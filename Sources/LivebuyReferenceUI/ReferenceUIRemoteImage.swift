import Foundation
import ImageIO
import UIKit

// MARK: - Remote still-image pipeline (rb-ios-remote-image-downsampling)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "iOS 遠端靜態圖依顯示尺寸降採樣載入（記憶體快取有成本上限、專用磁碟快取、離開畫面即取消）"
//   § "LivebuyReferenceUI RemoteStillImageView 記憶體快取與防 stale 圖"
//
// Everything `RemoteStillImageView` needs to turn a URL into pixels lives here, with no
// third-party dependency (ImageIO + URLSession + URLCache + NSCache only):
//
//   • `ReferenceUIImageSizing`     — PURE: which pixel size to request for a frame, how far
//                                    to downsample a given source, cache key / cost.
//   • `ReferenceUIImageDecoder`    — ImageIO thumbnail decode at (roughly) the requested
//                                    size instead of the source's full resolution.
//   • `ReferenceUIImageCache`      — cost-bounded memory cache, keyed by URL + request size.
//   • `ReferenceUIImageDataSource` — the module's OWN `URLSession` + OWN on-disk `URLCache`
//                                    holding the original bytes. Never touches the host's
//                                    `URLSession.shared` / `URLCache.shared`.
//   • `ReferenceUIImageSessionDelegate` — answers that session's authentication challenges:
//                                    an image host is never handed a credential from a
//                                    credential storage, nor a client identity.
//   • `ReferenceUIImagePipeline`   — fetch → decode → cache, cancellable; the production
//                                    `ReferenceUIImageLoading`. Views talk to the protocol, so
//                                    tests substitute a fake that never leaves the process.
//   • `ReferenceUIImagePrefetch`   — fire-and-forget cache warm.
//
// iOS-14-safe throughout. Parity: Android `StillImageEngine.kt` / `RemoteStillImage.kt`
// (`rb-android-remote-image-loader-library`).

// MARK: - Sizing (pure)

/// A size in device PIXELS (not points).
struct ReferenceUIImagePixelSize: Hashable {
    let width: Int
    let height: Int

    /// `true` when this size is at least `other` on BOTH edges.
    func covers(_ other: ReferenceUIImagePixelSize) -> Bool {
        width >= other.width && height >= other.height
    }
}

enum ReferenceUIImageSizing {
    /// Smallest request edge: below this a finer bucket saves nothing worth its own entry.
    static let minEdge = 64
    /// Largest request edge — a guard against a runaway frame, far above any real one.
    static let maxEdge = 4096
    /// Bytes per decoded pixel (ImageIO hands back 8-bit RGBA / BGRA bitmaps).
    static let bytesPerPixel = 4

    /// PURE: round a frame edge UP to a coarse ladder (64, 96, 128, 192, 256, 384, 512, … —
    /// powers of two and their ×1.5 midpoints), clamped to `minEdge...maxEdge`. Frames that
    /// differ by a few pixels then share one cache entry; rounding is always UP so the decoded
    /// image still covers the frame. Same ladder as Android `stillImageBucketPx`.
    static func bucket(_ px: Int) -> Int {
        if px <= minEdge { return minEdge }
        if px >= maxEdge { return maxEdge }
        var pow = minEdge
        while pow < px { pow *= 2 }
        let midpoint = pow / 4 * 3
        return midpoint >= px ? midpoint : pow
    }

    /// PURE: the pixel size to request for a view whose bounds are `bounds` (points) on a
    /// `displayScale`× screen, drawn magnified by up to `zoomScale` (1 for every surface except
    /// the zoom lightbox). `nil` while the view has no area yet — nothing is requested until
    /// layout has given it one.
    static func requestSize(
        bounds: CGSize, displayScale: CGFloat, zoomScale: CGFloat
    ) -> ReferenceUIImagePixelSize? {
        guard bounds.width > 0, bounds.height > 0,
              bounds.width.isFinite, bounds.height.isFinite else { return nil }
        let factor = max(displayScale, 1) * max(zoomScale, 1)
        func edge(_ points: CGFloat) -> Int {
            let px = (points * factor).rounded(.up)
            return bucket(px >= CGFloat(maxEdge) ? maxEdge : Int(px))
        }
        return ReferenceUIImagePixelSize(width: edge(bounds.width), height: edge(bounds.height))
    }

