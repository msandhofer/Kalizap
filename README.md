# Kalizap

Native macOS voice-to-text app with on-device transcription via Apple SpeechAnalyzer and optional correction by Claude Haiku (Anthropic API). Menu bar app, hotkey-driven, with DeepFilterNet3 noise suppression.

## How this was built

Kalizap is a personal experiment in *vibecoding*: every line of code in this project was produced with [Claude Code](https://claude.com/claude-code) by Anthropic. I have no prior experience with the underlying components (Swift/SwiftUI, on-device speech recognition, DSP-based noise suppression, among others) — architectural decisions, implementation, and refactorings all came out of the collaboration with the model. My role was product design, requirements, and review.

## Installation

### Homebrew Cask (recommended)

```
brew install --cask msandhofer/kalizap/kalizap
```

> The Homebrew tap is still in preparation (see Issue #45). Until then, please use Direct Download.

### Direct Download (GitHub Releases)

1. Download the latest version from [GitHub Releases](https://github.com/msandhofer/Kalizap/releases)
2. Unzip and drag `Kalizap.app` into `/Applications/`
3. Remove the quarantine attribute — either via right-click → **Open** → **Open** (one-time Gatekeeper bypass), or in Terminal:
   ```
   xattr -d com.apple.quarantine /Applications/Kalizap.app
   ```

Note: The app is not notarized (a deliberate choice — no Apple Developer Program membership). The quarantine bypass has to be repeated on every update. Going through Homebrew handles this automatically.

### Requirements

- macOS 26+ (Tahoe)
- Apple Silicon (ARM64)
- Anthropic API key for the LLM correction (optional — without a key the app runs as plain transcription)

## Build from source

Requirements: Xcode 15+ / Swift 6.2, macOS 26+.

```bash
git clone https://github.com/msandhofer/Kalizap.git
cd Kalizap
git lfs pull                           # fetch the DeepFilterNet model
./Scripts/generate-app-secret.sh       # one-time: app secret for API-key encryption
swift build -c release
```

The API key is stored as an AES-GCM-encrypted file under `~/Library/Application Support/Kalizap/`. The encryption key is bound to the device (`IOPlatformUUID`), the user account (`NSUserName`) and the build-time-injected app secret. Details and threat model: [`docs/security.md`](docs/security.md). Notes on the app secret: [`docs/build-secret.md`](docs/build-secret.md).

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — Copyright 2026 Mathias Sandhofer

Non-commercial use (private, research, learning, contributing) is permitted free of charge. Commercial use, resale, or integration into commercial products is not allowed. For commercial licensing inquiries, please get in touch.
