import Foundation
import CoreServices

/// Watches the user widgets folder (FSEvents, recursive) and calls `onChange` on the main queue, debounced.
final class CatalogWatcher: @unchecked Sendable {
    private final class Box {
        let fire: @Sendable () -> Void
        init(_ f: @escaping @Sendable () -> Void) { fire = f }
    }
    private var stream: FSEventStreamRef?
    private var box: Unmanaged<Box>?

    init(directory: URL, latency: Double = 0.5, onChange: @escaping @Sendable () -> Void) {
        let b = Unmanaged.passRetained(Box(onChange))
        box = b
        var ctx = FSEventStreamContext(version: 0, info: b.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().fire()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, cb, &ctx, [directory.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
    }

    deinit {
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s) }
        box?.release()
    }
}
