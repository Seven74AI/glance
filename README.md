# Glance

Share any screen or window with AI in real time. Press a hotkey, capture your screen, and get instant AI analysis — Claude, GPT, or Gemini looks at what you're looking at.

**[seven74ai.github.io/glance](https://seven74ai.github.io/glance)** — macOS first, cross-platform later. (glance.sh is planned.)

> Glance is in early development. The landing page has a waitlist for early access.

---

## Architecture

Glance is built as a modular Swift package with four libraries and one app executable.

```
┌──────────────────────────────────────────────────────┐
│                    GlanceApp                         │
│  AppDelegate: lifecycle, menu bar, overlay, prefs    │
│                                                      │
│  ┌───────────────────────────────────────────────┐   │
│  │              GlancePipeline                    │   │
│  │  Central orchestrator: wires all modules       │   │
│  └──────────────┬──────┬──────┬──────────────────┘   │
│                 │      │      │                       │
│      ┌──────────▼┐ ┌───▼─────▼───┐ ┌──────────────┐  │
│      │ CaptureEng │ │FrameProc   │ │  AIProvider  │  │
│      │ (SCK wrap) │ │Metal+JPEG  │ │ Claude/GPT/  │  │
│      │            │ │            │ │    Gemini    │  │
│      └────────────┘ └────────────┘ └──────────────┘  │
│                                                      │
│  ┌───────────────────────────────────────────────┐   │
│  │               GlanceUI                        │   │
│  │  UXStateMachine, MenuBar, Overlay, Prefs      │   │
│  └───────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

### Module Breakdown

| Module | Phase | Purpose | Lines |
|--------|-------|---------|-------|
| **CaptureEngine** | 1.1 | ScreenCaptureKit wrapper with protocol abstraction, thread-safe FrameQueue, permission handling | ~670 |
| **FrameProcessor** | 1.2 | Metal GPU compute shader for downscale + BGRA→RGB swizzle (single pass), JPEG encoding via ImageIO | ~890 |
| **AIProvider** | 1.3 | Protocol-based AI provider abstraction with Claude (Anthropic Messages API), OpenAI (Chat Completions), Gemini (Generative Language API) | ~630 |
| **GlanceUI** | 1.4 | Menu bar app, floating overlay window, 5-state UX machine, preferences, keyboard shortcuts | ~1,640 |
| **GlanceApp** | 1.5 | App executable + GlancePipeline orchestrator + SessionCoordinator + AIClient | ~1,220 |

### Pipeline Flow

```
┌──────────────┐    ┌──────────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ ScreenCapture │───▶│ FrameProcessor   │───▶│  AIClient    │───▶│ UXStateMach  │───▶│  Overlay     │
│    Kit        │    │ Metal + JPEG     │    │ HTTP → AI    │    │ 5-state FSM  │    │  Window      │
│               │    │                  │    │              │    │              │    │              │
│ 10 fps        │    │ Downscale 1080p  │    │ Claude/GPT/  │    │ IDLE→SELECT  │    │ Preview +    │
│ Zero-copy GPU │    │ BGRA→RGB swizzle │    │ Gemini       │    │ →PREVIEW→    │    │ AI Response  │
│ IOSurface     │    │ JPEG q=80        │    │              │    │ THINKING→    │    │ Auto-dismiss │
│               │    │ ~10-30ms e2e     │    │ 30s timeout  │    │ SHOWING→IDLE │    │ Esc to close │
└──────────────┘    └──────────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
     Capture          Metal Preprocess        AI Vision           UX States           Display
```

### UX State Machine

```
IDLE ──startCapture──▶ SELECTING
SELECTING ──captureComplete──▶ PREVIEW
SELECTING ──cancelCapture──▶ IDLE
PREVIEW ──confirmSend──▶ THINKING
PREVIEW ──cancelPreview──▶ IDLE
THINKING ──responseReceived──▶ SHOWING
THINKING ──aiError──▶ IDLE
SHOWING ──shareAgain──▶ SELECTING
SHOWING ──dismiss──▶ IDLE
```

The state machine enforces valid transitions. Invalid transitions are silently ignored — the ViewModel exposes `@Published var state: UXState` for SwiftUI observation.

---

## Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| **Language** | Swift 5.9+ | Strict concurrency (`Sendable`, `@MainActor`) |
| **Platform** | macOS 14.0+ (Sonoma) | ScreenCaptureKit requires macOS 14+ |
| **IDE** | Xcode 15.4+ | Required for Metal shader compilation |
| **Screen Capture** | ScreenCaptureKit | Zero-copy IOSurface, GPU-native frame delivery |
| **GPU Processing** | Metal 3 | Compute shader: bilinear downscale + BGRA→RGB (single pass) |
| **Image Encoding** | ImageIO | JPEG encoding at configurable quality (default 80%) |
| **UI Framework** | SwiftUI + AppKit | Menu bar app (`.accessory` activation policy), floating overlay window |
| **Reactivity** | Combine | `@Published` + `ObservableObject` for state propagation |
| **Keyboard** | KeyboardShortcuts | Global `⌃⌥⌘G` hotkey via `sindresorhus/KeyboardShortcuts` |
| **Archives** | ZIPFoundation | Archive support via `weichsel/ZIPFoundation` |
| **HTTP** | URLSession (async/await) | AI API calls with 30s timeout |
| **AI Providers** | Claude (Anthropic), GPT-4o (OpenAI), Gemini (Google) | Pluggable protocol-based architecture |
| **Config** | JSON | `~/.glance/config.json` — API keys, preferences |
| **Testing** | XCTest | 6 test targets, ~4,700 lines of tests |
| **Linting** | SwiftLint | `--strict` on CI |
| **CI/CD** | GitHub Actions | macOS-14 runners, debug + release builds |

---

## Setup (Local Development)

### Prerequisites

- **macOS 14.0+** (Sonoma or later — ScreenCaptureKit requires it)
- **Xcode 15.4+** (with Metal compiler)
- **An API key** for at least one AI provider:
  - [Anthropic Console](https://console.anthropic.com/) — Claude
  - [OpenAI Platform](https://platform.openai.com/) — GPT-4o
  - [Google AI Studio](https://aistudio.google.com/) — Gemini

### 1. Clone

```bash
git clone https://github.com/Seven74AI/glance.git
cd glance
```

### 2. Configure API Keys

Create `~/.glance/config.json` (the app auto-creates it on first launch, or copy the example):

```bash
mkdir -p ~/.glance
cp Config/ai-providers.example.json ~/.glance/config.json
```

Edit `~/.glance/config.json` with your API keys:

```json
{
  "providers": {
    "claude": {
      "apiKey": "sk-ant-your-key-here",
      "model": "claude-sonnet-4-20250514"
    },
    "openai": {
      "apiKey": "sk-your-key-here",
      "model": "gpt-4o"
    },
    "gemini": {
      "apiKey": "your-key-here",
      "model": "gemini-2.5-flash"
    }
  },
  "defaultProvider": "claude",
  "defaultCaptureMode": "windowUnderCursor",
  "keyboardShortcut": "ctrl+option+cmd+G"
}
```

The config file is never committed — `.gitignore` excludes `Config/ai-providers.json` and `.env`.

### 3. Build

```bash
# Debug build
swift build -c debug

# Release build
swift build -c release
```

### 4. Run Tests

```bash
# All tests (parallel)
swift test -c debug --parallel

# Single module
swift test -c debug --filter CaptureEngineTests --parallel
```

### 5. Run the App

```bash
# From Xcode: open Package.swift, select "Glance" scheme, ⌘R

# From terminal (debug executable):
swift run Glance

# Release executable:
swift build -c release
open .build/release/Glance
```

### 6. Grant Permissions

On first launch, macOS prompts for **Screen Recording** permission. Enable it in:
**System Settings → Privacy & Security → Screen Recording → toggle Glance ON**.

The app checks permission at startup and shows an error with a direct link to System Settings if denied.

---

## Contributing

### Development Workflow

1. **Fork** the repo and create a feature branch
2. **Write tests** first (TDD — tests are mandatory)
3. **Implement** with protocol-based abstractions for testability
4. **Run full CI locally** before pushing:

```bash
# Build
swift build -c debug

# Test (both configs)
swift test -c debug --parallel
swift test -c release --parallel

# Lint
brew install swiftlint
swiftlint --strict
```

5. **Push** and open a PR against `main`

### CI Pipeline

All pushes and PRs trigger GitHub Actions on `macos-14` runners:

| Job | What it runs |
|-----|-------------|
| **Lint** | `swiftlint --strict` |
| **Build** | `swift build -c debug` (with SPM dependency caching) |
| **Test** | `swift test -c debug --parallel`, `swift test -c release --parallel` (depends on `build`)

### Code Conventions

- **Strict concurrency**: All new code enables `StrictConcurrency` (`Sendable`, `@MainActor` where needed)
- **Protocol abstraction**: Every system dependency (SCStream, URLSession) is wrapped in a protocol for testability
- **Structured errors**: Every module defines its own `Error` enum conforming to `LocalizedError` + `Equatable`
- **No force-unwrap**: Use `guard let` / `if let` or `try` with explicit error handling
- **Thread safety**: CaptureEngine uses `NSLock` for shared state; pipeline uses a serial `DispatchQueue` for frame processing

### Project Structure

```
glance/
├── App/
│   ├── GlanceApp/            # Main .app target
│   │   ├── GlanceApp.swift        # @main entry point + AppDelegate
│   │   ├── GlancePipeline.swift   # Central orchestrator
│   │   ├── SessionCoordinator.swift
│   │   ├── AIClient.swift         # HTTP client (Claude/GPT/Gemini)
│   │   ├── Config.swift           # ~/.glance/config.json I/O
│   │   ├── Glance.entitlements
│   │   └── Info.plist
│   └── GlanceTestApp/        # Dev/test executable
├── Sources/
│   ├── CaptureEngine/        # ScreenCaptureKit wrapper
│   │   ├── CaptureProtocols.swift  # SCStream/SCContentFilter wrappers
│   │   ├── CaptureEngine.swift     # Concrete SCK integration
│   │   ├── FrameQueue.swift        # Thread-safe frame buffer
│   │   └── PermissionHelper.swift  # Screen Recording permission
│   ├── FrameProcessor/       # Metal GPU pipeline
│   │   ├── FrameProcessor.swift    # Orchestrator
│   │   ├── MetalPreprocessor.swift # GPU compute shader wrapper
│   │   ├── JPEGEncoder.swift       # ImageIO JPEG encoding
│   │   ├── PerformanceTimer.swift
│   │   └── PreprocessShader.metal  # Metal shader source
│   ├── AIProvider/           # AI provider abstraction
│   │   ├── AIProvider.swift        # AIResponse + AIProvider protocol
│   │   ├── ClaudeProvider.swift    # Anthropic Messages API
│   │   ├── OpenAIProvider.swift    # Chat Completions API
│   │   ├── GeminiProvider.swift    # Generative Language API
│   │   └── ProviderRegistry.swift
│   └── GlanceUI/             # Menu bar + overlay UI
│       ├── UXStateMachine.swift    # 5-state FSM
│       ├── StateMachineViewModel.swift
│       ├── MenuBarManager.swift
│       ├── OverlayWindow.swift
│       ├── OverlayContainer.swift
│       ├── PreferencesViewModel.swift
│       └── ...
├── Tests/
│   ├── CaptureEngineTests/   # ~640 lines
│   ├── FrameProcessorTests/  # ~1,290 lines
│   ├── AIProviderTests/      # ~550 lines
│   ├── GlanceUITests/        # ~1,050 lines
│   └── GlanceAppTests/       # ~1,130 lines (integration)
├── Config/
│   └── ai-providers.example.json  # Template for ~/.glance/config.json
├── spikes/
│   └── phase-0.1/            # Initial SCK pipeline validation spike
├── docs/                     # Landing page (GitHub Pages)
├── Scripts/
│   └── e2e-test.sh           # End-to-end test runner
├── Package.swift             # SPM manifest
├── .github/workflows/ci.yml  # GitHub Actions
├── .gitignore
├── SPIKE-REPORT.md           # Phase 0.1 spike report
└── README.md                 # This file
```

---

## Landing Page

The public landing page is a static site in `/docs`, served via GitHub Pages at **[seven74ai.github.io/glance](https://seven74ai.github.io/glance)**. It includes a waitlist form backed by Formspree. Submissions route to `sevenai@agentmail.to`.

---

## Acknowledgements

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — Apple
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Sindre Sorhus
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — Thomas Zoechling
