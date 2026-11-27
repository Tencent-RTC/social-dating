# Social-Dating

[English](README.md) | 简体中文

## 项目简介

**Social-Dating** 是基于腾讯云即时通信 IM（`IMSDK`）、实时音视频（`TRTC` / `RTCRoomEngine`）和 `AtomicXCore` 打造的 **Android** & **iOS** 原生 1v1 社交聊天与音视频通话开源方案。

项目提供完整的模块化 UI 实现，覆盖发现页、1v1 即时消息、趣味社交聊天互动、1v1 音视频通话与个人中心，帮助你快速体验或构建 1v1 社交交友应用。

## 核心功能

- **发现与个人主页（Home & Mine）**
  - 发现页推荐卡片、个人资料详情、相册与个人中心（由本地演示数据驱动）。
  - 支持将发现页演示角色绑定到真实 IM 测试账号，直接发起 1v1 聊天。
- **1v1 即时消息（Chat）**
  - 最近会话列表、好友列表、搜索，以及陌生人「打招呼消息」分类（会话标记功能需 IM 开发版/旗舰版/企业版支持）。
  - 支持文本、图片、语音、视频、表情、文件等基础消息类型。
  - 内置丰富的 1v1 社交特色互动消息：拍一拍、一起听歌、交换照片、阅后即焚私密照、猜拳、骰子、默契问答、礼物、红包、位置等。
- **1v1 音视频通话（Call）**
  - 集成 `TUICallKit`，支持 1v1 语音/视频通话、通话中送礼互动与通话记录查看。
- **个性化配置**
  - 支持简体中文、繁体中文、英文多语言切换，以及浅色/深色模式与多套主题色。

## 目录结构

```text
social-dating/
├── android/               # Android 工程（rootProject.name = "Social-Dating"）
│   ├── app/               # 宿主 Demo 应用
│   ├── uikit/             # Chat UIKit 聊天组件
│   ├── callkit/           # TUICallKit 1v1 音视频通话组件
│   ├── homekit/           # 发现页与资料详情组件
│   ├── minekit/           # 个人中心组件
│   ├── hostbase/          # 宿主公共抽象与基础模型
│   └── atomic_x/          # 通用主题、Token 与基础工具模块
├── ios/                   # iOS 工程
│   ├── App/               # 宿主 Demo 应用（CocoaPods Workspace）
│   ├── TUIChatKit/        # Chat UIKit 聊天组件
│   ├── TUICallKit/        # TUICallKit 1v1 音视频通话组件
│   ├── TUIHomeKit/        # 发现页与资料详情组件
│   ├── TUIMineKit/        # 个人中心组件
│   ├── TUIHostBase/       # 宿主公共抽象与基础模型
│   └── AtomicX/           # 通用主题、Token 与基础工具模块
└── tools/
    ├── seed_demo_data.py  # 演示数据导入脚本（账号、好友、示例会话）
    └── seed_demo_data.json
```

## 快速开始

### 1. 创建应用并获取密钥

