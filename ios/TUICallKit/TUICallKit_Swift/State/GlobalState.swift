//
//  GlobalState.swift
//  Pods
//
//  Created by vincepzhang on 2025/2/6.
//

import Foundation

class GlobalState: NSObject {
    var enableMuteMode: Bool = UserDefaults.standard.value(forKey: ENABLE_MUTEMODE_USERDEFAULT) as? Bool == true ? true : false
    var enableFloatWindow: Bool = true
    var enableIncomingBanner: Bool = false
    var enableVirtualBackground: Bool = true
    var enableForceUseV2API: Bool = false
    var enableMultiDeviceAbility: Bool = false
    /// AI 实时字幕 / 翻译不在产品范围内：默认关闭，通话页不出现右上角开关，主叫也不自动起转写。
    var enableAITranscriber: Bool = false
    var orientation: Orientation = .portrait
}

enum Orientation: Int{
    case portrait = 0
    case landscape = 1
    case auto = 2
}