    /// PURE: how to decode a `source`-sized image for a `request`-sized frame. The result keeps
    /// the source aspect ratio and is at least `request` on BOTH edges whenever the source is
    /// large enough; a source smaller than the request on either edge is decoded at its
    /// original size (never upscaled). `maxPixelSize` is the LONGEST edge to hand to ImageIO.
    static func decodePlan(
        source: ReferenceUIImagePixelSize, request: ReferenceUIImagePixelSize
    ) -> (maxPixelSize: Int, isFullResolution: Bool) {
        let longest = max(source.width, source.height)
        guard source.width > 0, source.height > 0 else { return (max(longest, 1), true) }
        let scale = max(Double(request.width) / Double(source.width),
                        Double(request.height) / Double(source.height))
        guard scale < 1 else { return (longest, true) }
        // +1 absorbs ImageIO's rounding of the shorter edge so it cannot land one pixel short.
        let target = Int((Double(longest) * scale).rounded(.up)) + 1
        return target >= longest ? (longest, true) : (target, false)
    }

    /// PURE: memory-cache key — the same URL at two request sizes is two entries.
    static func cacheKey(url: URL, size: ReferenceUIImagePixelSize) -> String {
        "\(size.width)x\(size.height)|\(url.absoluteString)"
    }

    /// PURE: memory cost (bytes) of a decoded bitmap.
    static func cost(of size: ReferenceUIImagePixelSize) -> Int {
        size.width * size.height * bytesPerPixel
    }

    /// PURE: the memory cache's total cost limit for a device with `physicalMemory` bytes of
    /// RAM — one sixteenth of it, kept between 32 MB and 128 MB.
    static func memoryCostLimit(physicalMemory: UInt64) -> Int {
        let megabyte: UInt64 = 1024 * 1024
        return Int(min(max(physicalMemory / 16, 32 * megabyte), 128 * megabyte))
    }
}

// MARK: - Decoded image

/// One decoded image plus what is needed to decide whether it is good enough for a frame.
final class ReferenceUIDecodedImage {
    /// Scale-1 image: `image.size` equals `pixelSize` (the long-standing contract of
    /// `RemoteStillImageView.onImageLoaded`, which reports this size).
    let image: UIImage
    let pixelSize: ReferenceUIImagePixelSize
    /// The request size this image was decoded for.
    let request: ReferenceUIImagePixelSize
    /// `true` when the image was decoded at the source's original resolution.
    let isFullResolution: Bool

    init(image: UIImage, pixelSize: ReferenceUIImagePixelSize,
         request: ReferenceUIImagePixelSize, isFullResolution: Bool) {
        self.image = image
        self.pixelSize = pixelSize
        self.request = request
        self.isFullResolution = isFullResolution
    }

    /// `true` when this image may stand as THE decode result for a `need`-sized frame: it is
    /// the whole source, or it was decoded for / is at least as large as that frame. An image
    /// that does not cover may only be shown as a stand-in while a larger one loads.
    func covers(_ need: ReferenceUIImagePixelSize) -> Bool {
        isFullResolution || request.covers(need) || pixelSize.covers(need)
    }
}

// MARK: - Decoder

enum ReferenceUIImageDecoder {
    /// The source's pixel size as it will be DISPLAYED (EXIF orientations 5–8 swap the edges).
    static func sourcePixelSize(_ source: CGImageSource) -> ReferenceUIImagePixelSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5
            ? ReferenceUIImagePixelSize(width: height, height: width)
            : ReferenceUIImagePixelSize(width: width, height: height)
    }

    /// Decode `data` for a `request`-sized frame via an ImageIO thumbnail — the bitmap that
    /// reaches memory is the downsampled one, the full-resolution bitmap is never materialised.
    /// `nil` when `data` is not a decodable image.
    static func decode(_ data: Data, request: ReferenceUIImagePixelSize) -> ReferenceUIDecodedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let sourceSize = sourcePixelSize(source) else { return nil }
        let plan = ReferenceUIImageSizing.decodePlan(source: sourceSize, request: request)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: plan.maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return ReferenceUIDecodedImage(
            image: UIImage(cgImage: cgImage, scale: 1, orientation: .up),
            pixelSize: ReferenceUIImagePixelSize(width: cgImage.width, height: cgImage.height),
            request: request,
            isFullResolution: plan.isFullResolution)
    }
}

