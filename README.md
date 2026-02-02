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

### Development (Debug)

```bash
swift build
.build/debug/PiIsland
```

### Production (App Bundle)

Create a proper macOS `.app` bundle with icon and LSUIElement support:

```bash
./scripts/bundle.sh
```

This generates `Pi Island.app` with:
- Proper app icon from `pi-island.icon` (Xcode 15+ Icon Composer format)
- `LSUIElement: true` - no dock icon by default, no terminal on launch
- All resources bundled correctly
- Login shell environment extraction (works when launched from Finder)

### Creating a DMG for Distribution

To distribute the app with proper codesigning (to avoid Gatekeeper warnings), you should sign it with a Developer ID Application certificate and notarize it with Apple.

Find your signing identity:
```bash
security find-identity -p codesigning -v
```

Build and sign:
```bash
# Build + ad-hoc sign + create DMG (for local/trusted distribution)
./scripts/bundle.sh --sign --dmg

# Build + sign with Developer ID + create DMG (for public distribution)
./scripts/bundle.sh --sign-id "Developer ID Application: Julien Wintz (TEAM_ID)" --dmg
```

This creates `Pi-Island-0.1.0.dmg`. To completely remove the "Apple could not verify..." warning for other users, you must notarize the DMG:

```bash
export APPLE_ID="your@email.com"
export APPLE_PASSWORD="app-specific-password"
export APPLE_TEAM_ID="YOUR_TEAM_ID"

./scripts/notarize.sh Pi-Island-0.1.0.dmg
```

You can verify the result with:
```bash
spctl -a -vv -t install "Pi-Island-0.1.0.dmg"
```

**Note:** Without a Developer ID certificate and notarization, recipients may see a "damaged" error or a security warning. They can bypass this by right-clicking the app and selecting **Open**, or by running:
```bash
xattr -cr "/Applications/Pi Island.app"
```

### Installation

From DMG:
1. Open `Pi-Island-0.1.0.dmg`
2. Drag `Pi Island` to the `Applications` folder

Or manually:
```bash
cp -R "Pi Island.app" /Applications/
```

### Auto-launch at Login

1. Open **System Settings > General > Login Items**
2. Click **+** and add **Pi Island** from Applications

The app will launch silently without opening a terminal window.

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
