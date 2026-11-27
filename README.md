# Social-Dating

English | [简体中文](README.cn.md)

## Overview

**Social-Dating** is an open-source 1v1 social chat and audio/video calling solution for **Android** and **iOS**, built on Tencent Cloud Instant Messaging (`IMSDK`), Real-Time Communication (`TRTC` / `RTCRoomEngine`), and `AtomicXCore`.

It provides complete, modular UI implementations for discovery, 1v1 messaging, interactive chat widgets, audio/video calling, and user profiles so you can quickly evaluate or build a 1v1 social dating experience on native mobile platforms.

## Features

- **Discovery & Profile (`Home` & `Mine`)**
  - Discovery feed and profile cards with detail pages, photo albums, and local demo fixtures.
  - Supports binding mock discovery profiles to real IM test accounts for instant messaging.
- **1v1 Instant Messaging (`Chat`)**
  - Recent chats, friend list, search, and a dedicated **Greetings** inbox for un-replied messages from strangers (requires IM Ultimate/Enterprise plan for conversation marks).
  - Supports text, image, voice, video, emoji, and file messages.
  - Rich 1v1 social interaction messages: Pat, Listen Together, Photo Swap, Burn-After-Reading Private Photo, Rock-Paper-Scissors, Dice, Crush Quiz, Gifts, Red Packets, and Location.
- **1v1 Audio & Video Calling (`Call`)**
  - Powered by `TUICallKit` with 1v1 voice and video calls, in-call gift sending, and call history.
- **Personalization**
  - Multi-language support (English, Simplified Chinese, Traditional Chinese), Light/Dark mode, and customizable theme colors.

## Project Structure

```text
social-dating/
├── android/               # Android project (rootProject.name = "Social-Dating")
│   ├── app/               # Host demo application
│   ├── uikit/             # Chat UIKit components
│   ├── callkit/           # TUICallKit (1v1 audio/video calling)
│   ├── homekit/           # Discovery feed & profile UI
│   ├── minekit/           # Me / personal center UI
│   ├── hostbase/          # Shared host abstractions & models
│   └── atomic_x/          # Shared base tokens, theme, and utilities
├── ios/                   # iOS project
│   ├── App/               # Host demo application (CocoaPods workspace)
│   ├── TUIChatKit/        # Chat UIKit components
│   ├── TUICallKit/        # TUICallKit (1v1 audio/video calling)
│   ├── TUIHomeKit/        # Discovery feed & profile UI
│   ├── TUIMineKit/        # Me / personal center UI
│   ├── TUIHostBase/       # Shared host abstractions & models
│   └── AtomicX/           # Shared base tokens, theme, and utilities
└── tools/
    ├── seed_demo_data.py  # Script to seed demo accounts, friends, and conversations
    └── seed_demo_data.json
```

## Quick Start

### 1. Create an Application and Obtain Credentials

1. Log in to the [Tencent RTC Console](https://console.trtc.io/) and create an application (or select an existing one).
2. In **Application Overview / Configuration**, note down your **SDKAppID** and **SecretKey**.

### 2. Clone the Repository

```bash
git clone https://github.com/Tencent-RTC/social-dating.git
cd social-dating
```

### 3. Run on Android

**Prerequisites**
- Android Studio
- JDK 17
- Android 6.0 (API level 23) or higher (`compileSdk 35`, Gradle Wrapper `8.9`, AGP `8.7.0`, Kotlin `2.1.10`)

**Configure `SDKAppID` and `SecretKey`**

Open `android/app/src/main/java/io/trtc/tuikit/chat/demo/login/GenerateTestUserSig.kt` and assign your credentials:

```kotlin
internal object GenerateTestUserSig {
    val SDKAPPID: Int = 1400000001          // Replace with your SDKAppID
    val SECRETKEY: String = "your_secret"   // Replace with your SecretKey
    val EXPIRETIME: Long = 604800L
    ...
}
```

> Both `SDKAPPID` and `SECRETKEY` are intentionally left uninitialized so the project will fail to compile until you configure your own credentials.

**Build & Run**
- Open the `android/` directory in Android Studio, wait for Gradle sync, select the `app` configuration, and click **Run**.
- Or build from the command line:

```bash
cd android
./gradlew :app:assembleDebug
```

### 4. Run on iOS

**Prerequisites**
- macOS with Xcode 15+
- iOS 15.0 or higher
- [CocoaPods](https://cocoapods.org/)

**Configure `SDKAppID` and `SecretKey`**

Open `ios/App/Sources/Login/GenerateTestUserSig.swift` and assign your credentials:

```swift
enum GenerateTestUserSig {
    static let SDKAPPID: Int32 = 1400000001        // Replace with your SDKAppID
    static let SECRETKEY: String = "your_secret"   // Replace with your SecretKey
    static let EXPIRETIME: Int64 = 604800
    ...
}
```

> Both `SDKAPPID` and `SECRETKEY` are intentionally left uninitialized so the project will fail to compile until you configure your own credentials.

**Install Pods & Run**

```bash
cd ios/App
pod install
open Chat1v1Demo.xcworkspace
```

In Xcode, select a simulator or connected device and click **Run**. To run on a physical device, configure your Apple Developer Team and Bundle Identifier under **Signing & Capabilities**.

### 5. (Optional) Seed Demo Data

You can log in directly with any `userID` to test basic chat and calling, or use the bundled Python 3 script (standard library only, no third-party packages required) to import 29 demo accounts, 96 friend pairs, and 80 sample conversations into your own IM application:

```bash
# Preview what will be imported (no network requests)
python3 tools/seed_demo_data.py --dry-run

# Import demo data into your SDKAppID (prompts for SecretKey interactively)
python3 tools/seed_demo_data.py --sdkappid <YOUR_SDKAPPID>

# For non-China data centers, specify --region (sgp, kr, jpn, ger, usa, idn, ksa)
python3 tools/seed_demo_data.py --sdkappid <YOUR_SDKAPPID> --region sgp

# Verify whether demo data has been imported
python3 tools/seed_demo_data.py --sdkappid <YOUR_SDKAPPID> --verify
```

You can also pass credentials via environment variables `CHAT1V1_SDKAPPID` and `CHAT1V1_SECRETKEY`, or pass `--skip-messages` to import only accounts and friend relationships.

After seeding, log in on two devices with any two of the preset accounts (`jianwan_000001`, `jianwan_000010`, `jianwan_000011`, `jianwan_000012`, `jianwan_000013`) to immediately test 1v1 messaging and audio/video calls.

## Notes

- **Production Security (`UserSig`)**: Calculating `UserSig` on the client is only intended for local demo evaluation and debugging. Embedding `SecretKey` in a client binary exposes it to reverse engineering. In production, generate `UserSig` on your own backend server. See [How do I calculate UserSig on the server?](https://trtc.io/document/34385?product=chat&menulabel=serverapis).
- **Offline Push**: Vendor push configurations, certificates, and push SDK integrations have been omitted from this open-source repository. If you need offline push notifications, integrate Tencent Cloud `TIMPush` with your own push credentials and certificates.
- **Emoji Assets Notice**: Out of respect for emoji design copyrights, large custom emoji packs are not bundled. Please replace demo assets and emoji packs with your own licensed assets before commercial release. The default yellow-face emoji pack is copyrighted by Tencent Cloud; please [contact us](https://trtc.io/contact) if you need commercial authorization.

## License

This project is licensed under the [MIT License](LICENSE).
