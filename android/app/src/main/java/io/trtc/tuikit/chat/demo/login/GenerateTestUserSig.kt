package io.trtc.tuikit.chat.demo.login

import android.util.Base64
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets.UTF_8
import java.util.zip.Deflater
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Ephemeral login result; neither UserSig nor signing keys are persisted by the host. */
class LoginTicket(val sdkAppId: Int, val userId: String, val userSig: String)

/**
 * [DEMO_LOCAL_AUTH] TLS 2.0 UserSig signer for the dev login, together with the SDKAppID and SecretKey it signs with.
 * The encoder is injected so Android API 23 can use android.util.Base64 and JVM tests can use java.util.Base64.
 * Never log the signature or the key.
 */
internal object GenerateTestUserSig {
    // Configure your Tencent Cloud SDKAppID and SecretKey before building.
    val SDKAPPID: Int
    val SECRETKEY: String
    val EXPIRETIME: Long = 604800L

    val isConfigured: Boolean
        get() = SDKAPPID > 0 && SECRETKEY.isNotEmpty() && EXPIRETIME > 0

    fun genTicket(userId: String): LoginTicket {
        val user = userId.trim()
        require(user.isNotEmpty())
        check(isConfigured)
        val sig = genTestUserSig(
            sdkAppId = SDKAPPID,
            userId = user,
            secretKey = SECRETKEY,
            expireSeconds = EXPIRETIME,
            base64 = { Base64.encodeToString(it, Base64.NO_WRAP) }
        )
        return LoginTicket(SDKAPPID, user, sig)
    }

    fun genTestUserSig(
        sdkAppId: Int,
        userId: String,
        secretKey: String,
        expireSeconds: Long,
        nowSeconds: Long = System.currentTimeMillis() / 1000,
        base64: (ByteArray) -> String
    ): String {
        require(sdkAppId > 0 && userId.isNotBlank() && secretKey.isNotEmpty())
        require(expireSeconds > 0 && nowSeconds > 0)
        val content = "TLS.identifier:$userId\nTLS.sdkappid:$sdkAppId\n" +
            "TLS.time:$nowSeconds\nTLS.expire:$expireSeconds\n"
        val mac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(secretKey.toByteArray(UTF_8), "HmacSHA256"))
        }
        val signature = base64(mac.doFinal(content.toByteArray(UTF_8)))
        val document = "{\"TLS.ver\":\"2.0\",\"TLS.identifier\":${quote(userId)}," +
            "\"TLS.sdkappid\":$sdkAppId,\"TLS.expire\":$expireSeconds," +
            "\"TLS.time\":$nowSeconds,\"TLS.sig\":${quote(signature)}}"
        val deflater = Deflater()
        val compressed = ByteArrayOutputStream()
        try {
            deflater.setInput(document.toByteArray(UTF_8))
            deflater.finish()
            val buffer = ByteArray(1024)
            while (!deflater.finished()) {
                val count = deflater.deflate(buffer)
                check(count > 0) { "TLS compression failed" }
                compressed.write(buffer, 0, count)
            }
        } finally {
            deflater.end()
        }
        return base64(compressed.toByteArray())
            .replace('+', '*').replace('/', '-').replace('=', '_')
    }

    private fun quote(value: String) = buildString {
        append('"')
        for (ch in value) {
            when (ch) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                else -> if (ch.code < 32) append("\\u" + ch.code.toString(16).padStart(4, '0')) else append(ch)
            }
        }
        append('"')
    }
}
