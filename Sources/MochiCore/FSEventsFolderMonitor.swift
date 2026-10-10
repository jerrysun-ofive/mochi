import CoreServices
import Foundation

public struct FolderEvent: Sendable {
    public let path: String
    public let flags: FSEventStreamEventFlags
    public let eventID: FSEventStreamEventId

    public var requiresFullReconciliation: Bool {
        let mask = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagRootChanged)
        return flags & mask != 0
    }
}

public final class FSEventsFolderMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable ([FolderEvent]) -> Void

    private let paths: [String]
    private let latency: CFTimeInterval
    private let queue: DispatchQueue
    private let handler: Handler
    private var stream: FSEventStreamRef?

    public init(urls: [URL], latency: CFTimeInterval = 1, handler: @escaping Handler) {
        self.paths = urls.map(\.standardizedFileURL.path)
        self.latency = latency
        self.handler = handler
        self.queue = DispatchQueue(label: "app.mochi.fsevents", qos: .utility)
    }

    deinit { stop() }

    public func start(since eventID: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)) throws {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            nil,
            Self.callback,
            &context,
            paths as CFArray,
            eventID,
            latency,
            flags
        ) else { throw FolderMonitorError.creationFailed }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            stream = nil
            throw FolderMonitorError.startFailed
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, count, rawPaths, rawFlags, rawIDs in
        guard let info else { return }
        let monitor = Unmanaged<FSEventsFolderMonitor>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
        let events = (0..<min(count, paths.count)).map { index in
            FolderEvent(path: paths[index], flags: rawFlags[index], eventID: rawIDs[index])
        }
        monitor.handler(events)
    }
}

public enum FolderMonitorError: Error { case creationFailed, startFailed }
