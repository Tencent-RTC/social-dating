package io.trtc.tuikit.chat.demo

import android.app.Application
import android.content.Context
import io.trtc.tuikit.atomicx.theme.Theme
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.chat.demo.chat.DemoCallGift
import io.trtc.tuikit.chat.demo.chat.DemoCardRenderer
import io.trtc.tuikit.chat.demo.host.DemoHomeActions
import io.trtc.tuikit.chat.demo.host.DemoMineActions
import io.trtc.tuikit.chat.demo.login.DemoLoginStore
import io.trtc.tuikit.chat.demo.mock.DemoHomeDataSource
import io.trtc.tuikit.chat.demo.mock.DemoMineDataSource
import io.trtc.tuikit.chat.demo.social.DemoCardProtocol
import io.trtc.tuikit.chat.home.HomeKit
import io.trtc.tuikit.chat.hostbase.DemoLocale
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.MsgBanner
import io.trtc.tuikit.chat.mine.MineKit
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.MessageListMessageSummaryRegistry

/** Applies the demo locale to the application context as well (toasts, SDK
 * strings resolved via applicationContext). See [DemoLocale]. */
class Chat1v1App : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(DemoLocale.wrap(base))
    }

    override fun onCreate() {
        super.onCreate()
        DemoText.init(this)
        DemoLoginStore.init(this)
        DemoUi.init(this)
        MsgBanner.install(this)
        DemoCallGift.install(this)
        DemoSessionWatcher.install(this)
        HomeKit.install(DemoHomeDataSource(this), DemoHomeActions)
        MineKit.install(DemoMineDataSource(this), DemoMineActions)
        MessageListMessageSummaryRegistry.setCustomMessageSummary(
            DemoCardProtocol.BUSINESS_ID, DemoCardRenderer.summaryProvider
        )
        // S05: palette and light/dark mode are independent and persisted. The first launch keeps
        // the brand dark look; afterwards the stored mode (dark / light / system) wins.
        ThemeStore.shared(this).apply {
            if (!hasStoredMode()) {
                setTheme(Theme.darkTheme(this@Chat1v1App))
            }
        }
    }
}