1. 登录[腾讯云即时通信 IM 控制台](https://console.cloud.tencent.com/im)（海外站请访问 [Tencent RTC Console](https://console.trtc.io/)），创建或选择一个已有应用。
2. 在应用详情的**基本配置**中获取你的 **SDKAppID** 和 **SecretKey**。

### 2. 克隆仓库

```bash
git clone https://github.com/Tencent-RTC/social-dating.git
cd social-dating
```

### 3. 运行 Android

**环境要求**
- Android Studio
- JDK 17
- Android 6.0（API 23）及以上设备或模拟器（`compileSdk 35`，内置 Gradle Wrapper `8.9`、AGP `8.7.0`、Kotlin `2.1.10`）

**配置 `SDKAppID` 和 `SecretKey`**

打开 `android/app/src/main/java/io/trtc/tuikit/chat/demo/login/GenerateTestUserSig.kt`，填入你的 `SDKAppID` 和 `SecretKey`：

```kotlin
internal object GenerateTestUserSig {
    val SDKAPPID: Int = 1400000001          // 替换为你的 SDKAppID
    val SECRETKEY: String = "your_secret"   // 替换为你的 SecretKey
    val EXPIRETIME: Long = 604800L
    ...
}
```

> 仓库中刻意未给 `SDKAPPID` 和 `SECRETKEY` 设置默认值，未填写前将直接编译报错，填入后即可正常编译运行。

**编译运行**
- 使用 Android Studio 打开 `android/` 目录，等待 Gradle 同步完成后，选择 `app` 运行配置并点击 **Run**。
- 或通过命令行编译：

```bash
cd android
./gradlew :app:assembleDebug
```

### 4. 运行 iOS

**环境要求**
- macOS 与 Xcode 15 及以上版本
- iOS 15.0 及以上设备或模拟器
- [CocoaPods](https://cocoapods.org/)

**配置 `SDKAppID` 和 `SecretKey`**

打开 `ios/App/Sources/Login/GenerateTestUserSig.swift`，填入你的 `SDKAppID` 和 `SecretKey`：

```swift
enum GenerateTestUserSig {
    static let SDKAPPID: Int32 = 1400000001        // 替换为你的 SDKAppID
    static let SECRETKEY: String = "your_secret"   // 替换为你的 SecretKey
    static let EXPIRETIME: Int64 = 604800
    ...
}
```

> 仓库中刻意未给 `SDKAPPID` 和 `SECRETKEY` 设置默认值，未填写前将直接编译报错，填入后即可正常编译运行。

**安装依赖并运行**

```bash
cd ios/App
pod install
open Chat1v1Demo.xcworkspace
```

在 Xcode 中选择模拟器或真机点击 **Run** 即可运行。真机运行前，请在 **Signing & Capabilities** 中配置你自己的 Apple Developer Team 和 Bundle Identifier。

### 5. （可选）导入演示数据

你可以直接输入任意 `userID` 登录体验基础聊天与通话，也可以运行仓库自带的 Python 3 脚本（仅使用标准库，无需额外安装依赖），将 29 个演示账号、96 对好友关系和 80 个示例会话一键导入到你自己的 IM 应用中：

```bash
# 仅预览将要导入的内容（不联网）
python3 tools/seed_demo_data.py --dry-run

# 将演示数据导入到你的 SDKAppID（会在终端交互提示输入 SecretKey）
python3 tools/seed_demo_data.py --sdkappid <你的 SDKAPPID>

# 若为海外数据中心应用，请通过 --region 指定（支持 sgp、kr、jpn、ger、usa、idn、ksa）
python3 tools/seed_demo_data.py --sdkappid <你的 SDKAPPID> --region sgp

# 校验演示数据是否已完整导入
python3 tools/seed_demo_data.py --sdkappid <你的 SDKAPPID> --verify
```

也支持通过环境变量 `CHAT1V1_SDKAPPID`、`CHAT1V1_SECRETKEY` 传入凭据，或添加 `--skip-messages` 仅导入账号和好友关系。

导入完成后，两台设备分别登录预设账号（`jianwan_000001`、`jianwan_000010`、`jianwan_000011`、`jianwan_000012`、`jianwan_000013`）中的任意两个，即可立即体验 1v1 聊天和音视频通话。

## 注意事项

- **生产环境安全（`UserSig`）**：客户端本地计算 `UserSig` 仅适用于快速跑通 Demo 与功能调试。将 `SecretKey` 写在客户端代码中存在反编译泄露风险，正式上线前请务必将 `UserSig` 计算逻辑迁移至业务服务端。参考文档：[服务端计算 UserSig](https://cloud.tencent.com/document/product/269/32688#Server)。
- **离线推送（Offline Push）**：本开源仓库已移除第三方厂商离线推送配置、证书及推送 SDK 依赖。如需接入离线推送，请根据腾讯云 IM 离线推送（`TIMPush`）文档自行配置证书与通道。
- **表情版权声明**：出于对表情设计版权的尊重，本项目不包含大表情切图，正式商用前请替换为自有版权素材。默认小黄脸表情包版权归腾讯云所有，如需商用授权请[联系我们](https://trtc.io/contact)。

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
