//
//  CredentialManager.swift
//  PiIsland
//
//  Manages credential loading and caching
//

import Foundation
import Security
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "CredentialManager")

/// Manages credentials for AI providers
actor CredentialManager {
    static let shared = CredentialManager()

    private var cache: [AIProvider: [String: Any]] = [:]
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 30 // 30 seconds

    /// Cached shell environment (loaded once from login shell)
    private var shellEnvironment: [String: String]?

    /// Get credentials for a provider
    func credentials(for provider: AIProvider) -> [String: Any]? {
        // Check cache validity
        if let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration,
           let cached = cache[provider] {
            return cached
        }

        // Load fresh credentials
        let creds = loadCredentials(for: provider)
        cache[provider] = creds
        cacheTimestamp = Date()
        return creds
    }

    /// Clear the credential cache
    func clearCache() {
        cache.removeAll()
        cacheTimestamp = nil
    }

    /// Load shell environment (for env var lookups when launched from Finder)
    private func getShellEnvironment() -> [String: String] {
        if let cached = shellEnvironment {
            return cached
        }

        // Use PiPathFinder's sync environment getter (which uses process env as fallback)
        // For better results, we resolve it ourselves using the same approach
        let env = resolveShellEnvironment()
        shellEnvironment = env
        return env
    }

    /// Resolve shell environment by spawning user's login shell
    /// This captures env vars like SYNTHETIC_API_KEY set in .zshrc/.bashrc
    private func resolveShellEnvironment() -> [String: String] {
        let homeDir = NSHomeDirectory()
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let marker = UUID().uuidString
        let command = "printf '%s' '\(marker)' && env && printf '%s' '\(marker)'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: defaultShell)

        if defaultShell.contains("tcsh") || defaultShell.contains("csh") {
            process.arguments = ["-ic", command]
        } else {
            process.arguments = ["-ilc", command]
        }

        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)
        process.environment = [
            "HOME": homeDir,
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            "SHELL": defaultShell,
            "TERM": "xterm-256color",
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
        ]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment

        do {
            try process.run()

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                process.waitUntilExit()
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + .seconds(5)) == .timedOut {
                process.terminate()
                return environment
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: stdoutData, encoding: .utf8) else {
                return environment
            }

            let parts = output.components(separatedBy: marker)
            if parts.count >= 3 {
                let envOutput = parts[1]
                for line in envOutput.components(separatedBy: "\n") {
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
            // Fall back to process environment
        }

        return environment
    }

    /// Load credentials from all possible sources
    private func loadCredentials(for provider: AIProvider) -> [String: Any]? {
        // Primary: pi's auth.json
        if let creds = loadFromAuthJson(for: provider) {
            return creds
        }

        // Fallbacks based on provider
        switch provider {
        case .anthropic:
            return loadAnthropicFromKeychain()
        case .copilot:
            return loadCopilotFromLegacy()
        case .geminiCli:
            return loadGeminiFromLegacy()
        case .codex:
            return loadCodexFromLegacy()
        case .synthetic:
            return loadSyntheticFromEnv()
        default:
            return nil
        }
    }

    /// Load Synthetic API key from environment variable (uses shell environment)
    private func loadSyntheticFromEnv() -> [String: Any]? {
        let env = getShellEnvironment()
        guard let apiKey = env["SYNTHETIC_API_KEY"],
              !apiKey.isEmpty else {
            return nil
        }
        return ["access": apiKey]
    }

    /// Load from pi's auth.json
    private func loadFromAuthJson(for provider: AIProvider) -> [String: Any]? {
        let authPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/auth.json")

        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json[provider.authKey] as? [String: Any]
    }

    /// Load Anthropic credentials from macOS Keychain
    private func loadAnthropicFromKeychain() -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let scopes = oauth["scopes"] as? [String],
              scopes.contains("user:profile"),
              let token = oauth["accessToken"] as? String else {
            return nil
        }

        return ["access": token]
    }

    /// Load Copilot credentials from legacy locations
    private func loadCopilotFromLegacy() -> [String: Any]? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let paths = [
            home.appendingPathComponent(".config/github-copilot/hosts.json"),
            home.appendingPathComponent(".github-copilot/hosts.json")
        ]

        for path in paths {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Normalize host keys to lowercase
            var normalized: [String: [String: String]] = [:]
            for (host, entry) in json {
                guard let entry = entry as? [String: String] else { continue }
                normalized[host.lowercased()] = entry
            }

            // Try preferred hosts first
            for preferred in ["github.com", "api.github.com"] {
                if let entry = normalized[preferred],
                   let token = entry["oauth_token"] ?? entry["user_token"] ?? entry["github_token"] ?? entry["token"] {
                    return ["access": token]
                }
            }

            // Fall back to any host
            for entry in normalized.values {
                if let token = entry["oauth_token"] ?? entry["user_token"] ?? entry["github_token"] ?? entry["token"] {
                    return ["access": token]
                }
            }
        }

        return nil
    }

    /// Load Gemini CLI credentials from legacy location
    private func loadGeminiFromLegacy() -> [String: Any]? {
        let path = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")

        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            return nil
        }

        return ["access": token]
    }

    /// Load Codex credentials from legacy location
    private func loadCodexFromLegacy() -> [String: Any]? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        // Try CODEX_HOME or ~/.codex
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .flatMap { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")

        let path = codexHome.appendingPathComponent("auth.json")

        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Try various credential formats
        if let key = json["OPENAI_API_KEY"] as? String {
            return ["access": key]
        }

        if let tokens = json["tokens"] as? [String: Any],
           let token = tokens["access_token"] as? String {
            var result: [String: Any] = ["access": token]
            if let accountId = tokens["account_id"] as? String {
                result["accountId"] = accountId
            }
            return result
        }

        return nil
    }

    /// Check if provider has credentials available
    func hasCredentials(for provider: AIProvider) -> Bool {
        credentials(for: provider) != nil
    }

    /// Get access token for a provider, refreshing if expired
    func accessToken(for provider: AIProvider) async -> String? {
        // For OAuth providers, try to refresh expired tokens first
        if let refreshedCreds = await OAuthTokenRefresher.shared.refreshIfNeeded(provider: provider) {
            // Invalidate cache so next credentials() call picks up fresh data
            cache.removeValue(forKey: provider)
            cacheTimestamp = nil

            // Special case: Copilot usage API (api.github.com) uses the GitHub OAuth
            // token (stored as "refresh"), not the Copilot session token (stored as "access").
            if provider == .copilot {
                return refreshedCreds.refresh
            }

            return refreshedCreds.access
        }

        // Fallback: read from credentials (non-OAuth providers, or refresh not applicable)
        guard let creds = credentials(for: provider) else { return nil }

        // Special case: Copilot uses the GitHub OAuth token for the usage API
        if provider == .copilot {
            return creds["refresh"] as? String ??
                   creds["access"] as? String
        }

        return creds["access"] as? String ??
               creds["accessToken"] as? String ??
               creds["token"] as? String ??
               creds["key"] as? String
    }

    /// Get a specific field from credentials
    func credentialField(_ field: String, for provider: AIProvider) -> String? {
        credentials(for: provider)?[field] as? String
    }
}
