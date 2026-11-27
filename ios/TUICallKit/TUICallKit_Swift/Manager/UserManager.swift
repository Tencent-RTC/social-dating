//
//  UserManager.swift
//  Pods
//
//  Created by vincepzhang on 2025/2/25.
//

import TUICore
import AtomicXCore
import AtomicX
import Foundation

class UserManager: NSObject {
    static let shared = UserManager()
    private override init() {}
    
    static func convertUser(user: V2TIMUserInfo) -> CallParticipantInfo {
        var dstUser = CallParticipantInfo()
        dstUser.id = user.userID ?? ""
        dstUser.name = user.nickName ?? ""
        dstUser.avatarURL = user.faceURL ?? ""
        return dstUser
    }
    
    static func getUserInfosFromIM(userIDs: [String], response: @escaping ([CallParticipantInfo]) -> Void ) {
        V2TIMManager.sharedInstance().getFriendsInfo(userIDs) { friendInfosOptional in
            guard let friendInfos = friendInfosOptional else {
                response([])
                return
            }
            
            var userModels: [CallParticipantInfo] = []
            for friendInfo in friendInfos {
                var userModel = convertUser(user: friendInfo.friendInfo.userFullInfo)
                userModel.remark = friendInfo.friendInfo.friendRemark ?? userModel.remark
                userModels.append(userModel)
            }
            response(userModels)
        } fail: { code, message in
            print("getUsersInfo file code:\(code) message:\(message ?? "")")
            response([])
        }
    }

    /// The signed-in user ID from AtomicXCore LoginStore (TUILogin is not used by the app, so its getters
    /// are empty); falls back to V2TIM in case LoginStore has not filled the profile yet.
    static func selfUserID() -> String {
        if let id = LoginStore.shared.state.value.loginUserInfo?.userID, !id.isEmpty {
            return id
        }
        return V2TIMManager.sharedInstance().getLoginUser() ?? ""
    }

    static func getSelfUserInfo(response: @escaping (CallParticipantInfo) -> Void ){
        let selfId = selfUserID()
        guard !selfId.isEmpty else {
            response(CallParticipantInfo())
            return
        }
        
        getUserInfosFromIM(userIDs: [selfId]) { users in
            response(users.first ?? CallParticipantInfo())
        }
    }

    static func getUserDisplayName(user: CallParticipantInfo) -> String {
        if !user.remark.isEmpty {
            return user.remark
        }
        if !user.name.isEmpty {
            return user.name
        }
        return user.id
    }
}
