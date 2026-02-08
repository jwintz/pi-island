//
//  AppVersion.swift
//  PiIsland
//
//  Single source of truth for app version
//

import Foundation

/// App version information
enum AppVersion {
    /// Hardcoded version - update this when releasing
    /// This is the fallback when not running from a bundled .app
    private static let hardcodedVersion = "0.5.0"

    /// The current app version (e.g., "0.4.0")
    static var current: String {
        // Try Info.plist first (when running as .app bundle)
        if let plistVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           plistVersion != "0.0.0" {
            return plistVersion
        }
        // Fall back to hardcoded version (when running from swift build)
        return hardcodedVersion
    }

    /// The current build number (e.g., "1")
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Full version string (e.g., "0.4.0 (1)")
    static var full: String {
        "\(current) (\(build))"
    }

    /// Display string for UI (e.g., "Pi Island v0.4.0")
    static var display: String {
        "Pi Island v\(current)"
    }
}