// MARK: - Memory cache

/// Process-wide decoded-image cache for reference-ui remote still images, bounded by total
/// decoded bytes. Keyed by URL + request size; also remembers, per URL, the largest entry it
/// holds so a view can show something immediately before layout has told it its frame.
final class ReferenceUIImageCache {
    static let shared = ReferenceUIImageCache(
        totalCostLimit: ReferenceUIImageSizing.memoryCostLimit(
            physicalMemory: ProcessInfo.processInfo.physicalMemory))

    private let entries = NSCache<NSString, ReferenceUIDecodedImage>()
    private let largestKeys = NSCache<NSURL, NSString>()
    private let lock = NSLock()

    init(totalCostLimit: Int) {
        entries.totalCostLimit = totalCostLimit
        largestKeys.countLimit = 2048
    }

    var totalCostLimit: Int { entries.totalCostLimit }

    /// The entry stored for exactly this URL + request size, if still in memory.
    func image(for url: URL, size: ReferenceUIImagePixelSize) -> ReferenceUIDecodedImage? {
        entries.object(forKey: ReferenceUIImageSizing.cacheKey(url: url, size: size) as NSString)
    }

    /// The largest entry still in memory for this URL at ANY request size.
    func largestImage(for url: URL) -> ReferenceUIDecodedImage? {
        guard let key = largestKeys.object(forKey: url as NSURL) else { return nil }
        return entries.object(forKey: key)
    }

    func store(_ entry: ReferenceUIDecodedImage, for url: URL) {
        let key = ReferenceUIImageSizing.cacheKey(url: url, size: entry.request) as NSString
        lock.lock()
        defer { lock.unlock() }
        let current = largestImage(for: url)
        entries.setObject(entry, forKey: key, cost: ReferenceUIImageSizing.cost(of: entry.pixelSize))
        let isLargest = current.map {
            ReferenceUIImageSizing.cost(of: entry.pixelSize) >= ReferenceUIImageSizing.cost(of: $0.pixelSize)
        } ?? true
        if isLargest { largestKeys.setObject(key, forKey: url as NSURL) }
    }

    /// Decode `data` for a `size`-sized frame and store it under `url` + `size`. Returns the
    /// entry, or `nil` (no cache write) when `data` is missing / undecodable. SINGLE choke point
    /// for the decode + cache-write step — display loads and prefetches both end up here.
    @discardableResult
    func decodeAndStore(
        _ data: Data?, for url: URL, size: ReferenceUIImagePixelSize
    ) -> ReferenceUIDecodedImage? {
        guard let data = data,
              let entry = ReferenceUIImageDecoder.decode(data, request: size) else { return nil }
        store(entry, for: url)
        return entry
    }

    /// Test-only. Production code never calls this. Empties the cache.
    func _resetForTesting() {
        entries.removeAllObjects()
        largestKeys.removeAllObjects()
    }
}

// MARK: - Cancellation

protocol ReferenceUIImageCancellable: AnyObject {
    func cancel()
}

/// A cancellable unit of work: remembers that it was cancelled and forwards the cancel to
/// whatever inner work has been attached (attaching after a cancel cancels immediately).
final class ReferenceUIImageRequest: ReferenceUIImageCancellable {
    private let lock = NSLock()
    private var cancelled = false
    private var inner: ReferenceUIImageCancellable?
    private var onCancel: (() -> Void)?

    init(onCancel: (() -> Void)? = nil) {
        self.onCancel = onCancel
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ work: ReferenceUIImageCancellable) {
        lock.lock()
        let alreadyCancelled = cancelled
        if !alreadyCancelled { inner = work }
        lock.unlock()
        if alreadyCancelled { work.cancel() }
    }

    func cancel() {
        lock.lock()
        let first = !cancelled
        cancelled = true
        let work = inner
        let callback = onCancel
        inner = nil
        onCancel = nil
        lock.unlock()
        guard first else { return }
        work?.cancel()
        callback?()
    }
}

