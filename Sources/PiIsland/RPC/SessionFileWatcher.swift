//
//  SessionFileWatcher.swift
//  PiIsland
//
//  Watches the sessions directory for file changes using FSEvents for real-time updates
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "SessionFileWatcher")

// Debug file logging
private func debugLog(_ message: String) {
    let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi-island-debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] [FSEvents] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

/// Watches the Pi sessions directory for changes using FSEvents
@MainActor
final class SessionFileWatcher {
    /// Callback when a session file is created
    var onSessionCreated: ((URL) -> Void)?

    /// Callback when a session file is modified
    var onSessionModified: ((URL) -> Void)?

    /// Callback when a session file is deleted
    var onSessionDeleted: ((URL) -> Void)?

    // MARK: - Private

    private var eventStream: FSEventStreamRef?
    private var isWatching = false
    private var knownFiles: [String: (date: Date, size: UInt64)] = [:]

    private let sessionsDirectory: URL

    // MARK: - Initialization

    init() {
        self.sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/sessions")
    }

    // MARK: - Public API

    /// Start watching the sessions directory
    func startWatching() {
        guard !isWatching else { return }

        // Ensure directory exists
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else {
            logger.warning("Sessions directory does not exist: \(self.sessionsDirectory.path)")
            return
        }

        // Scan initial state
        scanDirectory()

        // Set up FSEvents stream
        setupFSEventsStream()

        isWatching = true
        logger.info("Started watching sessions directory with FSEvents")
    }

    /// Stop watching
    func stopWatching() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        isWatching = false
        logger.info("Stopped watching sessions directory")
    }

    // MARK: - FSEvents Setup

    private func setupFSEventsStream() {
        let pathsToWatch = [sessionsDirectory.path] as CFArray

        // Context to pass self to the callback
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create the stream with low latency for real-time updates
        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,  // 100ms latency - very responsive
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            logger.error("Failed to create FSEvents stream")
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    // MARK: - Change Detection

    fileprivate func handleFSEvent(paths: [String], flags: [UInt32]) {
        for (index, path) in paths.enumerated() {
            let flag = flags[index]

            // Only process .jsonl files
            guard path.hasSuffix(".jsonl") else { continue }

            let url = URL(fileURLWithPath: path)

            // Check event type
            let isRemoved = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
            let isCreated = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isModified = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let isRenamed = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
            let isInodeMetaMod = (flag & UInt32(kFSEventStreamEventFlagItemInodeMetaMod)) != 0
            let isXattrMod = (flag & UInt32(kFSEventStreamEventFlagItemXattrMod)) != 0

            // Treat inode/xattr changes as potential modifications too
            let isPotentiallyModified = isModified || isInodeMetaMod || isXattrMod

            if isRemoved {
                if knownFiles[path] != nil {
                    knownFiles.removeValue(forKey: path)
                    logger.debug("Session file deleted: \(path)")
                    onSessionDeleted?(url)
                }
            } else if isCreated || isRenamed {
                // Check if file exists and is new to us
                if let attrs = fileAttributes(at: path) {
                    if knownFiles[path] == nil {
                        knownFiles[path] = attrs
                        logger.debug("Session file created: \(path)")
                        onSessionCreated?(url)
                    }
                }
            } else if isPotentiallyModified {
                // Check if file actually changed (size or date)
                if let attrs = fileAttributes(at: path) {
                    let known = knownFiles[path]
                    if known == nil || attrs.date > known!.date || attrs.size != known!.size {
                        knownFiles[path] = attrs
                        logger.debug("Session file modified: \(path)")
                        onSessionModified?(url)
                    }
                }
            }
        }
    }

    private func fileAttributes(at path: String) -> (date: Date, size: UInt64)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? UInt64 else {
            return nil
        }
        return (modDate, size)
    }

    private func scanDirectory() {
        knownFiles = [:]

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return
        }

        for projectDir in projectDirs {
            guard projectDir.hasDirectoryPath else { continue }

            if let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) {
                for file in sessionFiles where file.pathExtension == "jsonl" {
                    if let attrs = fileAttributes(at: file.path) {
                        knownFiles[file.path] = attrs
                    }
                }
            }
        }

        logger.info("Scanned \(self.knownFiles.count) session files")
    }
}

// MARK: - FSEvents Callback

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }

    let watcher = Unmanaged<SessionFileWatcher>.fromOpaque(info).takeUnretainedValue()

    // Convert paths
    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    // Convert flags to array
    var flags: [UInt32] = []
    for i in 0..<numEvents {
        flags.append(eventFlags[i])
    }

    // Dispatch to main actor
    Task { @MainActor in
        watcher.handleFSEvent(paths: paths, flags: flags)
    }
}
