package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

object CallGiftBridge {
    var sender: ((peerId: String, onResult: (Boolean) -> Unit) -> Unit)? = null
    var inspector: ((customData: String?) -> String?)? = null
}
