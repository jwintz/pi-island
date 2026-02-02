//
//  PiPathFinder.swift
//  PiIsland
//
//  Finds the pi executable path using shell environment resolution
//  Based on VSCode's approach: spawn login shell and extract PATH
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "PiPathFinder")

/// Finds and caches the pi executable path
actor PiPathFinder {
    static let shared = PiPathFinder()

    private var cachedPath: String?
    private var cachedEnvironment: [String: String]?

    private init() {}

    /// Get the path to pi executable
    func getPiPath() -> String? {
        if let cached = cachedPath {
            return cached
        }

        // Check known locations FIRST to avoid spawning a shell (which can cause a terminal window to flash)
        logger.info("Checking known locations for pi executable")
        if let piPath = findPiInKnownLocations() {
            logger.info("Found pi in known location: \(piPath)")
            cachedPath = piPath
            return piPath
        }

        // Fallback: try to resolve the shell environment (VSCode-style approach)
        // This is slower and might show a terminal window, but captures custom PATHs
        logger.info("Known locations check failed, attempting shell environment resolution")
        let shellEnv = getShellEnvironment()

        if let path = shellEnv["PATH"] {
            logger.info("Resolved shell PATH: \(path)")
            // Use 'which' with the resolved PATH to find pi
            if let piPath = findExecutable("pi", inPath: path) {
                logger.info("Found pi via shell environment: \(piPath)")
                cachedPath = piPath
                cachedEnvironment = shellEnv
                return piPath
            }
        }

        logger.error("pi executable not found")
        return nil
    }

    /// Get the cached shell environment (includes PATH and other variables)
    nonisolated func getEnvironmentSync() -> [String: String] {
        // Return current process environment as fallback for sync contexts
        ProcessInfo.processInfo.environment
    }

    /// Get the cached shell environment (includes PATH and other variables)
    func getEnvironment() async -> [String: String] {
        if let cached = cachedEnvironment {
            return cached
        }
        let env = getShellEnvironment()
        cachedEnvironment = env
        return env
    }

    /// Check if pi is available
    func isPiAvailable() -> Bool {
        getPiPath() != nil
    }

    /// Clear the cached path (useful if pi was installed after app launch)
    func clearCache() {
        cachedPath = nil
        cachedEnvironment = nil
    }

    // MARK: - Shell Environment Resolution (VSCode-style)

    /// Resolve shell environment by spawning user's login shell
    /// This is the approach used by VSCode to get the full user environment
    private func getShellEnvironment() -> [String: String] {
        let homeDir = NSHomeDirectory()
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        logger.info("Resolving shell environment: shell=\(defaultShell)")

        // Use a unique marker to find our output in the shell output
        let marker = UUID().uuidString

        // Build the command to output environment with markers
        // Using printf to avoid shell echo differences
        let command = "printf '%s' '\(marker)' && env && printf '%s' '\(marker)'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: defaultShell)

        // Use -ilc for interactive login shell with command
        // tcsh uses -ic instead (doesn't support -l with -c)
        if defaultShell.contains("tcsh") || defaultShell.contains("csh") {
            process.arguments = ["-ic", command]
        } else {
            process.arguments = ["-ilc", command]
        }

        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)

        // Set minimal environment - the shell will load its own
        process.environment = [
            "HOME": homeDir,
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            "SHELL": defaultShell,
            "TERM": "xterm-256color",
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
            // Mark that we're resolving environment (like VSCode does)
            "PI_ISLAND_RESOLVING_ENVIRONMENT": "1"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        var environment: [String: String] = ProcessInfo.processInfo.environment

        do {
            try process.run()

            // Use a timeout to avoid hanging
            let timeout = DispatchTime.now() + .seconds(10)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: timeout)
            if result == .timedOut {
                logger.warning("Shell environment resolution timed out")
                process.terminate()
                return environment
            }

            let exitCode = process.terminationStatus
            logger.info("Shell exited with code \(exitCode)")

            // Log stderr for debugging
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let stderrText = String(data: stderrData, encoding: .utf8), !stderrText.isEmpty {
                // Only log non-empty stderr, and truncate if too long
                let truncated = stderrText.count > 500 ? String(stderrText.prefix(500)) + "..." : stderrText
                logger.debug("Shell stderr: \(truncated)")
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: stdoutData, encoding: .utf8) else {
                logger.warning("Failed to decode shell output")
                return environment
            }

            // Find content between markers
            let parts = output.components(separatedBy: marker)
            if parts.count >= 3 {
                let envOutput = parts[1]
                // Parse env output: KEY=VALUE lines
                for line in envOutput.components(separatedBy: "\n") {
                    if let equalIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalIndex])
                        let value = String(line[line.index(after: equalIndex)...])
                        if !key.isEmpty && !key.contains(" ") && key != "_" {
                            environment[key] = value
                        }
                    }
                }
                logger.info("Extracted \(environment.count) environment variables")
            } else {
                logger.warning("Could not find markers in shell output, parsing raw output")
                // Fallback: try to parse raw output
                for line in output.components(separatedBy: "\n") {
                    if let equalIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalIndex])
                        let value = String(line[line.index(after: equalIndex)...])
                        if !key.isEmpty && !key.contains(" ") && key != "_" {
                            environment[key] = value
                        }
                    }
                }
            }
        } catch {
            logger.error("Failed to run shell: \(error.localizedDescription)")
        }

        return environment
    }

    /// Find an executable in the given PATH
    private func findExecutable(_ name: String, inPath path: String) -> String? {
        let fm = FileManager.default
        let directories = path.components(separatedBy: ":")

        for dir in directories {
            let fullPath = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    // MARK: - Fallback: Known Locations

    /// Fallback method: check known installation locations
    private func findPiInKnownLocations() -> String? {
        let homeDir = NSHomeDirectory()
        let fm = FileManager.default

        var possiblePaths: [String] = [
            "/usr/local/bin/pi",
            "/opt/homebrew/bin/pi",
            "/usr/bin/pi",
            "\(homeDir)/.npm-global/bin/pi",
            "\(homeDir)/.npm/bin/pi",
            "\(homeDir)/.volta/bin/pi",
            "\(homeDir)/.bun/bin/pi",
            "\(homeDir)/.local/share/pnpm/pi",
        ]

        // Check nvm installations
        let nvmDir = "\(homeDir)/.nvm/versions/node"
        if fm.fileExists(atPath: nvmDir),
           let contents = try? fm.contentsOfDirectory(atPath: nvmDir) {
            let sorted = contents.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                possiblePaths.insert("\(nvmDir)/\(version)/bin/pi", at: 0)
            }
        }

        // Check fnm installations
        let fnmDir = "\(homeDir)/.fnm/node-versions"
        if fm.fileExists(atPath: fnmDir),
           let contents = try? fm.contentsOfDirectory(atPath: fnmDir) {
            let sorted = contents.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                possiblePaths.insert("\(fnmDir)/\(version)/installation/bin/pi", at: 0)
            }
        }

        // Check asdf installations
        let asdfDir = "\(homeDir)/.asdf/installs/nodejs"
        if fm.fileExists(atPath: asdfDir),
           let contents = try? fm.contentsOfDirectory(atPath: asdfDir) {
            let sorted = contents.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                possiblePaths.insert("\(asdfDir)/\(version)/bin/pi", at: 0)
            }
        }

        for path in possiblePaths {
            if fm.isExecutableFile(atPath: path) {
                logger.info("Found pi in known location: \(path)")
                return path
            }
        }

        return nil
    }
}
