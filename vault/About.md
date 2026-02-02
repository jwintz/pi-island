---
title: About Pi Island
description: Background and motivation for the Pi Island project
icon: i-lucide-info
order: 99
navigation:
  title: About
  icon: i-lucide-info
  order: 99
---

Pi Island is a passion project to create a native macOS experience for the Pi coding agent. Rather than living in a terminal window, Pi Island brings the agent to your notch area for always-available, ambient interaction.

## Motivation

The Pi coding agent is powerful but requires a terminal to interact with. Pi Island solves this by:

1. **Ambient presence**: Always visible in the notch, never hidden behind windows
2. **Non-intrusive notifications**: Subtle animations indicate activity without interrupting work
3. **Quick access**: One hover or click to check on your agent
4. **Session continuity**: Resume any session from any project instantly

## Design Philosophy

Pi Island follows several key principles:

### RPC Passthrough

Pi Island is a pure passthrough to the Pi RPC interface. It does not:

- Parse or re-encode messages unnecessarily
- Make additional API calls
- Store duplicate message history
- Add overhead beyond what Pi itself consumes

### Native Experience

Built with Swift and SwiftUI, Pi Island feels like a native macOS application:

- Proper accessory app behavior (no dock icon, no menu bar takeover)
- Respects system appearance and accessibility settings
- Uses FSEvents for efficient file watching
- Integrates with Login Items for auto-launch

### Minimal Footprint

Pi Island is designed to be lightweight:

- Single-process architecture
- Lazy RPC connections (only connects when needed)
- Efficient session file parsing
- No background polling - uses FSEvents for instant updates

## Credits

Pi Island is built on:

- [Pi coding agent](https://github.com/badlogic/pi-mono) by Mario Zechner
- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) for markdown rendering
- SwiftUI for the user interface
- FSEvents API for file system monitoring

## License

Pi Island is open source software. See the LICENSE file for details.
