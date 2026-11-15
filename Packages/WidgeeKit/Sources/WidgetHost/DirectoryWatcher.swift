import Foundation
import CoreServices

/// Рекурсивное слежение за каталогом (FSEvents). Реагирует на manifest.json и *.js; события склеиваются на 0.3 с.
final class DirectoryWatcher: @unchecked Sendable {
    private final class Box {
        let onChange: @Sendable () -> Void
        init(_ f: @escaping @Sendable () -> Void) { onChange = f }
    }
    private var stream: FSEventStreamRef?
    private var box: Unmanaged<Box>?
    private let queue = DispatchQueue(label: "widgee.watcher")

    init(directory: URL, latency: Double = 0.3, onChange: @escaping @Sendable () -> Void) {
        let b = Unmanaged.passRetained(Box(onChange))
        box = b
        var ctx = FSEventStreamContext(version: 0, info: b.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let relevant = paths.prefix(count).contains {
                let name = ($0 as NSString).lastPathComponent
                return name == "manifest.json" || name.hasSuffix(".js")
            }
            if relevant { Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().onChange() }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, cb, &ctx, [directory.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
            stream = nil
        }
        box?.release(); box = nil
    }
    deinit { stop() }
}
