//
//  OAuthTokenRefresher.swift
//  PiIsland
//
//  Handles OAuth token refresh for AI providers.
//  Mirrors the refresh logic from @mariozechner/pi-ai OAuth providers.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "OAuthTokenRefresher")

/// OAuth credentials stored in auth.json
struct OAuthCredentials: Sendable {
    var type: String
    var access: String
    var refresh: String
    var expires: Double // milliseconds since epoch
    var extra: [String: String] // projectId, email, accountId, enterpriseUrl, etc.

    /// Whether the access token has expired
    var isExpired: Bool {
        Date().timeIntervalSince1970 * 1000 >= expires
    }

    /// Convert back to dictionary for JSON serialization
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "access": access,
            "refresh": refresh,
            "expires": expires,
        ]
        for (key, value) in extra {
            dict[key] = value
        }
        return dict
    }

    /// Parse from auth.json dictionary
    static func from(_ dict: [String: Any]) -> OAuthCredentials? {
        guard let type = dict["type"] as? String, type == "oauth",
              let access = dict["access"] as? String,
              let refresh = dict["refresh"] as? String,
              let expires = dict["expires"] as? Double else {
            return nil
        }

        var extra: [String: String] = [:]
        for (key, value) in dict {
            if key == "type" || key == "access" || key == "refresh" || key == "expires" { continue }
            if let strValue = value as? String {
                extra[key] = strValue
            }
        }

        return OAuthCredentials(
            type: type,
            access: access,
            refresh: refresh,
            expires: expires,
            extra: extra
        )
    }
}

/// OAuth client credentials extracted from Pi's installed JS files at runtime.
/// These are public OAuth client IDs (not secrets) used by the official Pi agent.
struct OAuthClientConfig: Sendable {
    let anthropicClientId: String
    let anthropicTokenURL: String

    let copilotTokenURL: String

    let geminiClientId: String
    let geminiClientSecret: String
    let googleTokenURL: String

    let antigravityClientId: String
    let antigravityClientSecret: String

    let codexClientId: String
    let codexTokenURL: String
}

