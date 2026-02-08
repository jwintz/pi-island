---
title: Changelog
description: Release history and notable changes to Pi Island
navigation:
  icon: i-lucide-history
order: 99
---

All notable changes to Pi Island are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

:changelog-versions{:versions='[{"title":"Unreleased","description":""},{"title":"v0.5.0","date":"2026-02-08","description":"Notch UI overhaul: layout consistency, accessibility, performance","to":"https://github.com/jwintz/pi-island/releases/tag/v0.5.0"},{"title":"v0.4.1","date":"2026-02-06","description":"OAuth token auto-refresh for usage monitor","to":"https://github.com/jwintz/pi-island/releases/tag/v0.4.1"},{"title":"v0.4.0","date":"2026-02-05","description":"Usage Monitor with multi-provider support, battery optimizations","to":"https://github.com/jwintz/pi-island/releases/tag/v0.4.0"},{"title":"v0.3.0","date":"2026-02-03","description":"Bounce animation, update checker, slash commands, file references","to":"https://github.com/jwintz/pi-island/releases/tag/v0.3.0"},{"title":"v0.2.0","date":"2026-02-01","description":"Real-time session updates, terminal Pi detection","to":"https://github.com/jwintz/pi-island/releases/tag/v0.2.0"},{"title":"v0.1.0","date":"2026-01-31","description":"Initial release with RPC client, multi-session support, notch UI","to":"https://github.com/jwintz/pi-island/releases/tag/v0.1.0"}]'}

---

## Unreleased

---

## v0.5.0 - 2026-02-08

### Added
- Inline "No active sessions" guidance when no live sessions exist
- Hover feedback on session rows
- Tooltips on header buttons (usage toggle, settings)
- Escape key closes the notch
- Divider above historical sessions section
- Token/cost stats footer below chat input bar

### Changed
- Preserve usage view state when leaving and reentering the notch
- Move model selector from notch header to chat body header
- Make session/usage toggle always visible with icon reflecting current state
- Split NotchView.swift into NotchView, SessionsListView, and SettingsContentView
- Replace onTapGesture with Button on session rows for accessibility
- Move status color legend from settings to sessions list footer
- Move token/cost display from chat header to footer below input
- Use consistent "Sessions" label on all back buttons
- Only show search bar when session count exceeds threshold
- Reduce settings panel height to match content
- Activate application when notch opens for tooltip and keyboard support
- Cache filtered session lists and formatters for performance

### Removed
- Delete unused SettingsView.swift, dead view structs, commented-out debug prints
- Remove unused Combine import and viewModel dependency from SettingsContentView

---

## v0.4.1 - 2026-02-06

### Added
- OAuth token auto-refresh for all OAuth providers (Anthropic, GitHub Copilot, Google Gemini CLI, Google Antigravity, OpenAI Codex)
- OAuthTokenRefresher actor with file-locking coordination with Pi instances
- Runtime extraction of OAuth client credentials from Pi's installed JS files (no credentials in sources)

### Fixed
- Fix usage monitor requiring `pi login` every time tokens expire
- Fix credential cache not invalidating after token refresh

---

## v0.4.0 - 2026-02-05

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
- Shell environment resolution for Finder launches

### Changed
- Move usage display from menu bar to notch interface
- Simplify status bar menu to only show Quit option
- Rename headers to "Session Monitor" and "Usage Monitor"
- Version display uses centralized AppVersion
- Bundle script reads version from git tag

### Fixed
- Battery efficiency: mouse tracking only active near notch area
- Battery efficiency: usage monitoring only runs when view is displayed
- Session error indicator no longer persists after recovery
- Non-fatal errors during session resume no longer block the session

## v0.3.0 - 2026-02-03

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

---

## v0.2.0 - 2026-02-01

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

---

## v0.1.0 - 2026-01-31

Initial release of Pi Island.

### Added
- Core architecture with RPC client (PiRPCClient actor)
- Multi-session support (SessionManager + ManagedSession)
- Historical session loading from ~/.pi/agent/sessions/ JSONL
- Session resume via RPC commands
- Dynamic island UI with notch integration
- NotchView with open/close animations
- Sessions list showing live and historical sessions
- Chat view with markdown rendering and syntax highlighting
- Thinking messages display (collapsible with streaming)
- Model selector dropdown in chat header
- Settings panel (launch at login, show in dock)
- Menu bar status item
- Boot animation, hover-to-expand, click-outside-to-close
- Application icon with all resolutions
- Production .app bundle creation with signing and DMG

---

For the raw changelog file, see [CHANGELOG.md on GitHub](https://github.com/jwintz/pi-island/blob/main/CHANGELOG.md).
