<div align="center">

# ⚡ Elysium Vanguard — Screen Mirror Studio

**Low-latency P2P screen mirroring & recording between macOS and Android**

[![Platform](https://img.shields.io/badge/macOS-14%2B-00E5FF?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Platform](https://img.shields.io/badge/Android-14%2B-00E676?style=flat-square&logo=android&logoColor=white)](https://developer.android.com/)
[![WebRTC](https://img.shields.io/badge/WebRTC-P2P-E040FB?style=flat-square&logo=webrtc&logoColor=white)](https://webrtc.org/)
[![License](https://img.shields.io/badge/License-Proprietary-333?style=flat-square)](./LICENSE)

<br/>

*Real-time Android screen streaming to macOS with PIP compositing, neon annotations, and HEVC recording — all over LAN with zero cloud dependency.*

</div>

---

## Architecture

```
┌─────────────────────────┐         LAN (TCP:9999 + WebRTC)         ┌──────────────────────────┐
│     Android Sender      │ ◄══════════════════════════════════════► │     macOS Director       │
│    (Honor Magic V2)     │                                         │    (Apple Silicon)       │
│                         │    ┌─────────────────────────────────┐   │                          │
│  MediaProjection        │    │  Signaling: JSON-over-TCP       │   │  ScreenCaptureKit        │
│  → ScreenCapturerHook   │    │  Media: WebRTC VP8/HW           │   │  → MetalCompositor       │
│  → WebRTC PeerConn      │────│  Metadata: DataChannel          │───│  → AVAssetRecorder       │
│  → DataChannel (fold)   │    │  Discovery: Bonjour/NSD         │   │  → AudioMixer            │
│                         │    └─────────────────────────────────┘   │  → EphemeralCanvas       │
└─────────────────────────┘                                         └──────────────────────────┘
```

## Features

### macOS Director
- **Screen Capture** — 60fps via ScreenCaptureKit with GPU acceleration
- **3-Pass Metal Compositor** — Mac screen + Android PIP + Neon annotations
- **HEVC Recording** — H.265 up to 8K with AAC-LC 256kbps audio
- **Dynamic PIP** — Cubic-eased transitions for fold state morphing
- **Ephemeral Annotations** — Neon glow strokes baked directly into MP4
- **System Audio Mixing** — ScreenCaptureKit audio bridged to AVAudioEngine
- **Auto-Discovery** — Zero-config Bonjour browser with auto-reconnect
- **Cyberpunk Dashboard** — Real-time telemetry: FPS, P2P status, fold state
- **Floating HUD** — Glassmorphism toolbar with record, annotate, spotlight, color picker
- **Hotkeys** — `⌘⌥1/2/3` for PIP layout switching

### Android Sender
- **Hardware Capture** — MediaProjection → EGL → WebRTC (zero software copies)
- **Fold State Propagation** — WindowInfoTracker → DataChannel → Mac PIP morph
- **Orientation Tracking** — Real-time screen rotation sync
- **Premium Haptics** — Taptic Engine composition API patterns
- **Foreground Service** — Android 14+ compliant background capture
- **Cyberpunk UI** — Grid background, neon glow, radar animations, telemetry panel

## Tech Stack

| Layer | macOS | Android |
|-------|-------|---------|
| **UI** | SwiftUI + AppKit | Jetpack Compose + Material3 |
| **Capture** | ScreenCaptureKit (SCStream) | MediaProjection + EGL |
| **Compositing** | Metal + Core Image | — |
| **Recording** | AVAssetWriter (HEVC/AAC) | — |
| **Audio** | AVAudioEngine + PCM bridging | — |
| **WebRTC** | WebRTC.framework (M125) | io.github.webrtc-sdk:android:125.6422.07 |
| **Signaling** | NWConnection (TCP client) | ServerSocket (TCP server) |
| **Discovery** | NWBrowser (Bonjour) | NsdManager (mDNS) |
| **Haptics** | NSHapticFeedbackManager | VibratorManager + Composition API |

## Quick Start

### Prerequisites
- macOS 14+ with Xcode 15+ and Swift 5.9+
- Android Studio Hedgehog+ with API 34 SDK
- Both devices on the same LAN

### Build & Run

**Android (Sender):**
```bash
cd android
./gradlew assembleRelease
# Install APK from android/app/build/outputs/apk/release/
```

**macOS (Director):**
```bash
cd mac
swift build -c release
# Binary at .build/release/MacDirector
```

### Usage
1. Launch the Android app → tap **LINK** (grants screen capture permission)
2. Launch the Mac app → click **MODO DUAL ELYSIUM** (auto-discovers Android via Bonjour)
3. WebRTC handshake completes automatically (ICE trickle over TCP:9999)
4. Click **INICIAR GRABACIÓN** to record the composited output as MP4
5. Use `⌘⌥1/2/3` to switch Android PIP layouts
6. Draw neon annotations directly on screen (baked into recording)

## Project Structure

```
├── android/
│   └── app/src/main/java/com/jsm/core/
│       ├── MainActivity.kt            # Compose UI + orchestration
│       ├── foldable/
│       │   └── FoldStateListener.kt   # WindowInfoTracker bridge
│       ├── sensory/
│       │   └── SensoryFeedbackManager.kt  # Haptic patterns
│       ├── signaling/
│       │   ├── NsdBroadcaster.kt      # Bonjour/NSD registration
│       │   └── SignalingServer.kt     # TCP JSON signaling server
│       └── webrtc/
│           ├── CaptureForegroundService.kt  # Android 14+ lifecycle
│           ├── RTCClient.kt           # PeerConnection + DataChannel
│           └── ScreenCapturerHook.kt  # MediaProjection → WebRTC
├── mac/
│   ├── Package.swift
│   └── Sources/MacDirector/
│       ├── JSMApp.swift               # SwiftUI entry point
│       ├── MainRouter.swift           # Central orchestrator
│       ├── Capture/
│       │   ├── AudioMixer.swift       # System audio → AVAudioEngine
│       │   └── ScreenCaptureManager.swift  # SCStream 60fps
│       ├── Recorder/
│       │   └── AVAssetRecorder.swift  # HEVC + AAC writer
│       ├── Renderer/
│       │   ├── EphemeralCanvas.swift   # Neon annotations + cache
│       │   ├── LayoutMorphEngine.swift # Cubic PIP transitions
│       │   └── MetalCompositor.swift   # 3-pass GPU pipeline
│       ├── Sensory/
│       │   └── SensoryFeedbackManager.swift  # Haptics + sounds
│       ├── Signaling/
│       │   ├── BonjourBrowser.swift    # Zero-config discovery
│       │   └── SignalingClient.swift   # TCP client + auto-reconnect
│       ├── UI/
│       │   ├── DashboardView.swift    # Cyberpunk dashboard
│       │   ├── HotKeyObserver.swift   # ⌘⌥ keyboard shortcuts
│       │   └── MainHUD.swift          # Floating glassmorphism toolbar
│       └── WebRTC/
│           ├── RTCController.swift    # PeerConnection receiver
│           └── RTCVideoSink.swift     # CVPixelBuffer extractor
└── README.md
```

## Thread Safety Model

| Resource | Protection | Threads |
|----------|-----------|---------|
| `LayoutMorphEngine.currentLayout` | `os_unfair_lock` | Main ↔ SCStream Capture |
| `EphemeralEngine._cachedStrokes` | `os_unfair_lock` | Main ↔ SCStream Capture |
| `AudioMixer.systemAudioNode` | `NSLock` | SCStream Audio ↔ AVAudioEngine Render |
| `SignalingServer.clientWriter` | `synchronized` | Accept ↔ Client Handler |

## Signaling Protocol

```json
// Newline-delimited JSON over TCP:9999
{"type":"offer","sdp":"<base64-encoded-SDP>"}
{"type":"answer","sdp":"<base64-encoded-SDP>"}
{"type":"ice","candidate":"...","sdpMid":"audio","sdpMLineIndex":0}
```

## Security

- **LAN-only** — No STUN/TURN servers, zero cloud exposure
- **No credentials in repo** — All secrets excluded via `.gitignore`
- **TCP_NODELAY** — Minimal signaling latency, no buffering

## License

Proprietary. All rights reserved. © 2026 JSM Engineering.
