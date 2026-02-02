---
title: Pi Island
description: A native macOS dynamic island interface for the Pi coding agent
layout: landing
navigation: false
---

::u-page-hero
---
title: Pi Island
description: A native macOS dynamic island interface for the Pi coding agent. Real-time session monitoring, ambient notifications, and seamless multi-session management - all from your notch.
links:
  - label: Get Started
    to: /home
    icon: i-lucide-arrow-right
    color: neutral
    size: xl
  - label: View on GitHub
    to: https://github.com/jwintz/pi-island
    icon: simple-icons-github
    color: neutral
    variant: outline
    size: xl
---
::

::u-page-grid{class="lg:grid-cols-3 max-w-(--ui-container) mx-auto px-4"}

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-2
to: /guide/usage
---
::::noir-image
---
src: /_raw/Assets/Screenshot1.png
alt: Dynamic island interface in the macOS notch
height: 240px
---
::::

#title
Dynamic Island Interface

#description
Pi Island lives in your MacBook's **notch area**. Hover to preview, click to expand. Subtle pulse animations notify you when Pi responds - all without interrupting your workflow.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /architecture/sessions
---
::::noir-image
---
src: https://images.unsplash.com/photo-1555066931-4365d14bab8c?auto=format&fit=crop&w=800&q=80
alt: Multi-session management interface
height: 240px
---
::::

#title
Multi-Session Management

#description
View all your Pi sessions across projects. **Green dots** for active, **yellow** for recent activity, **blue** when thinking. Resume any session instantly.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /architecture/file-watching
---
::::noir-image
---
src: https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=800&q=80
alt: Real-time file system monitoring
height: 240px
---
::::

#title
Real-Time Updates

#description
FSEvents-powered file watching with **100ms latency**. See terminal Pi activity instantly - no polling, no delays.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-2
to: /guide/usage
---
::::noir-image
---
src: /_raw/Assets/Screenshot2.png
alt: Rich chat interface with markdown rendering
height: 240px
---
::::

#title
Rich Chat Interface

#description
Full **Markdown rendering** with syntax-highlighted code blocks. Collapsible thinking messages, tool call inspection, and streaming responses. Model switching mid-conversation.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-2
to: /architecture/overview
---
::::noir-image
---
src: https://images.unsplash.com/photo-1531297484001-80022131f5a1?auto=format&fit=crop&w=800&q=80
alt: Native Swift and SwiftUI application
height: 240px
---
::::

#title
Native macOS Experience

#description
Built with **Swift** and **SwiftUI** for true native performance. Proper accessory app behavior - no dock icon, no menu bar takeover. Respects system appearance and accessibility settings.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /architecture/rpc
---
::::noir-image
---
src: https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=800&q=80
alt: RPC protocol architecture
height: 240px
---
::::

#title
Pure RPC Passthrough

#description
Zero overhead - Pi Island is a **pure passthrough** to Pi's RPC interface. No extra API calls, no duplicate storage.
:::

::

::div{class="h-24"}
::