// MARK: - Bytes: network + disk cache

/// Supplies the ORIGINAL bytes of a remote image. `completion` may run on any queue.
protocol ReferenceUIImageDataFetching: AnyObject {
    func fetch(_ url: URL, completion: @escaping (Data?) -> Void) -> ReferenceUIImageCancellable
    /// Drop whatever is stored on disk for `url` (its bytes turned out not to be an image).
    func discard(_ url: URL)
}

/// Production byte source: the module's OWN `URLSession` (the URL loading system's implicit
/// caching is switched off for it) plus the module's OWN on-disk `URLCache`, which this class
/// reads and writes EXPLICITLY. Storing explicitly makes the disk cache independent of the
/// response's cache headers — a CDN that sends no `Cache-Control` (or `no-store`) is cached
/// just the same — at the price of ignoring HTTP revalidation, so an entry is simply treated
/// as expired after `maxAge`. Concurrent fetches of one URL share a single download.
final class ReferenceUIImageDataSource: ReferenceUIImageDataFetching {
    static let diskCapacity = 150 * 1024 * 1024
    static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60
    static let storedAtHeader = "X-LB-RefUI-Stored-At"
    /// Idle timeout of an image request (seconds) — same as Android's image fetch.
    static let requestTimeout: TimeInterval = 10

    static let shared = ReferenceUIImageDataSource(
        session: makeSession(), diskCache: makeDiskCache())

    /// One download in progress. `id` is the flight's own identity: a URL can be downloaded
    /// again while a CANCELLED earlier download of the same URL has yet to report back, and
    /// that late report must not be mistaken for the new download's.
    private struct Flight {
        let id: UUID
        let task: URLSessionDataTask
        var waiters: [UUID: (Data?) -> Void]
    }

    private let session: URLSession
    private let diskCache: URLCache
    private let maxAge: TimeInterval
    private let now: () -> Date
    private let queue = DispatchQueue(label: "tv.livebuy.referenceui.image-data")
    private var flights: [URL: Flight] = [:]

    init(session: URLSession, diskCache: URLCache,
         maxAge: TimeInterval = ReferenceUIImageDataSource.defaultMaxAge,
         now: @escaping () -> Date = Date.init) {
        self.session = session
        self.diskCache = diskCache
        self.maxAge = maxAge
        self.now = now
    }

    /// A session of the module's own; `configuration` is a parameter so tests can add a stub
    /// `URLProtocol`. The URL loading system's own caching is disabled — this class owns it —
    /// and image requests neither send nor store cookies (the host's shared cookie storage is
    /// not read or written). The session has no credential storage and its delegate answers
    /// every authentication challenge (`ReferenceUIImageSessionDelegate`), so an image host is
    /// never handed a credential taken from a credential storage, nor a client identity.
    /// NOT covered, on purpose: user info written in the image URL ITSELF
    /// (`https://user:pass@host/a.png`). The system's HTTP loader answers that host's HTTP
    /// challenge with it below the delegate — the delegate is not asked. Those are the URL's
    /// own credentials going to the URL's own host, not anything the host app stored; stripping
    /// them would turn an image that loads into one that does not. Downloads keep using
    /// completion-handler tasks: the delegate is consulted for challenges only.
    static func makeSession(
        configuration: URLSessionConfiguration = .default,
        delegate: ReferenceUIImageSessionDelegate = ReferenceUIImageSessionDelegate()
    ) -> URLSession {
        URLSession(configuration: configure(configuration), delegate: delegate, delegateQueue: nil)
    }

    /// Apply the image session's settings to `configuration` (returned for inspection).
    @discardableResult
    static func configure(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        return configuration
    }

    /// PURE: the ONLY response headers written to disk — the content type (if any) and this
    /// class's own timestamp. Everything else the server sent (`Set-Cookie`, authentication
    /// headers, …) is dropped.
    static func storedHeaders(contentType: String?, storedAt: TimeInterval) -> [String: String] {
        var headers = [storedAtHeader: String(storedAt)]
        if let contentType = contentType { headers["Content-Type"] = contentType }
        return headers
    }