/// Handles OAuth token refresh for all supported providers.
/// Uses file locking on auth.json to coordinate with Pi instances.
actor OAuthTokenRefresher {
    static let shared = OAuthTokenRefresher()

    /// Client config loaded from Pi's JS files
    private var clientConfig: OAuthClientConfig?

    /// Track in-flight refresh tasks to avoid duplicate refreshes
    private var refreshTasks: [AIProvider: Task<OAuthCredentials?, Error>] = [:]

    /// Load client credentials from Pi's installed OAuth JS files
    private func getClientConfig() -> OAuthClientConfig? {
        if let config = clientConfig {
            return config
        }
        let config = Self.loadClientConfigFromPi()
        clientConfig = config
        return config
    }

    /// Locate Pi's pi-ai OAuth JS files and extract client credentials
    private static func loadClientConfigFromPi() -> OAuthClientConfig? {
        guard let piAiDir = findPiAiOAuthDir() else {
            logger.error("Could not find Pi's pi-ai OAuth directory")
            return nil
        }

        let anthropicFile = piAiDir.appendingPathComponent("anthropic.js")
        let copilotFile = piAiDir.appendingPathComponent("github-copilot.js")
        let geminiFile = piAiDir.appendingPathComponent("google-gemini-cli.js")
        let antigravityFile = piAiDir.appendingPathComponent("google-antigravity.js")
        let codexFile = piAiDir.appendingPathComponent("openai-codex.js")

        // Extract base64-encoded values from the JS source
        guard let anthropicId = extractBase64Constant(from: anthropicFile, named: "CLIENT_ID") else {
            logger.error("Failed to extract Anthropic CLIENT_ID")
            return nil
        }
        let anthropicTokenURL = extractStringConstant(from: anthropicFile, named: "TOKEN_URL")
            ?? "https://console.anthropic.com/v1/oauth/token"

        let copilotTokenURL: String
        // Copilot token URL is constructed dynamically, extract the pattern
        if let copilotJS = try? String(contentsOf: copilotFile, encoding: .utf8),
           copilotJS.contains("copilot_internal/v2/token") {
            copilotTokenURL = "https://api.github.com/copilot_internal/v2/token"
        } else {
            copilotTokenURL = "https://api.github.com/copilot_internal/v2/token"
        }

        guard let geminiId = extractBase64Constant(from: geminiFile, named: "CLIENT_ID"),
              let geminiSecret = extractBase64Constant(from: geminiFile, named: "CLIENT_SECRET") else {
            logger.error("Failed to extract Gemini CLI credentials")
            return nil
        }
        let googleTokenURL = extractStringConstant(from: geminiFile, named: "TOKEN_URL")
            ?? "https://oauth2.googleapis.com/token"

        guard let antigravityId = extractBase64Constant(from: antigravityFile, named: "CLIENT_ID"),
              let antigravitySecret = extractBase64Constant(from: antigravityFile, named: "CLIENT_SECRET") else {
            logger.error("Failed to extract Antigravity credentials")
            return nil
        }

        let codexId = extractPlainConstant(from: codexFile, named: "CLIENT_ID")
            ?? "app_EMoamEEZ73f0CkXaXp7hrann"
        let codexTokenURL = extractStringConstant(from: codexFile, named: "TOKEN_URL")
            ?? "https://auth.openai.com/oauth/token"

        let config = OAuthClientConfig(
            anthropicClientId: anthropicId,
            anthropicTokenURL: anthropicTokenURL,
            copilotTokenURL: copilotTokenURL,
            geminiClientId: geminiId,
            geminiClientSecret: geminiSecret,
            googleTokenURL: googleTokenURL,
            antigravityClientId: antigravityId,
            antigravityClientSecret: antigravitySecret,
            codexClientId: codexId,
            codexTokenURL: codexTokenURL
        )

        logger.info("Loaded OAuth client config from Pi installation")
        return config
    }

    /// Find Pi's pi-ai OAuth directory by locating the pi executable
    private static func findPiAiOAuthDir() -> URL? {
        let fm = FileManager.default
        let homeDir = NSHomeDirectory()

        // Strategy: find pi-coding-agent's node_modules containing pi-ai
        // Check nvm installations first (most common)
        let nvmDir = "\(homeDir)/.nvm/versions/node"
        if fm.fileExists(atPath: nvmDir),
           let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                let oauthDir = "\(nvmDir)/\(version)/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/utils/oauth"
                if fm.fileExists(atPath: oauthDir) {
                    return URL(fileURLWithPath: oauthDir)
                }
            }
        }

        // Check fnm installations
        let fnmDir = "\(homeDir)/.fnm/node-versions"
        if fm.fileExists(atPath: fnmDir),
           let versions = try? fm.contentsOfDirectory(atPath: fnmDir) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                let oauthDir = "\(fnmDir)/\(version)/installation/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/utils/oauth"
                if fm.fileExists(atPath: oauthDir) {
                    return URL(fileURLWithPath: oauthDir)
                }
            }
        }

        // Check global npm locations
        let globalPaths = [
            "/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/utils/oauth",
            "/opt/homebrew/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/utils/oauth",
            "\(homeDir)/.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/utils/oauth",
        ]

        for path in globalPaths {
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    /// Extract a base64-encoded constant from a JS file: `const NAME = decode("BASE64");`
    private static func extractBase64Constant(from file: URL, named name: String) -> String? {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        // Pattern: const NAME = decode("BASE64VALUE");
        let pattern = #"const \#(name) = decode\("([A-Za-z0-9+/=]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return nil
        }

        let base64 = String(content[range])
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    /// Extract a plain string constant from a JS file: `const NAME = "VALUE";`
    private static func extractPlainConstant(from file: URL, named name: String) -> String? {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        let pattern = #"const \#(name) = "([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return String(content[range])
    }

    /// Extract a URL string constant from a JS file
    private static func extractStringConstant(from file: URL, named name: String) -> String? {
        return extractPlainConstant(from: file, named: name)
    }

    /// Refresh the access token for the given provider if expired.
    /// Returns updated credentials, or nil if refresh is not applicable/failed.
    func refreshIfNeeded(provider: AIProvider) async -> OAuthCredentials? {
        // Read current credentials from auth.json
        guard let currentCreds = readCredentials(for: provider) else {
            return nil
        }

        // If token is still valid, return as-is
        if !currentCreds.isExpired {
            return currentCreds
        }

        // Check if there's already a refresh in progress for this provider
        if let existingTask = refreshTasks[provider] {
            return try? await existingTask.value
        }

        // Start a new refresh task
        let task = Task<OAuthCredentials?, Error> {
            let result = await refreshWithLock(provider: provider)
            return result
        }

        refreshTasks[provider] = task
        let result = try? await task.value
        refreshTasks.removeValue(forKey: provider)
        return result
    }

    /// Perform the token refresh with file-level coordination
    private func refreshWithLock(provider: AIProvider) async -> OAuthCredentials? {
        let authPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/auth.json")
        let lockPath = authPath.appendingPathExtension("lock")

        // Acquire file lock (simple file-based lock)
        let acquired = acquireLock(lockPath)
        defer {
            if acquired {
                releaseLock(lockPath)
            }
        }

        // Re-read after acquiring lock (another process may have refreshed)
        if let freshCreds = readCredentials(for: provider), !freshCreds.isExpired {
            logger.info("Token for \(provider.rawValue) already refreshed by another process")
            return freshCreds
        }

        guard let creds = readCredentials(for: provider) else {
            logger.warning("No credentials found for \(provider.rawValue) during refresh")
            return nil
        }

        // Perform the actual refresh
        guard let newCreds = await performRefresh(provider: provider, credentials: creds) else {
            return nil
        }

        // Write updated credentials to auth.json
        writeCredentials(newCreds, for: provider, authPath: authPath)

        logger.info("Successfully refreshed token for \(provider.rawValue)")
        return newCreds
    }

    /// Read credentials for a specific provider from auth.json
    private func readCredentials(for provider: AIProvider) -> OAuthCredentials? {
        let authPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/auth.json")

        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerDict = json[provider.authKey] as? [String: Any] else {
            return nil
        }

        return OAuthCredentials.from(providerDict)
    }

    /// Write updated credentials back to auth.json
    private func writeCredentials(_ creds: OAuthCredentials, for provider: AIProvider, authPath: URL) {
        do {
            var json: [String: Any] = [:]

            if let data = try? Data(contentsOf: authPath),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = existing
            }

            json[provider.authKey] = creds.toDictionary()

            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: authPath, options: .atomic)

            // Ensure proper permissions (600)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: authPath.path
            )
        } catch {
            logger.error("Failed to write updated credentials: \(error.localizedDescription)")
        }
    }

    // MARK: - File Locking

    private func acquireLock(_ lockPath: URL) -> Bool {
        let maxRetries = 10
        var retryDelay: UInt32 = 100_000 // 100ms

        for _ in 0..<maxRetries {
            let fd = open(lockPath.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
            if fd >= 0 {
                close(fd)
                return true
            }

            // Check if lock is stale (older than 30 seconds)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: lockPath.path),
               let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > 30 {
                try? FileManager.default.removeItem(at: lockPath)
                continue
            }

            usleep(retryDelay)
            retryDelay = min(retryDelay * 2, 10_000_000) // max 10s
        }

        logger.warning("Failed to acquire lock after \(maxRetries) retries")
        return false
    }

    private func releaseLock(_ lockPath: URL) {
        try? FileManager.default.removeItem(at: lockPath)
    }

    // MARK: - Provider-Specific Refresh

    private func performRefresh(provider: AIProvider, credentials: OAuthCredentials) async -> OAuthCredentials? {
        switch provider {
        case .anthropic:
            return await refreshAnthropic(credentials)
        case .copilot:
            return await refreshCopilot(credentials)
        case .geminiCli:
            return await refreshGeminiCli(credentials)
        case .antigravity:
            return await refreshAntigravity(credentials)
        case .codex:
            return await refreshCodex(credentials)
        default:
            // Providers without OAuth refresh (synthetic, kiro, zai)
            return nil
        }
    }

    // MARK: - Anthropic

    private func refreshAnthropic(_ creds: OAuthCredentials) async -> OAuthCredentials? {
        guard let config = getClientConfig() else { return nil }

        let body = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": config.anthropicClientId,
            "refresh_token": creds.refresh,
        ])

        guard let body = body else { return nil }

        var request = URLRequest(url: URL(string: config.anthropicTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Double else {
                logger.error("Anthropic token refresh failed")
                return nil
            }

            let refreshToken = json["refresh_token"] as? String ?? creds.refresh
            let expiresAt = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000 - 5 * 60 * 1000

            return OAuthCredentials(
                type: "oauth",
                access: accessToken,
                refresh: refreshToken,
                expires: expiresAt,
                extra: creds.extra
            )
        } catch {
            logger.error("Anthropic refresh error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - GitHub Copilot

    private func refreshCopilot(_ creds: OAuthCredentials) async -> OAuthCredentials? {
        // Copilot uses the GitHub OAuth token (stored as "refresh") to get a Copilot session token
        let domain = creds.extra["enterpriseUrl"] ?? "github.com"
        let tokenURL = "https://api.\(domain)/copilot_internal/v2/token"

        guard let url = URL(string: tokenURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(creds.refresh)", forHTTPHeaderField: "Authorization")
        request.setValue("GitHubCopilotChat/0.35.0", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode/1.107.0", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.35.0", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String,
                  let expiresAt = json["expires_at"] as? Double else {
                logger.error("Copilot token refresh failed")
                return nil
            }

            return OAuthCredentials(
                type: "oauth",
                access: token,
                refresh: creds.refresh, // GitHub OAuth token doesn't change
                expires: expiresAt * 1000 - 5 * 60 * 1000,
                extra: creds.extra
            )
        } catch {
            logger.error("Copilot refresh error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Google Gemini CLI

    private func refreshGeminiCli(_ creds: OAuthCredentials) async -> OAuthCredentials? {
        guard let config = getClientConfig() else { return nil }
        return await refreshGoogleOAuth(
            creds,
            clientId: config.geminiClientId,
            clientSecret: config.geminiClientSecret,
            tokenURL: config.googleTokenURL
        )
    }

    // MARK: - Google Antigravity

    private func refreshAntigravity(_ creds: OAuthCredentials) async -> OAuthCredentials? {
        guard let config = getClientConfig() else { return nil }
        return await refreshGoogleOAuth(
            creds,
            clientId: config.antigravityClientId,
            clientSecret: config.antigravityClientSecret,
            tokenURL: config.googleTokenURL
        )
    }

    /// Shared Google OAuth refresh (used by both Gemini CLI and Antigravity)
    private func refreshGoogleOAuth(
        _ creds: OAuthCredentials,
        clientId: String,
        clientSecret: String,
        tokenURL: String
    ) async -> OAuthCredentials? {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: creds.refresh),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]

        guard let body = components.percentEncodedQuery?.data(using: .utf8) else { return nil }
        guard let url = URL(string: tokenURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Double else {
                logger.error("Google OAuth token refresh failed")
                return nil
            }

            let refreshToken = json["refresh_token"] as? String ?? creds.refresh
            let expiresAt = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000 - 5 * 60 * 1000

            return OAuthCredentials(
                type: "oauth",
                access: accessToken,
                refresh: refreshToken,
                expires: expiresAt,
                extra: creds.extra
            )
        } catch {
            logger.error("Google OAuth refresh error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OpenAI Codex

    private func refreshCodex(_ creds: OAuthCredentials) async -> OAuthCredentials? {
        guard let config = getClientConfig() else { return nil }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: creds.refresh),
            URLQueryItem(name: "client_id", value: config.codexClientId),
        ]

        guard let body = components.percentEncodedQuery?.data(using: .utf8) else { return nil }
        guard let url = URL(string: config.codexTokenURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let refreshToken = json["refresh_token"] as? String,
                  let expiresIn = json["expires_in"] as? Double else {
                logger.error("Codex token refresh failed")
                return nil
            }

            let expiresAt = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000

            // Extract accountId from JWT
            var extra = creds.extra
            if let accountId = extractCodexAccountId(from: accessToken) {
                extra["accountId"] = accountId
            }

            return OAuthCredentials(
                type: "oauth",
                access: accessToken,
                refresh: refreshToken,
                expires: expiresAt,
                extra: extra
            )
        } catch {
            logger.error("Codex refresh error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Extract accountId from OpenAI JWT token
    private func extractCodexAccountId(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
        // Pad to multiple of 4
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String,
              !accountId.isEmpty else {
            return nil
        }

        return accountId
    }
}
