# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-02-08

### Added
- Inline "No active sessions" guidance when no live sessions exist
- Hover feedback on session rows (brightened background on mouse over)
- Tooltips on header buttons (usage toggle, settings)
- Escape key closes the notch
- Divider above historical sessions section for visual separation
- Token/cost stats footer below chat input bar

### Changed
- Preserve usage view state when leaving and reentering the notch
- Move model selector from notch header to chat body header
- Make session/usage toggle always visible with icon reflecting current state
- Split NotchView.swift into NotchView, SessionsListView, and SettingsContentView
- Replace onTapGesture with Button on session rows for accessibility
- Replace showsIndicators parameter with .scrollIndicators(.hidden) modifier
- Replace lowercased().contains() with localizedStandardContains() for session search
- Replace DispatchQueue.main.asyncAfter with structured Task.sleep in view handlers
- Extract duplicated back-button into NotchBackButton component
- Cache RelativeDateTimeFormatter as static property instead of allocating per row
- Cache filtered session lists in @State with onChange instead of recomputing in body
- Change injected viewModel from var to let in view structs
- Move status color legend from settings to sessions list footer
- Move token/cost display from chat header to footer below input
- Center usage monitor "Updated" footer text
- Use consistent "Sessions" label on all back buttons
- Only show search bar when session count exceeds threshold
- Reduce settings panel height to match content
- Activate application when notch opens for tooltip and keyboard support

### Removed
- Delete unused SettingsView.swift (superseded by SettingsContentView)
- Delete dead ActivityIndicator, PulseDot, and ProcessingSpinner views
- Remove unused Combine import from NotchView
- Remove status legend and viewModel dependency from SettingsContentView
- Remove commented-out debug print statements

## [0.4.1] - 2026-02-06

### Added
- OAuth token auto-refresh for all OAuth providers (Anthropic, GitHub Copilot, Google Gemini CLI, Google Antigravity, OpenAI Codex)
- OAuthTokenRefresher actor with file-locking coordination with Pi instances
- Runtime extraction of OAuth client credentials from Pi's installed JS files (no credentials in sources)

### Fixed
- Fix usage monitor requiring `pi login` every time tokens expire
- Fix credential cache not invalidating after token refresh

## [0.4.0] - 2026-02-05

### Added
- AI Usage Monitor with support for multiple providers:
  - Anthropic (Claude): 5-hour and weekly quotas with extra usage tracking
  - GitHub Copilot: Monthly premium interactions quota
  - Google Gemini CLI: Pro and Flash model quotas
  - Google Antigravity: Per-model quotas for all available models
  - Synthetic: Subscription, search/hr, and tool call quotas
- Usage view accessible via chart icon in sessions header
- Progress bars with linear pace markers showing expected vs actual usage
- Period bounds display with start/end times and elapsed/remaining duration
- Pace comparison indicators (arrows when ahead/behind linear usage)
- Multi-source credential loading (auth.json, env vars, keychain, legacy configs)

- Notifications for warning (80%) and critical (95%) usage thresholds
- Automatic refresh with configurable intervals (only when usage view is displayed)
- Shell environment resolution for Finder launches (captures env vars from login shell)
- Usage monitor documentation in vault

### Changed
- Move usage display from menu bar to notch interface
- Simplify status bar menu to only show Quit option
- Rename "Sessions" header to "Session Monitor"
- Rename "AI Usage" header to "Usage Monitor"
- Version display now uses centralized AppVersion (hardcoded fallback for debug builds)
- Bundle script reads version from git tag

### Fixed
- Battery efficiency: mouse tracking only active near notch area
- Battery efficiency: usage monitoring only runs when view is displayed
- Session error indicator no longer persists after recovery
- Non-fatal errors during session resume no longer block the session

## [0.3.0] - 2026-02-03

### Added
- Pi icon bounce animation when agent completes a response
- Automatic update checker via GitHub releases API
- Monospaced font theme for chat messages
- Slash command completion with keyboard navigation
- File reference completion (@file syntax)
- Session search/filter in sessions list
- Token count and cost display in chat header
- New session button with folder picker
- Session delete button for historical sessions
- External display support (notch moves when lid closes)
- Documentation site via Lithos static generator

### Changed
- Improved dot indicator alignment in message views
- Cleaner landing page with icon-based feature cards

### Fixed
- Bounce animation now uses scale effect instead of translation
- Navigation structure for documentation vault

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

[Unreleased]: https://github.com/jwintz/pi-island/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/jwintz/pi-island/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/jwintz/pi-island/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/jwintz/pi-island/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jwintz/pi-island/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jwintz/pi-island/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jwintz/pi-island/releases/tag/v0.1.0
