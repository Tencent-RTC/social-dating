import Foundation
import Combine
import AtomicXCore
import ImSDK_Plus

public enum ComponentUsage {
    public static let social = 1024
    public static let socialHome = 10241
    public static let socialMessages = 10242
    public static let socialChat = 10243
    public static let socialCall = 10244

    private static var loginWatch: AnyCancellable?
    private static var logined = false

    public static func report(_ type: Int) {
        DispatchQueue.main.async {
            watchLogin()
            send(type)
        }
    }

    private static func watchLogin() {
        guard loginWatch == nil else { return }
        loginWatch = LoginStore.shared.state
            .subscribe(StatePublisherSelector(keyPath: \LoginState.loginStatus))
            .receive(on: DispatchQueue.main)
            .sink { status in
                let now = status == .logined
                if now && !logined { send(social) }
                logined = now
            }
    }

    private static func send(_ type: Int) {
        let param = "{\"UIComponentType\":\(type)}" as NSString
        V2TIMManager.sharedInstance().callExperimentalAPI(
            api: "reportTUIFeatureUsage",
            param: param,
            succ: { _ in },
            fail: { _, _ in }
        )
    }
}