    /// The module's own on-disk cache under the app's Caches directory (the OS may purge it).
    static func makeDiskCache(directoryName: String = "tv.livebuy.referenceui.images") -> URLCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return URLCache(memoryCapacity: 0, diskCapacity: diskCapacity,
                        directory: caches?.appendingPathComponent(directoryName, isDirectory: true))
    }

    /// PURE: whether a finished download is worth keeping on disk.
    static func shouldStore(statusCode: Int?, byteCount: Int) -> Bool {
        guard let statusCode = statusCode else { return false }
        return (200..<300).contains(statusCode) && byteCount > 0
    }

    /// PURE: whether a disk entry stamped `storedAt` (seconds since 1970; `nil` = unstamped) is
    /// still usable at `now`. Unstamped or future-dated entries are not.
    static func isFresh(storedAt: TimeInterval?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let storedAt = storedAt else { return false }
        let age = now.timeIntervalSince1970 - storedAt
        return age >= 0 && age <= maxAge
    }

    func fetch(_ url: URL, completion: @escaping (Data?) -> Void) -> ReferenceUIImageCancellable {
        let id = UUID()
        queue.async { [weak self] in
            guard let self = self else { return completion(nil) }
            self.start(url, id: id, completion: completion)
        }
        return ReferenceUIImageRequest { [weak self] in
            self?.queue.async { self?.removeWaiter(id, for: url) }
        }
    }

    func discard(_ url: URL) {
        diskCache.removeCachedResponse(for: URLRequest(url: url))
    }

    /// The bytes stored on disk for `url`, if present and not older than `maxAge`.
    func storedData(for url: URL) -> Data? {
        guard let cached = diskCache.cachedResponse(for: URLRequest(url: url)) else { return nil }
        let stamp = (cached.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: Self.storedAtHeader)
            .flatMap(TimeInterval.init)
        return Self.isFresh(storedAt: stamp, now: now(), maxAge: maxAge) ? cached.data : nil
    }

    // Runs on `queue`.
    private func start(_ url: URL, id: UUID, completion: @escaping (Data?) -> Void) {
        if flights[url] != nil {
            flights[url]?.waiters[id] = completion
            return
        }
        if let data = storedData(for: url) {
            completion(data)
            return
        }
        let flightID = UUID()
        let task = session.dataTask(with: URLRequest(url: url)) { [weak self] data, response, error in
            self?.queue.async {
                self?.finish(url, flightID: flightID, data: error == nil ? data : nil, response: response)
            }
        }
        flights[url] = Flight(id: flightID, task: task, waiters: [id: completion])
        task.resume()
    }

    // Runs on `queue`. Only the flight that is CURRENTLY registered for `url` may finish it: a
    // cancelled download still reports back (with an error), possibly after a new download of
    // the same URL has started — that stale report is dropped.
    private func finish(_ url: URL, flightID: UUID, data: Data?, response: URLResponse?) {
        guard let flight = flights[url], flight.id == flightID else { return }
        flights[url] = nil
        if let data = data { store(data, response: response, for: url) }
        flight.waiters.values.forEach { $0(data) }
    }

    // Runs on `queue`. The last waiter leaving cancels the download.
    private func removeWaiter(_ id: UUID, for url: URL) {
        guard var flight = flights[url], flight.waiters.removeValue(forKey: id) != nil else { return }
        if flight.waiters.isEmpty {
            flights[url] = nil
            flight.task.cancel()
        } else {
            flights[url] = flight
        }
    }

    private func store(_ data: Data, response: URLResponse?, for url: URL) {
        let http = response as? HTTPURLResponse
        guard Self.shouldStore(statusCode: http?.statusCode, byteCount: data.count),
              let http = http else { return }
        let headers = Self.storedHeaders(
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            storedAt: now().timeIntervalSince1970)
        guard let stamped = HTTPURLResponse(
            url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)
        else { return }
        diskCache.storeCachedResponse(
            CachedURLResponse(response: stamped, data: data, storagePolicy: .allowed),
            for: URLRequest(url: url))
    }
}

// MARK: - Authentication challenges

