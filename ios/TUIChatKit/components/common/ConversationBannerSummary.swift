import UIKit
import AtomicXCore

public enum ConversationBannerSummary {
    public static func text(for conversation: ConversationInfo) -> String {
        MessageListHelper.getMessageAbstract(conversation.lastMessage)
    }

    /// Same summary with the emoji keys (「[TUIEmoji_Smile]」) drawn as the little emoji pictures.
    public static func attributedText(for conversation: ConversationInfo, font: UIFont, color: UIColor) -> NSAttributedString {
        EmojiManager.shared.createStyledAttributedString(fromEmojiCodes: text(for: conversation), font: font, textColor: color)
    }

    public static func text(forMessage message: MessageInfo?) -> String {
        MessageListHelper.getMessageAbstract(message)
    }

    public static func attributedText(forMessage message: MessageInfo?, font: UIFont, color: UIColor) -> NSAttributedString {
        EmojiManager.shared.createStyledAttributedString(fromEmojiCodes: text(forMessage: message), font: font, textColor: color)
    }

    /// Same picture substitution for an already composed summary (e.g. 「昵称：[TUIEmoji_Smile]」),
    /// so host screens that prefix the sender name do not have to rebuild the line by hand.
    public static func attributedText(forText text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        EmojiManager.shared.createStyledAttributedString(fromEmojiCodes: text, font: font, textColor: color)
    }

    public static func isTypingMessage(_ message: MessageInfo?) -> Bool {
        guard let message, case .custom(let payload) = message.messagePayload,
              let data = payload.customData.data(using: .utf8),
              let info = ChatUtil.jsonData2Dictionary(jsonData: data) else { return false }
        return info["businessID"] as? String == MessageInputView.typingMessageBusinessID
    }

    public static func isCallMessage(_ message: MessageInfo?) -> Bool {
        guard let message else { return false }
        return CallMessageParser.parse(message) != nil
    }
}
