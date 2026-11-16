# DS Bot for HarmonyOS

A HarmonyOS port of the DS Bot mobile application. This project brings the DS Bot experience to HarmonyOS devices.

## Overview

DS Bot for HarmonyOS is a native HarmonyOS application that provides a mobile interface for interacting with the DS Bot team. It includes features for:

- **Bot Management**: Browse, create, and manage DS Bot agents
- **Chat Interface**: Real-time chat with bots and teams
- **Team Collaboration**: Multi-bot conversations and group chats
- **Cross-platform Sync**: Seamless synchronization with the DS Bot ecosystem

## Architecture

This is a HarmonyOS 5.0 (API 26) application built with:

- **ArkTS** - Primary language for UI and logic
- **Hvigor** - Build system
- **Ohpm** - Package manager for HarmonyOS

### Project Structure

```
DS-Bot-HarmonyOS/
├── AppScope/                 # App-level configuration
│   ├── app.json5             # App manifest
│   └── resources/            # Resources (strings, icons, media)
├── entry/                    # Main module (UIAbility)
│   ├── src/main/ets/         # ArkTS source files
│   │   ├── appstate/         # Global state management
│   │   ├── common/           # Shared utilities and services
│   │   │   ├── link/         # Network/link protocols
│   │   │   ├── team/         # Team/bot state management
│   │   │   ├── deepview/     # Deep view components
│   │   │   ├── ui/           # UI components and i18n
│   │   │   ├── markdown/     # Markdown rendering
│   │   │   └── demo/         # Demo components
│   │   ├── components/       # Reusable UI components
│   │   ├── screens/          # Page-level components
│   │   │   └── chat/         # Chat-specific screens
│   │   ├── entryability/     # Ability entry point
│   │   ├── pages/            # Main pages
│   │   └── platform/         # Platform-specific code
│   ├── build-profile.json5   # Module build config
│   ├── hvigorfile.ts         # Hvigor build script
│   └── obfuscation-rules.txt # Obfuscation rules
├── build-profile.json5       # Project build config
├── hvigorfile.ts             # Project build script
├── oh-package.json5          # Project dependencies
└── local.properties          # Local SDK path config
```

## Key Features

### Network & Communication
- **Secure Transport**: Noise protocol implementation for encrypted communication
- **Relay Transport**: WebSocket-based relay for NAT traversal
- **RPC Client**: Remote procedure call framework for bot interactions
- **Pairing**: Device pairing and authentication flows

### State Management
- **AppStore**: Centralized state store using reactive patterns
- **Team Link**: Team and bot connection management
- **Chat State**: Optimistic UI updates for chat messages
- **Character System**: Bot personality and character selection

### UI Components
- **Theme System**: Consistent theming with dark/light support
- **Internationalization**: Multi-language support (Chinese/English)
- **Chat Interface**: Rich message rendering with markdown support
- **Form Controls**: Custom form components for bot configuration

## Getting Started

### Prerequisites
- DevEco Studio (latest)
- HarmonyOS SDK API 26+
- Node.js (for ohpm)
- ohpm CLI: `npm install -g @ohos/ohpm`

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS.git
   cd DS-Bot-HarmonyOS
   ```

2. Install dependencies:
   ```bash
   ohpm install
   ```

3. Open in DevEco Studio and build/run on device/emulator.

### Build Commands

```bash
# Debug build
hvigorw assembleDefaultDebug

# Release build
hvigorw assembleDefaultRelease
```

## Configuration

The app requires connection to a DS Bot backend. Configure the backend URL in the app settings after first launch.

## Development

### Code Style
- Follows HarmonyOS ArkTS conventions
- ESLint + Prettier for TypeScript/ArkTS files
- Commit message convention: Conventional Commits

### Testing
```bash
# Unit tests (if configured)
hvigorw test
```

## License

Apache-2.0 License - See [LICENSE](LICENSE) for details.

## Author

**Fei2411** - Original mobile app author
Port to HarmonyOS by the DS Bot team

## Links

- [DS Bot Main Repository](https://github.com/deepseek-ai/ds-bot)
- [HarmonyOS Development Docs](https://developer.harmonyos.com/)