/// What the image session does with one authentication challenge.
enum ReferenceUIImageChallengeResponse: Equatable {
    /// Let the system handle it exactly as if there were no delegate.
    case systemDefault
    /// A PROXY asked for a credential: offer the one the host stored for that proxy, if any.
    case proxyCredential
    /// Go on WITHOUT a credential / client identity.
    case continueWithoutCredential
    /// Fail the request.
    case cancel
}

/// PURE decision table for the image session's authentication challenges.
enum ReferenceUIImageChallengePolicy {
    /// - Server trust (TLS certificate evaluation) is ALWAYS left to the system — never
    ///   weakened, never skipped, also when the challenging party is a proxy.
    /// - A proxy's challenge is not the image host's: the first one is answered with the
    ///   credential stored for that proxy (so a network that needs an authenticated proxy keeps
    ///   working); a repeated one (the credential was refused) falls back to the system, which
    ///   — the session having no credential storage — has nothing to offer.
    /// - A client-certificate request goes on without an identity: a server that merely
    ///   *offers* client authentication still serves the image, one that requires it fails the
    ///   handshake.
    /// - Every other method (HTTP Basic / Digest / NTLM / Negotiate / form / unknown) fails the
    ///   request: the image host is not offered a credential by this session.
    static func response(
        authenticationMethod: String, isProxy: Bool, previousFailureCount: Int
    ) -> ReferenceUIImageChallengeResponse {
        if authenticationMethod == NSURLAuthenticationMethodServerTrust { return .systemDefault }
        if isProxy { return previousFailureCount == 0 ? .proxyCredential : .systemDefault }
        if authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            return .continueWithoutCredential
        }
        return .cancel
    }
}

/// The image session's delegate. It exists ONLY to answer authentication challenges —
/// downloads are completion-handler tasks, so no data / completion callback is routed here.
final class ReferenceUIImageSessionDelegate: NSObject, URLSessionTaskDelegate {
    typealias Reply = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    private let proxyCredentialProvider: (URLProtectionSpace) -> URLCredential?

    /// `proxyCredentialProvider`: the credential stored for a PROXY's protection space.
    /// Production reads the shared credential storage — for proxy protection spaces only.
    init(proxyCredentialProvider: @escaping (URLProtectionSpace) -> URLCredential? = {
        URLCredentialStorage.shared.defaultCredential(for: $0)
    }) {
        self.proxyCredentialProvider = proxyCredentialProvider
    }

