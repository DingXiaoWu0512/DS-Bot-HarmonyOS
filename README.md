# DS Bot for HarmonyOS

[English](README.md) | [中文](README_ZH.md)

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-5.0%20(API%2026)-007DFF?logo=harmonyos&logoColor=white)](https://developer.harmonyos.com/)
[![ArkTS](https://img.shields.io/badge/ArkTS-TypeScript%20Superset-3178C6?logo=typescript&logoColor=white)](https://developer.harmonyos.com/cn/docs/documentation/doc-guides-V3/arkts-overview-0000001477981650-V3)
[![Hvigor](https://img.shields.io/badge/Build-Hvigor-FF6B35)](https://hvigor.com/)
[![Ohpm](https://img.shields.io/badge/Package-Ohpm-4CAF50)](https://ohpm.openharmony.cn/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/dwc13775953197-spec/DS-Bot-HarmonyOS?style=social)](https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS/stargazers)

A **native HarmonyOS 5.0 (API 26)** port of the DS Bot mobile application. This project brings the full DS Bot experience to HarmonyOS devices with secure communication, reactive state management, and a modern declarative UI.

---

## 📱 Screenshots

| Bot List | Chat Interface | Settings |
|:--------:|:--------------:|:--------:|
| ![Bot List](entry/src/main/resources/base/media/app_icon.png) | ![Chat](entry/src/main/resources/base/media/app_icon.png) | ![Settings](entry/src/main/resources/base/media/app_icon.png) |

*Screenshots coming soon — run the app in DevEco Studio preview or on device.*

---

## ✨ Key Features

### 🔐 Secure Communication
| Feature | Description |
|---------|-------------|
| **Noise Protocol** | Modern crypto handshake (Noise_XK_25519_ChaChaPoly_BLAKE2s) for encrypted transport |
| **Relay Transport** | WebSocket relay for NAT traversal and firewall traversal |
| **Secure Channels** | ChaCha20-Poly1305 AEAD encryption with perfect forward secrecy |
| **Pairing Flow** | QR-code / passphrase based device pairing with authentication |

### 🧠 State Management
- **AppStore** — Centralized reactive store (ArkTS `@Observed` / `@State`)
- **Team Link** — Persistent team/bot connections with auto-reconnect
- **Optimistic UI** — Instant message feedback with server reconciliation
- **Character System** — Per-bot personality, avatar, and behavior config

### 💬 Chat & UI
- **Markdown Rendering** — Full CommonMark + GFM (tables, code blocks, math)
- **Deep View Components** — Interactive tables, charts, forms rendered from bot tools
- **Internationalization** — Chinese (zh_CN) / English with dynamic locale switching
- **Theme System** — Light/Dark/System with custom color tokens
- **Accessibility** — TalkBack, large fonts, high contrast support

### 🛠 Developer Experience
- **Hot Reload** — ArkTS incremental compilation in DevEco Studio
- **Type Safety** — Strict ArkTS with `@ohos/arkts` linting
- **Testing** — Unit tests (Noise crypto, link protocol, logic) + integration tests

---

## 🏗 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      AppScope (App Level)                    │
│  App manifest · Global resources · Permissions · Theme      │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                       entry (UIAbility)                       │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   AppStore (Global State)               │  │
│  │  TeamStore │ BotStore │ ChatStore │ SettingsStore      │  │
│  └────────────────────────────────────────────────────────┘  │
│                           │                                   │
│  ┌──────────────┬─────────┴──────────┬────────────────────┐  │
│  │  Screens     │   Components       │   Common Services  │  │
│  │  ├─ BotBrowser            ├─ Banner      ├─ link/       │  │
│  │  ├─ Chat                 ├─ FormControls│   ├─ noise.ts │  │
│  │  ├─ Settings             ├─ Theme       │   ├─ transport│  │
│  │  └─ ...                  └─ ...         │   ├─ rpc      │  │
│  │                                 │   ├─ team/       │  │
│  │                                 │   ├─ deepview/   │  │
│  │                                 │   ├─ ui/i18n/    │  │
│  │                                 │   └─ markdown/   │  │
│  └─────────────────────────────────┴────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
DS-Bot-HarmonyOS/
├── AppScope/                          # App-level configuration
│   ├── app.json5                      # App manifest (bundleName, version, permissions)
│   └── resources/
│       └── base/
│           ├── element/               # Colors, strings, integers
│           └── media/                 # App icon, splash, favicon
├── entry/                             # Main module (UIAbility)
│   ├── src/main/ets/                  # ArkTS source files
│   │   ├── appstate/                  # Global reactive stores
│   │   │   └── AppStore.ets           # Central state container
│   │   ├── common/                    # Shared utilities & services
│   │   │   ├── link/                  # Network protocol stack
│   │   │   │   ├── noise.ts           # Noise protocol implementation
│   │   │   │   ├── transport.ts       # Base transport interface
│   │   │   │   ├── secure-transport.ts# Encrypted transport wrapper
│   │   │   │   ├── relay-transport.ts # WebSocket relay transport
│   │   │   │   ├── rpc-client.ts      # RPC framework
│   │   │   │   ├── pairing.ts         # Device pairing protocol
│   │   │   │   ├── frames.ts          # Binary frame encoding
│   │   │   │   └── keys.ts            # X25519 key management
│   │   │   ├── team/                  # Team/bot state management
│   │   │   │   ├── store-core.ts      # Core store implementation
│   │   │   │   ├── chat-state.ts      # Chat message state
│   │   │   │   ├── team-link.ts       # Team connection lifecycle
│   │   │   │   └── types.ts           # Shared type definitions
│   │   │   ├── deepview/              # Dynamic view components
│   │   │   │   ├── views-core.ts      # View rendering engine
│   │   │   │   ├── view-bridge.ts     # ArkTS ↔ DeepView bridge
│   │   │   │   └── formula.ts         # Formula evaluation
│   │   │   ├── ui/                    # UI primitives & i18n
│   │   │   │   ├── i18n.ts            # Internationalization core
│   │   │   │   ├── i18n-zh-desktop.ts # Chinese translations
│   │   │   │   ├── characters.ts      # Bot character definitions
│   │   │   │   └── tokens.ts          # Design tokens (colors, spacing)
│   │   │   ├── markdown/              # Markdown parser & renderer
│   │   │   ├── crypto/                # ChaCha20, SHA256, X25519, HKDF
│   │   │   └── platform-hooks.ts      # Platform-specific bridges
│   │   ├── components/                # Reusable UI components
│   │   │   ├── Banner.ets             # Top banner with actions
│   │   │   ├── CharacterPick.ets      # Bot character selector
│   │   │   ├── FormControls.ets       # Input, Select, Toggle, Slider
│   │   │   ├── Icon.ets               # Icon system (Material + custom)
│   │   │   ├── Marks.ets              # Badge/label components
│   │   │   ├── Sheet.ets              # Bottom sheet / modal
│   │   │   └── Theme.ets              # Theme provider & consumer
│   │   ├── screens/                   # Page-level components
│   │   │   ├── BotBrowser.ets         # Bot discovery & management
│   │   │   ├── Chat.ets               # Main chat interface
│   │   │   ├── Settings.ets           # App & account settings
│   │   │   ├── Pair.ets               # Device pairing flow
│   │   │   ├── TeamList.ets           # Team/workspace switcher
│   │   │   ├── BotEdit.ets            # Bot creation/editing
│   │   │   ├── BotDetails.ets         # Bot info & capabilities
│   │   │   ├── GroupDetails.ets       # Group chat management
│   │   │   ├── Memory.ets             # Conversation memory viewer
│   │   │   ├── Schedules.ets          # Scheduled tasks UI
│   │   │   ├── ModelMenu.ets          # Model selector
│   │   │   ├── Side.ets               # Sidebar navigation
│   │   │   ├── Usage.ets              # Token/cost usage stats
│   │   │   ├── NeedsYou.ets           # Pending approvals
│   │   │   ├── NewChat.ets            # New conversation starter
│   │   │   ├── Folder.ets             # Conversation folders
│   │   │   ├── routes.ts              # Router configuration
│   │   │   ├── settings/              # Settings sub-pages
│   │   │   │   ├── AboutPages.ets
│   │   │   │   ├── Capabilities.ets
│   │   │   │   ├── Connectors.ets
│   │   │   │   ├── Providers.ets
│   │   │   │   └── TeamPages.ets
│   │   │   └── chat/                  # Chat-specific components
│   │   │       ├── ChatCards.ets      # Message card variants
│   │   │       ├── ChatInput.ets      # Composer with attachments
│   │   │       ├── ChatRows.ets       # Message list virtualization
│   │   │       ├── DeepView.ets       # Interactive tool views
│   │   │       ├── MarkdownText.ets   # Rich markdown rendering
│   │   │       └── MessageList.ets    # Message container
│   │   ├── entryability/              # Ability lifecycle
│   │   │   └── EntryAbility.ets       # App entry point
│   │   ├── pages/                     # Legacy page entry (Index.ets)
│   │   └── platform/                  # Platform adapters
│   │       ├── AppInfo.ets            # App metadata access
│   │       └── Platform.ets           # OS capability detection
│   ├── build-profile.json5            # Module build configuration
│   ├── hvigorfile.ts                  # Module build script
│   ├── obfuscation-rules.txt          # R8/ProGuard rules for release
│   ├── oh-package.json5               # Module dependencies
│   └── src/main/module.json5          # Module manifest (abilities, permissions)
├── build-profile.json5                # Project build configuration
├── hvigorfile.ts                      # Project build script (Hvigor)
├── hvigor/                            # Hvigor config & plugins
│   └── hvigor-config.json5
├── oh-package.json5                   # Project dependencies (ohpm)
├── local.properties                   # Local SDK paths (gitignored)
├── spec/                              # Design specifications
│   ├── dsbot-ui-port/                 # UI port specification
│   └── feature.json                   # Feature matrix
├── test/                              # Unit & integration tests
│   ├── noise.test.ts                  # Noise protocol tests
│   ├── link-integration.test.ts       # Transport integration tests
│   ├── logic.test.ts                  # Business logic tests
│   ├── crypto.test.ts                 # Crypto primitive tests
│   ├── package.json
│   └── package-lock.json
├── tools/                             # Build/dev utilities
│   └── decompile_chat.py              # Chat export decompiler
├── .gitignore
├── LICENSE
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **DevEco Studio** | Latest (5.0+) | [Download](https://developer.harmonyos.com/cn/download/) |
| **HarmonyOS SDK** | API 26 (5.0.0) | DevEco Studio → SDK Manager |
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org/) |
| **ohpm** | Latest | `npm install -g @ohos/ohpm` |
| **hvigor** | Bundled with SDK | `hvigorw --version` |

### Quick Start

```bash
# 1. Clone
git clone https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS.git
cd DS-Bot-HarmonyOS

# 2. Install dependencies
ohpm install

# 3. Open in DevEco Studio
# File → Open → Select project folder

# 4. Build & Run
# Click ▶ Run on device/emulator
# Or CLI:
hvigorw assembleDefaultDebug    # Debug build (HAP)
hvigorw assembleDefaultRelease  # Release build (HAP + App Gallery)
```

### Build Commands

```bash
# Development
hvigorw assembleDefaultDebug          # Debug HAP
hvigorw :entry:compileDefaultDebug    # Incremental compile only

# Release
hvigorw assembleDefaultRelease        # Signed release HAP
hvigorw :entry:compileDefaultRelease  # Release compile

# Testing
hvigorw test                          # Run all tests
hvigorw :entry:testDebugUnitTest      # Unit tests only

# Clean
hvigorw clean                         # Clean build outputs
```

---

## ⚙️ Configuration

### Backend Connection
On first launch, the app prompts for **DS Bot Backend URL**. This connects to your DS Bot server (WebSocket + REST).

```
Default: wss://your-ds-bot-host:port
```

### Signing (Release Builds)
Configure signing in `entry/build-profile.json5` → `signingConfigs`:

```json5
{
  "name": "release",
  "material": {
    "certpath": "path/to/cert.cer",
    "keyAlias": "releaseKey",
    "keyPassword": "***",
    "profile": "path/to/profile.p7b",
    "signAlg": "SHA256withECDSA",
    "storeFile": "path/to/keystore.p12",
    "storePassword": "***"
  }
}
```

> **Never commit signing materials.** They're in `.gitignore`.

### Local Properties
Create `local.properties` (auto-generated by DevEco Studio):

```properties
ohos.sdk.path=/Users/xxx/Library/Huawei/Sdk/ohos/5.0.0
ohos.ndk.path=/Users/xxx/Library/Huawei/Sdk/ohos/5.0.0/native
```

---

## 🧪 Testing

```bash
# All tests
hvigorw test

# Specific test suites
hvigorw :entry:testDebugUnitTest --tests "noise.test"
hvigorw :entry:testDebugUnitTest --tests "link-integration"

# Coverage (requires lcov)
hvigorw jacocoReport
```

### Test Structure
| File | Coverage |
|------|----------|
| `noise.test.ts` | Noise handshake, encryption, rekey |
| `crypto.test.ts` | ChaCha20-Poly1305, SHA256, X25519, HKDF |
| `link-integration.test.ts` | Transport layer, relay, reconnection |
| `logic.test.ts` | Store, optimistic updates, pairing |

---

## 📦 Dependencies (ohpm)

```json5
// oh-package.json5
{
  "dependencies": {
    "@ohos/arkts": "^1.0.0",          // ArkTS stdlib
    "@ohos/hypium": "^1.0.0",         // Testing framework
    "@ohos/hamock": "^1.0.0"          // Mocking (if needed)
  },
  "devDependencies": {
    "@ohos/eslint": "^1.0.0",
    "@ohos/prettier": "^1.0.0"
  }
}
```

Run `ohpm install` after cloning. Lockfile: `oh-package-lock.json5`.

---

## 🔧 Development Workflow

### Code Style
```bash
# Lint
npx @ohos/eslint entry/src/main/ets --ext .ets,.ts

# Format
npx @ohos/prettier --write entry/src/main/ets/**/*.ets
```

### Commit Convention
Follows **Conventional Commits**:
```
feat(chat): add markdown rendering for code blocks
fix(link): handle relay reconnection backoff
docs(readme): update build commands
refactor(store): extract TeamLink from AppStore
test(noise): add rekey scenario tests
chore(deps): upgrade ohpm packages
```

### Branch Strategy
- `master` — Protected, release tags only
- `develop` — Integration branch (if team grows)
- `feat/*`, `fix/*`, `chore/*` — Short-lived feature branches

---

## 📄 License

**Apache-2.0** — See [LICENSE](LICENSE) for full text.

```
Copyright 2024 DS Bot Team

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
```

---

## 👥 Contributors

| Role | Author |
|------|--------|
| **Original Mobile App** | [Fei2411](https://github.com/Fei2411) |
| **HarmonyOS Port** | DS Bot Team |
| **Noise Protocol** | Based on [Noise Explorer](https://github.com/noiseprotocol/noise-explorer) |
| **Crypto Primitives** | [@noble/ciphers](https://github.com/paulmillr/noble-ciphers), [@noble/hashes](https://github.com/paulmillr/noble-hashes), [@noble/curves](https://github.com/paulmillr/noble-curves) |

---

## 🔗 Related Projects

- **DS Bot (Main)** — [deepseek-ai/ds-bot](https://github.com/deepseek-ai/ds-bot)
- **DS Bot Web** — Web dashboard for bot management
- **DeepView** — Dynamic view rendering engine (embedded)
- **HarmonyOS Docs** — [developer.harmonyos.com](https://developer.harmonyos.com/)

---

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS/discussions)
- **DS Bot Community**: [Discord/Telegram links in main repo]

---

<div align="center">
  <sub>Built with ❤️ for HarmonyOS • Powered by ArkTS & Hvigor</sub>
</div>