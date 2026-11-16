# DS Bot for HarmonyOS

[English](README.md) | [中文](README_ZH.md)

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-5.0%20(API%2026)-007DFF?logo=harmonyos&logoColor=white)](https://developer.harmonyos.com/)
[![ArkTS](https://img.shields.io/badge/ArkTS-TypeScript%20超集-3178C6?logo=typescript&logoColor=white)](https://developer.harmonyos.com/cn/docs/documentation/doc-guides-V3/arkts-overview-0000001477981650-V3)
[![Hvigor](https://img.shields.io/badge/构建-Hvigor-FF6B35)](https://hvigor.com/)
[![Ohpm](https://img.shields.io/badge/包管理-Ohpm-4CAF50)](https://ohpm.openharmony.cn/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/dwc13775953197-spec/DS-Bot-HarmonyOS?style=social)](https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS/stargazers)

**原生 HarmonyOS 5.0 (API 26) 应用**，将 DS Bot 移动端完整移植到鸿蒙设备。具备安全通信、响应式状态管理、现代声明式 UI 等核心能力。

---

## 📱 截图预览

| Bot 列表 | 聊天界面 | 设置页面 |
|:--------:|:--------:|:--------:|
| ![Bot List](entry/src/main/resources/base/media/app_icon.png) | ![Chat](entry/src/main/resources/base/media/app_icon.png) | ![Settings](entry/src/main/resources/base/media/app_icon.png) |

*截图即将上线 —— 可在 DevEco Studio 预览器或真机运行查看。*

---

## ✨ 核心特性

### 🔐 安全通信
| 特性 | 说明 |
|------|------|
| **Noise 协议** | 现代加密握手 (Noise_XK_25519_ChaChaPoly_BLAKE2s)，提供前向保密 |
| **Relay 传输** | WebSocket 中继穿透 NAT/防火墙 |
| **安全通道** | ChaCha20-Poly1305 AEAD 加密认证 |
| **配对流程** | 二维码 / 口令配对，设备认证授权 |

### 🧠 状态管理
- **AppStore** —— 中心化响应式存储 (ArkTS `@Observed` / `@State`)
- **Team Link** —— 团队/ Bot 持久连接，自动重连
- **乐观 UI** —— 消息即时反馈，服务端最终一致性校正
- **角色系统** —— 每个 Bot 独立人设、头像、行为配置

### 💬 聊天与 UI
- **Markdown 渲染** —— 完整 CommonMark + GFM (表格、代码块、数学公式)
- **Deep View 组件** —— 从 Bot 工具动态渲染交互式表格、图表、表单
- **国际化** —— 中文 (zh_CN) / 英文，运行时动态切换语言
- **主题系统** —— 浅色/深色/跟随系统，自定义设计 Token
- **无障碍** —— TalkBack、大字体、高对比度支持

### 🛠 开发体验
- **热重载** —— DevEco Studio 增量编译
- **类型安全** —— 严格 ArkTS + `@ohos/arkts` 静态检查
- **测试完备** —— 单测 (Noise、链路、逻辑) + 集成测试

---

## 🏗 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                      AppScope (应用层)                        │
│  应用清单 · 全局资源 · 权限声明 · 主题配置                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                       entry (UIAbility)                       │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   AppStore (全局状态)                   │  │
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

## 📁 目录结构

```
DS-Bot-HarmonyOS/
├── AppScope/                          # 应用级配置
│   ├── app.json5                      # 应用清单 (bundleName、版本、权限)
│   └── resources/
│       └── base/
│           ├── element/               # 颜色、字符串、整数资源
│           └── media/                 # 应用图标、启动页、favicon
├── entry/                             # 主模块 (UIAbility)
│   ├── src/main/ets/                  # ArkTS 源码
│   │   ├── appstate/                  # 全局响应式 Store
│   │   │   └── AppStore.ets           # 中心状态容器
│   │   ├── common/                    # 共享工具与服务
│   │   │   ├── link/                  # 网络协议栈
│   │   │   │   ├── noise.ts           # Noise 协议实现
│   │   │   │   ├── transport.ts       # 传输层接口
│   │   │   │   ├── secure-transport.ts# 加密传输封装
│   │   │   │   ├── relay-transport.ts # WebSocket 中继传输
│   │   │   │   ├── rpc-client.ts      # RPC 框架
│   │   │   │   ├── pairing.ts         # 设备配对协议
│   │   │   │   ├── frames.ts          # 二进制帧编解码
│   │   │   │   └── keys.ts            # X25519 密钥管理
│   │   │   ├── team/                  # 团队/Bot 状态管理
│   │   │   │   ├── store-core.ts      # 核心 Store 实现
│   │   │   │   ├── chat-state.ts      # 聊天消息状态
│   │   │   │   ├── team-link.ts       # 团队连接生命周期
│   │   │   │   └── types.ts           # 共享类型定义
│   │   │   ├── deepview/              # 动态视图组件
│   │   │   │   ├── views-core.ts      # 视图渲染引擎
│   │   │   │   ├── view-bridge.ts     # ArkTS ↔ DeepView 桥接
│   │   │   │   └── formula.ts         # 公式求值
│   │   │   ├── ui/                    # UI 基础组件 & i18n
│   │   │   │   ├── i18n.ts            # 国际化核心
│   │   │   │   ├── i18n-zh-desktop.ts # 中文翻译
│   │   │   │   ├── characters.ts      # Bot 人设定义
│   │   │   │   └── tokens.ts          # 设计 Token (色板、间距)
│   │   │   ├── markdown/              # Markdown 解析渲染
│   │   │   ├── crypto/                # ChaCha20、SHA256、X25519、HKDF
│   │   │   └── platform-hooks.ts      # 平台适配桥接
│   │   ├── components/                # 复用 UI 组件
│   │   │   ├── Banner.ets             # 顶部横幅操作栏
│   │   │   ├── CharacterPick.ets      # Bot 人设选择器
│   │   │   ├── FormControls.ets       # Input、Select、Toggle、Slider
│   │   │   ├── Icon.ets               # 图标系统 (Material + 自定义)
│   │   │   ├── Marks.ets              # 徽标/标签组件
│   │   │   ├── Sheet.ets              # 底部弹窗/模态框
│   │   │   └── Theme.ets              # 主题 Provider/Consumer
│   │   ├── screens/                   # 页面级组件
│   │   │   ├── BotBrowser.ets         # Bot 发现与管理
│   │   │   ├── Chat.ets               # 主聊天界面
│   │   │   ├── Settings.ets           # 应用与账号设置
│   │   │   ├── Pair.ets               # 设备配对流程
│   │   │   ├── TeamList.ets           # 团队/工作区切换
│   │   │   ├── BotEdit.ets            # Bot 创建/编辑
│   │   │   ├── BotDetails.ets         # Bot 详情与能力
│   │   │   ├── GroupDetails.ets       # 群聊管理
│   │   │   ├── Memory.ets             # 对话记忆查看器
│   │   │   ├── Schedules.ets          # 定时任务 UI
│   │   │   ├── ModelMenu.ets          # 模型选择器
│   │   │   ├── Side.ets               # 侧边栏导航
│   │   │   ├── Usage.ets              # Token/费用统计
│   │   │   ├── NeedsYou.ets           # 待审批事项
│   │   │   ├── NewChat.ets            # 新建会话入口
│   │   │   ├── Folder.ets             # 会话文件夹
│   │   │   ├── routes.ts              # 路由配置
│   │   │   ├── settings/              # 设置子页面
│   │   │   │   ├── AboutPages.ets
│   │   │   │   ├── Capabilities.ets
│   │   │   │   ├── Connectors.ets
│   │   │   │   ├── Providers.ets
│   │   │   │   └── TeamPages.ets
│   │   │   └── chat/                  # 聊天专用组件
│   │   │       ├── ChatCards.ets      # 消息卡片变体
│   │   │       ├── ChatInput.ets      # 输入框 (支持附件)
│   │   │       ├── ChatRows.ets       # 消息列表虚拟化
│   │   │       ├── DeepView.ets       # 交互式工具视图
│   │   │       ├── MarkdownText.ets   # 富文本 Markdown
│   │   │       └── MessageList.ets    # 消息容器
│   │   ├── entryability/              # Ability 生命周期
│   │   │   └── EntryAbility.ets       # 应用入口
│   │   ├── pages/                     # 传统页面入口 (Index.ets)
│   │   └── platform/                  # 平台适配器
│   │       ├── AppInfo.ets            # 应用元数据访问
│   │       └── Platform.ets           # OS 能力检测
│   ├── build-profile.json5            # 模块构建配置
│   ├── hvigorfile.ts                  # 模块构建脚本
│   ├── obfuscation-rules.txt          # Release 混淆规则
│   ├── oh-package.json5               # 模块依赖
│   └── src/main/module.json5          # 模块清单 (abilities、permissions)
├── build-profile.json5                # 项目构建配置
├── hvigorfile.ts                      # 项目构建脚本 (Hvigor)
├── hvigor/                            # Hvigor 配置与插件
│   └── hvigor-config.json5
├── oh-package.json5                   # 项目依赖 (ohpm)
├── local.properties                   # 本地 SDK 路径 (gitignore)
├── spec/                              # 设计规格文档
│   ├── dsbot-ui-port/                 # UI 移植规格
│   └── feature.json                   # 特性矩阵
├── test/                              # 单测 & 集成测试
│   ├── noise.test.ts                  # Noise 协议测试
│   ├── link-integration.test.ts       # 传输层集成测试
│   ├── logic.test.ts                  # 业务逻辑测试
│   ├── crypto.test.ts                 # 密码学基础测试
│   ├── package.json
│   └── package-lock.json
├── tools/                             # 构建/开发工具
│   └── decompile_chat.py              # 聊天导出反编译
├── .gitignore
├── LICENSE
├── README.md
└── README_ZH.md
```

---

## 🚀 快速开始

### 环境准备

| 工具 | 版本 | 获取方式 |
|------|------|----------|
| **DevEco Studio** | 最新 (5.0+) | [官网下载](https://developer.harmonyos.com/cn/download/) |
| **HarmonyOS SDK** | API 26 (5.0.0) | DevEco Studio → SDK 管理器 |
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org/) |
| **ohpm** | 最新 | `npm install -g @ohos/ohpm` |
| **hvigor** | SDK 自带 | `hvigorw --version` |

### 三步上手

```bash
# 1. 克隆
git clone https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS.git
cd DS-Bot-HarmonyOS

# 2. 安装依赖
ohpm install

# 3. DevEco Studio 打开
# 文件 → 打开 → 选择项目文件夹

# 4. 构建运行
# 点击 ▶ 在设备/模拟器运行
# 或命令行：
hvigorw assembleDefaultDebug    # Debug 包 (HAP)
hvigorw assembleDefaultRelease  # Release 包 (HAP + 应用市场)
```

### 常用构建命令

```bash
# 开发调试
hvigorw assembleDefaultDebug          # Debug HAP
hvigorw :entry:compileDefaultDebug    # 增量编译

# 发布构建
hvigorw assembleDefaultRelease        # 签名 Release HAP
hvigorw :entry:compileDefaultRelease  # Release 编译

# 测试
hvigorw test                          # 全量测试
hvigorw :entry:testDebugUnitTest      # 仅单元测试

# 清理
hvigorw clean                         # 清理构建产物
```

---

## ⚙️ 配置说明

### 后端连接
首次启动会提示输入 **DS Bot 后端地址** (WebSocket + REST)。

```
默认: wss://your-ds-bot-host:port
```

### 签名配置 (Release)
在 `entry/build-profile.json5` → `signingConfigs` 配置：

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

> **切勿提交签名材料** —— 已在 `.gitignore` 中忽略。

### 本地属性
创建 `local.properties` (DevEco Studio 自动生成)：

```properties
ohos.sdk.path=/Users/xxx/Library/Huawei/Sdk/ohos/5.0.0
ohos.ndk.path=/Users/xxx/Library/Huawei/Sdk/ohos/5.0.0/native
```

---

## 🧪 测试

```bash
# 全部测试
hvigorw test

# 指定测试套件
hvigorw :entry:testDebugUnitTest --tests "noise.test"
hvigorw :entry:testDebugUnitTest --tests "link-integration"

# 覆盖率 (需 lcov)
hvigorw jacocoReport
```

### 测试覆盖
| 文件 | 覆盖范围 |
|------|----------|
| `noise.test.ts` | Noise 握手、加密、重协商 |
| `crypto.test.ts` | ChaCha20-Poly1305、SHA256、X25519、HKDF |
| `link-integration.test.ts` | 传输层、中继、重连 |
| `logic.test.ts` | Store、乐观更新、配对流程 |

---

## 📦 依赖管理 (ohpm)

```json5
// oh-package.json5
{
  "dependencies": {
    "@ohos/arkts": "^1.0.0",          // ArkTS 标准库
    "@ohos/hypium": "^1.0.0",         // 测试框架
    "@ohos/hamock": "^1.0.0"          // Mock 库 (按需)
  },
  "devDependencies": {
    "@ohos/eslint": "^1.0.0",
    "@ohos/prettier": "^1.0.0"
  }
}
```

克隆后执行 `ohpm install`。锁文件：`oh-package-lock.json5`。

---

## 🔧 开发工作流

### 代码规范
```bash
# 静态检查
npx @ohos/eslint entry/src/main/ets --ext .ets,.ts

# 格式化
npx @ohos/prettier --write entry/src/main/ets/**/*.ets
```

### 提交规范
遵循 **Conventional Commits**：
```
feat(chat): 增加代码块 Markdown 渲染
fix(link): 修复中继重连退避策略
docs(readme): 更新构建命令
refactor(store): 从 AppStore 拆分 TeamLink
test(noise): 新增重协商场景测试
chore(deps): 升级 ohpm 依赖
```

### 分支策略
- `master` —— 受保护，仅打 Release Tag
- `develop` —— 集成分支 (团队扩大后启用)
- `feat/*`、`fix/*`、`chore/*` —— 短期特性分支

---

## 📄 许可证

**Apache-2.0** —— 详见 [LICENSE](LICENSE)。

```
Copyright 2024 DS Bot Team

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
```

---

## 👥 贡献者

| 角色 | 作者 |
|------|------|
| **原版移动端** | [Fei2411](https://github.com/Fei2411) |
| **HarmonyOS 移植** | DS Bot Team |
| **Noise 协议** | 基于 [Noise Explorer](https://github.com/noiseprotocol/noise-explorer) |
| **密码学基础** | [@noble/ciphers](https://github.com/paulmillr/noble-ciphers)、[@noble/hashes](https://github.com/paulmillr/noble-hashes)、[@noble/curves](https://github.com/paulmillr/noble-curves) |

---

## 🔗 相关项目

- **DS Bot (主仓库)** — [deepseek-ai/ds-bot](https://github.com/deepseek-ai/ds-bot)
- **DS Bot Web** — Bot 管理 Web 面板
- **DeepView** — 动态视图渲染引擎 (内嵌)
- **HarmonyOS 文档** — [developer.harmonyos.com](https://developer.harmonyos.com/)

---

## 💬 获取帮助

- **Issues**: [GitHub Issues](https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dwc13775953197-spec/DS-Bot-HarmonyOS/discussions)
- **DS Bot 社区**: 主仓库内的 Discord/Telegram 链接

---

<div align="center">
  <sub>为 HarmonyOS 而构建 ❤️ • 基于 ArkTS & Hvigor</sub>
</div>