    /// Connection-level challenges (server trust, client certificate, NTLM, Negotiate).
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping Reply) {
        answer(challenge, completionHandler)
    }

    /// Request-level challenges (HTTP Basic / Digest, proxy, …).
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping Reply) {
        answer(challenge, completionHandler)
    }

    func answer(_ challenge: URLAuthenticationChallenge, _ reply: Reply) {
        let space = challenge.protectionSpace
        let response = ReferenceUIImageChallengePolicy.response(
            authenticationMethod: space.authenticationMethod, isProxy: space.isProxy(),
            previousFailureCount: challenge.previousFailureCount)
        switch response {
        case .systemDefault:
            reply(.performDefaultHandling, nil)
        case .proxyCredential:
            if let credential = proxyCredentialProvider(space) {
                reply(.useCredential, credential)
            } else {
                reply(.performDefaultHandling, nil)
            }
        case .continueWithoutCredential:
            reply(.useCredential, nil)
        case .cancel:
            reply(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Loader

/// What `RemoteStillImageView` loads through. Every method is called on the main thread and
/// `load`'s `completion` is delivered on the main thread.
protocol ReferenceUIImageLoading: AnyObject {
    /// SYNCHRONOUS memory lookup: the largest image currently in memory for `url`. The caller
    /// decides (via `covers`) whether it is final or only a stand-in.
    func memoryImage(for url: URL) -> ReferenceUIDecodedImage?
    /// Load `url` decoded for a `size` frame. `completion` receives `nil` on failure and is not
    /// called after the returned handle is cancelled.
    func load(url: URL, size: ReferenceUIImagePixelSize,
              completion: @escaping (ReferenceUIDecodedImage?) -> Void) -> ReferenceUIImageCancellable
    /// Warm the caches for `url` at `size` without drawing anything.
    func prefetch(url: URL, size: ReferenceUIImagePixelSize)
}

/// Production loader: bytes from `ReferenceUIImageDataSource` (disk cache, then network),
/// downsampled decode on a serial background queue, result into `ReferenceUIImageCache`.
final class ReferenceUIImagePipeline: ReferenceUIImageLoading {
    static let shared = ReferenceUIImagePipeline(
        cache: .shared, fetcher: ReferenceUIImageDataSource.shared)

    private let cache: ReferenceUIImageCache
    private let fetcher: ReferenceUIImageDataFetching
    private let decodeQueue: DispatchQueue
    private let deliver: (@escaping () -> Void) -> Void
    private let lock = NSLock()
    private var prefetching = Set<URL>()

    init(cache: ReferenceUIImageCache, fetcher: ReferenceUIImageDataFetching,
         decodeQueue: DispatchQueue = DispatchQueue(
            label: "tv.livebuy.referenceui.image-decode", qos: .userInitiated),
         deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.cache = cache
        self.fetcher = fetcher
        self.decodeQueue = decodeQueue
        self.deliver = deliver
    }

    func memoryImage(for url: URL) -> ReferenceUIDecodedImage? {
        cache.largestImage(for: url)
    }

    func load(url: URL, size: ReferenceUIImagePixelSize,
              completion: @escaping (ReferenceUIDecodedImage?) -> Void) -> ReferenceUIImageCancellable {
        let request = ReferenceUIImageRequest()
        let finish: (ReferenceUIDecodedImage?) -> Void = { [deliver] entry in
            deliver { if !request.isCancelled { completion(entry) } }
        }
        if let hit = cache.image(for: url, size: size) {
            finish(hit)
            return request
        }
        request.attach(fetcher.fetch(url) { [weak self] data in
            self?.decodeQueue.async {
                guard let self = self, !request.isCancelled else { return }
                finish(self.decode(data, url: url, size: size))
            }
        })
        return request
    }

    func prefetch(url: URL, size: ReferenceUIImagePixelSize) {
        guard cache.largestImage(for: url) == nil else { return }
        // A URL whose prefetch is still in flight is not requested a second time (the 5s
        // products poll hands the same list over and over).
        lock.lock()
        let isNew = prefetching.insert(url).inserted
        lock.unlock()
        guard isNew else { return }
        _ = load(url: url, size: size) { [weak self] _ in
            self?.finishPrefetch(url)
        }
    }

    private func finishPrefetch(_ url: URL) {
        lock.lock()
        prefetching.remove(url)
        lock.unlock()
    }

    // Runs on `decodeQueue`. A second load of the same key that queued up behind this one finds
    // the entry instead of decoding again.
    private func decode(_ data: Data?, url: URL, size: ReferenceUIImagePixelSize) -> ReferenceUIDecodedImage? {
        if let hit = cache.image(for: url, size: size) { return hit }
        let entry = cache.decodeAndStore(data, for: url, size: size)
        if entry == nil, data != nil { fetcher.discard(url) }
        return entry
    }
}

// MARK: - Prefetch

/// Fire-and-forget background prefetch (`rb-ios-product-image-loading-polish`) — call ahead of
/// a product entering the now-introducing / narrating window so its card thumbnail is already
/// decoded by the time a `RemoteStillImageView` needs it. Warms the memory entry for the
/// product-card thumbnail size plus the on-disk original bytes; a surface showing the same URL
/// in a larger frame decodes again from disk (no second download). NEVER touches any
/// `UIImageView` / SwiftUI `@State`.
enum ReferenceUIImagePrefetch {
    /// The frame (points) prefetched images are decoded for: the "now introducing" product
    /// card's image area.
    static let thumbnailPointSize = CGSize(width: 100, height: 100)

    static func prefetch(
        url rawURL: URL,
        pointSize: CGSize = thumbnailPointSize,
        displayScale: CGFloat = UIScreen.main.scale,
        loader: ReferenceUIImageLoading = ReferenceUIImagePipeline.shared
    ) {
        // Same http→https upgrade `RemoteStillImageView` applies, so both use one cache key.
        let url = rawURL.lbHTTPSUpgraded
        guard let size = ReferenceUIImageSizing.requestSize(
            bounds: pointSize, displayScale: displayScale, zoomScale: 1) else { return }
        loader.prefetch(url: url, size: size)
    }
}
