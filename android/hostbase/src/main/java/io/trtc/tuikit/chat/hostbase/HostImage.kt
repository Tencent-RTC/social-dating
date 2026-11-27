package io.trtc.tuikit.chat.hostbase

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

fun interface HostRemoteImageLoader {
    fun load(view: ImageView, url: String, onLoaded: (Boolean) -> Unit)
}

object HostImage {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newFixedThreadPool(3)
    private val cache = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    /** One download per URL: every view / prefetch waiting for the same picture shares the result. */
    private val lock = Any()
    private val inflight = HashMap<String, MutableList<(Bitmap?) -> Unit>>()

    @Volatile
    var remoteLoader: HostRemoteImageLoader = HostRemoteImageLoader { view, url, onLoaded ->
        if (url.isBlank()) {
            onLoaded(false)
            return@HostRemoteImageLoader
        }
        loadBitmap(url) { bitmap ->
            if (view.getTag(R.id.host_image_ref) != url) return@loadBitmap
            if (bitmap != null) view.setImageBitmap(bitmap)
            onLoaded(bitmap != null)
        }
    }

    /** [onDone] runs on the main thread, immediately when the picture is already cached. */
    private fun loadBitmap(url: String, onDone: (Bitmap?) -> Unit) {
        cache.get(url)?.let {
            onDone(it)
            return
        }
        synchronized(lock) {
            val waiting = inflight[url]
            if (waiting != null) {
                waiting += onDone
                return
            }
            inflight[url] = mutableListOf(onDone)
        }
        executor.execute {
            val bitmap = runCatching {
                (URL(url).openConnection() as HttpURLConnection).run {
                    connectTimeout = 5000
                    readTimeout = 8000
                    requestMethod = "GET"
                    inputStream.use { BitmapFactory.decodeStream(it) }
                }
            }.getOrNull()
            val waiting = synchronized(lock) { inflight.remove(url) ?: mutableListOf() }
            main.post {
                if (bitmap != null) cache.put(url, bitmap)
                waiting.forEach { it(bitmap) }
            }
        }
    }

    /**
     * Warms the memory cache for [urls] so a list can be built with its pictures already available (no placeholder
     * frame). [onReady] runs on the main thread once every picture is cached, or straight away when nothing is left.
     */
    fun prefetch(urls: Collection<String>, onReady: () -> Unit) {
        val todo = urls.filter { isRemote(it) && cache.get(it) == null }.distinct()
        if (todo.isEmpty()) {
            onReady()
            return
        }
        val left = java.util.concurrent.atomic.AtomicInteger(todo.size)
        todo.forEach { url ->
            loadBitmap(url) { if (left.decrementAndGet() == 0) onReady() }
        }
    }

    fun isRemote(ref: String?): Boolean =
        ref != null && (ref.startsWith("http://") || ref.startsWith("https://"))

    fun bind(view: ImageView, ref: String?, onLoaded: ((Boolean) -> Unit)? = null) {
        view.setTag(R.id.host_image_ref, ref)
        view.setImageDrawable(null)
        if (ref.isNullOrBlank()) {
            onLoaded?.invoke(false)
            return
        }
        if (isRemote(ref)) {
            remoteLoader.load(view, ref) { onLoaded?.invoke(it) }
            return
        }
        val res = resolveDrawable(view.context, ref)
        if (res != 0) view.setImageResource(res)
        onLoaded?.invoke(res != 0)
    }

    fun resolveDrawable(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "drawable", context.packageName)
}

object HostThread {
    private val main = Handler(Looper.getMainLooper())

    fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }
}

class AvatarView(context: Context, name: String, color: String = DemoUi.ACCENT, sizeDp: Int = 64) :
    FrameLayout(context) {
    private val initials = DemoUi.text(context, DemoUi.initials(name), 22f, "#FFFFFF", true).apply {
        gravity = Gravity.CENTER
    }
    private val image = ImageView(context).apply { scaleType = ImageView.ScaleType.CENTER_CROP }

    init {
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor(color))
        }
        clipToOutline = true
        addView(initials, LayoutParams(-1, -1))
        addView(image, LayoutParams(-1, -1))
        layoutParams = LinearLayout.LayoutParams(DemoUi.dp(context, sizeDp), DemoUi.dp(context, sizeDp))
    }

    fun load(ref: String?) {
        if (ref.isNullOrBlank()) return
        HostImage.bind(image, ref) { loaded -> initials.visibility = if (loaded) GONE else VISIBLE }
    }
}

object HostPhoto {
    fun tile(context: Context, ref: String?, radiusDp: Float = 0f): FrameLayout = FrameLayout(context).apply {
        setBackgroundColor(DemoUi.tokens.bgColorFunction)
        addView(ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            HostImage.bind(this, ref)
        }, FrameLayout.LayoutParams(-1, -1))
        if (radiusDp > 0f) Host.roundedClip(this, radiusDp)
    }
}

class HostStateView(context: Context) : LinearLayout(context) {
    private val message: TextView

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER
        message = Host.text(context, "", 13f, DemoUi.tokens.textColorTertiary).apply { gravity = Gravity.CENTER }
        addView(message, LayoutParams(-2, -2))
        visibility = GONE
    }

    fun showLoading() {
        message.text = DemoText.get(R.string.demo_loading)
        setOnClickListener(null)
        isClickable = false
        visibility = VISIBLE
    }

    fun showError(retry: () -> Unit) {
        message.text = DemoText.get(R.string.demo_load_failed_tap_to_retry)
        setOnClickListener { retry() }
        visibility = VISIBLE
    }

    fun showEmpty() {
        message.text = DemoText.get(R.string.demo_nothing_here_yet)
        setOnClickListener(null)
        isClickable = false
        visibility = VISIBLE
    }

    fun hide() {
        visibility = GONE
    }

    companion object {
        fun asContent(context: Context): HostStateView = HostStateView(context).apply {
            layoutParams = LayoutParams(-1, -1)
        }
    }
}
