# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Documentation vault for lithos-based static site generation
- CHANGELOG.md following keepachangelog format

## [0.2.0] - 2026-02-01

### Added
- Real-time session updates via FSEvents file watching
- Dynamic sessions list updates (create/delete/modify)
- Terminal Pi activity detection with visual indicators
- Blue dot animation when Pi is thinking in terminal
- Yellow dot for recently modified external sessions
- Background RPC connection for instant session entry
- Activity timer for periodic state re-evaluation

### Changed
- Replaced polling with FSEvents for near-instant updates (~100ms latency)
- Session entry now shows messages immediately while RPC connects in background
- Improved JSONL parser to correctly handle `type: "message"` format
- Moved disk I/O out of computed properties for better performance

### Fixed
- Duplicate sessions appearing in list after resume
- Sessions showing 0 messages due to incorrect JSONL parsing
- FSEvents not detecting inode/xattr changes
- External updates being skipped for idle live sessions
- View not re-rendering when file modification dates change

## [0.1.0] - 2026-01-31

### Added
- Core architecture with RPC client (PiRPCClient actor)
- Multi-session support (SessionManager + ManagedSession)
- Historical session loading from ~/.pi/agent/sessions/ JSONL
- Session resume via RPC commands (switch_session + get_messages)
- NotchGeometry, NotchShape with proper corner radii
- NotchViewModel with mouse tracking via Combine
- NotchWindowController - full-width panel with proper event handling
- NotchView - SwiftUI view with open/close animations
- SessionsListView - shows live + historical sessions
- SessionChatView - chat UI with streaming
- PiLogo - custom SwiftUI Shape for Pi branding
- Menu bar status item (Quit only)
- Boot animation, hover-to-expand, click-outside-to-close
- Back button to exit chat and return to sessions list
- Model selector dropdown in chat header
- Thinking level badge (reasoning models only)
- Settings panel (launch at login, show in dock)
- Green dot for active sessions
- Auto-scroll to bottom when entering chat
- Proper @Observable / @Bindable observation chain
- Thinking messages display (collapsible with streaming)
- LSUIElement plist fix for proper accessory behavior
- Markdown rendering with syntax highlighting (MarkdownUI)
- Tool result syntax highlighting with full-width expandable code blocks
- Non-activating window behavior
- Custom main.swift entry point for SPM activation policy
- Application icon with all resolutions via .icon package + actool
- Shell environment resolution for Finder launches (VSCode-style approach)
- Non-activating floating panel behavior
- Production .app bundle creation script with signing and DMG

[Unreleased]: https://github.com/jwintz/pi-island/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jwintz/pi-island/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jwintz/pi-island/releases/tag/v0.1.0
