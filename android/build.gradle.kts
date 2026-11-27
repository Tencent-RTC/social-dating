plugins {
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("org.jetbrains.kotlin.android") apply false
}
// [1V1] One pinned communication SDK stack for all copied UI modules.
extra["atomicxCoreSdk"] = "io.trtc.uikit:atomicx-core:4.3.11.59"
extra["roomEngineSdk"] = "io.trtc.uikit:rtc_room_engine:4.3.11.59"
extra["liteavSdk"] = "com.tencent.liteav:LiteAVSDK_Professional:13.5.0.20670"
subprojects {
    configurations.configureEach {
        resolutionStrategy.force(
            "com.tencent.imsdk:imsdk-plus:9.1.7822",
            "io.trtc.uikit:atomicx-core:4.3.11.59",
            "io.trtc.uikit:rtc_room_engine:4.3.11.59",
            "com.tencent.liteav:LiteAVSDK_Professional:13.5.0.20670",
            "com.tencent.liteav.tuikit:tuicore:9.0.7667"
        )
    }
}
