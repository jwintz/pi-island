# Pi Island

A native macOS Dynamic Island-style interface for the [Pi Coding Agent](https://github.com/mariozechner/pi-coding-agent). Pi Island provides a floating notch UI that gives you a glanceable view of your Pi agent's status with full chat capabilities.

## Features

### Core
- **Floating Notch UI** - Sits at the top of your screen, mimicking Dynamic Island
- **Full Chat Interface** - Send messages, receive streaming responses
- **Real-time Status** - See thinking, executing, idle states at a glance
- **Tool Execution** - Watch tool calls with live output streaming
- **Native macOS** - Built with SwiftUI, optimized for macOS 14+

### Session Management
- **Multi-session Support** - Manage multiple Pi sessions simultaneously
- **Session Resume** - Click any historical session to resume where you left off
- **Historical Sessions** - Browse recent sessions from ~/.pi/agent/sessions/
- **External Activity Detection** - Yellow indicator for sessions active in other terminals
- **Live Session Indicators** - Green dot for connected sessions

### Model & Provider
- **Model Selector** - Dropdown to switch between available models
- **Provider Grouping** - Models organized by provider
- **Thinking Level** - Adjustable reasoning depth for supported models

### Settings
- **Launch at Login** - Start Pi Island automatically
- **Show in Dock** - Toggle dock icon visibility
- **Menu Bar** - Quick access to quit

### UI Polish
- **Boot Animation** - Smooth expand/collapse on launch
- **Hover to Expand** - Natural interaction with notch area
- **Click Outside to Close** - Dismiss by clicking elsewhere
- **Auto-scroll** - Chat scrolls to latest message
- **Glass Effect** - Ultra-thin material background

## Architecture

Pi Island spawns Pi in RPC mode (`pi --mode rpc`) and communicates via stdin/stdout JSON protocol:

```
Pi Island (macOS app)
    |
    |--- stdin: Commands (prompt, switch_session, get_messages, etc.)
    |--- stdout: Events (message streaming, tool execution, etc.)
    |
    v
pi --mode rpc (child process)
```

## Requirements

- macOS 14.0+
- Pi Coding Agent installed (`npm install -g @mariozechner/pi-coding-agent`)
- Valid API key for your preferred provider

## Building

```bash
swift build
.build/debug/PiIsland
```

## Usage

1. Launch Pi Island
2. Hover over the notch area at the top of your screen to expand
3. Click a session to open chat, or click gear icon for settings
4. Type messages in the input bar to interact with Pi

### Status Indicators

- **Gray** - Disconnected / Historical session
- **Yellow** - Externally active (modified recently)
- **Orange** - Connecting
- **Green** - Connected and idle
- **Blue** - Thinking
- **Cyan** - Executing tool
- **Red** - Error

## File Structure

```
pi-island/
  Package.swift
  Sources/
    PiIsland/
      PiIslandApp.swift           # Entry point, AppDelegate, StatusBarController
      Core/
        EventMonitors.swift       # Global mouse event monitoring
        NotchGeometry.swift       # Geometry calculations
        NotchViewModel.swift      # State management
        NSScreen+Notch.swift      # Screen extensions
      UI/
        NotchView.swift           # Main SwiftUI view
        NotchShape.swift          # Animatable notch shape
        NotchWindowController.swift
        PiLogo.swift              # Pi logo shape
        SettingsView.swift        # Settings panel
      RPC/
        PiRPCClient.swift         # RPC process management
        RPCChatView.swift         # Chat UI components
        RPCTypes.swift            # Protocol types
        SessionManager.swift      # Session management
```

## License

MIT
