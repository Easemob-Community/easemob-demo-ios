//
//  ChatServiceImplement.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/6.
//

import UIKit

@objcMembers public class ChatServiceImplement: NSObject {
    private var responseDelegates: NSHashTable<ChatResponseListener> = NSHashTable<ChatResponseListener>.weakObjects()
    
    public private(set) var to = ""

    /// Parent group for thread recalls; the SDK recall callback carries the thread ID.
    var parentGroupId = ""
    
    @objc required public init(to: String) {
        super.init()
        self.to = to
        ChatClient.shared().chatManager?.add(self, delegateQueue: nil)
    }
    
    deinit {
        ChatClient.shared().chatManager?.remove(self)
    }
}

extension ChatServiceImplement: ChatService {
    public func fetchChatThreadHistoryMessages(conversationId: String, cursor: String?, pageSize: UInt, completion: @escaping (ChatError?, [ChatMessage], String?) -> Void) {
        // SDK 5.0 pages server history via an opaque cursor (``EMCursorResult/cursor``). The caller owns
        // the cursor and the "no more" flag; here we simply fetch from the given cursor and hand back the
        // next one (nil for the first page).
        let option = ChatFetchServerMessagesOption()
        option.direction = .down
        ChatClient.shared().chatManager?.fetchMessagesFromServer(by: conversationId, conversationType: .groupChat, cursor: cursor, pageSize: pageSize, option: option, completion: { result, error in
            completion(error, result?.list ?? [], result?.cursor)
        })
    }
    
    
    public func reaction(reaction: String, message: ChatMessage, completion: @escaping (ChatError?) -> Void) {
        let messageReaction = ChatClient.shared().chatManager?.getMessageWithMessageId(message.messageId)?.reactionList?.first(where: { $0.reaction ?? "" == reaction })
        if messageReaction == nil {
            ChatClient.shared().chatManager?.addReaction(reaction, toMessage: message.messageId, completion: { error in
                completion(error)
            })
        } else {
            if messageReaction!.isAddedBySelf {
                ChatClient.shared().chatManager?.removeReaction(reaction, fromMessage: message.messageId, completion: { error in
                    completion(error)
                })
            } else {
                ChatClient.shared().chatManager?.addReaction(reaction, toMessage: message.messageId, completion: { error in
                    completion(error)
                })
            }
        }
    }
    
    public func edit(messageId: String, text: String, completion: @escaping (ChatError?, ChatMessage?) -> Void) {
        let rawMessage = ChatClient.shared().chatManager?.getMessageWithMessageId(messageId)
        let body = ChatTextMessageBody(text: text)
        if let rawBody = rawMessage?.body as? ChatTextMessageBody {
            body.targetLanguages = rawBody.targetLanguages
        }
        ChatClient.shared().chatManager?.modifyMessage(messageId, body: body, ext: nil, completion: { error, message in
            completion(error,message)
        })
    }
    
    public func recall(messageId: String, completion: @escaping (ChatError?) -> Void) {
        let original = ChatClient.shared().chatManager?.getMessageWithMessageId(messageId)
        let payload = original.flatMap { MessageRecallNotice(message: $0, operatorId: ChatUIKitContext.shared?.currentUserId ?? ChatClient.shared().currentUsername ?? "", parentGroupId: self.parentGroupId).payload }
        ChatClient.shared().chatManager?.recallMessage(withMessageId: messageId, ext: payload, completion: { error in
            completion(error)
        })
    }
    
    public func bindChatEventsListener(listener: ChatResponseListener) {
        if self.responseDelegates.contains(listener) {
            return
        }
        self.responseDelegates.add(listener)
    }
    
    public func unbindChatEventsListener(listener: ChatResponseListener) {
        if self.responseDelegates.contains(listener) {
            self.responseDelegates.remove(listener)
        }
    }
    
    public func send(message: ChatMessage, completion: @escaping (ChatError?, ChatMessage?) -> Void) {
        let message = message
        ChatClient.shared().chatManager?.send(message, progress: nil, completion: { message, error in
//            self?.pushSendNotification(message: message)
            completion(error,message)
        })
    }
    
    private func pushSendNotification(message: ChatMessage?) {
        if let conversationId = message?.conversationId {
            NotificationCenter.default.post(name: Notification.Name("EaseChatUIKit_Conversation_last_message_need_update"), object: conversationId)
        }
    }
    
    public func removeLocalMessage(messageId: String) {
        ChatClient.shared().chatManager?.getConversationWithConvId(self.to)?.deleteMessage(withId: messageId, error: nil)
        
    }
    
    public func removeHistoryMessages() {
        ChatClient.shared().chatManager?.getConversationWithConvId(self.to)?.deleteAllMessages(nil)
    }
    
    public func markMessageAsRead(messageId: String) {
        if let message = ChatClient.shared().chatManager?.getMessageWithMessageId(messageId) {
            ChatClient.shared().chatManager?.sendMessageReadReceipts([message]) { error in
                
                if error != nil {
                    consoleLogInfo("sendMessageReadReceipts error:\(error?.errorDescription ?? "")", type: .error)
                }
            }
        }
        
    }
    
    public func markAllMessagesAsRead() {
        ChatClient.shared().chatManager?.clearConversationUnreadMessageCount(self.to) { error in
            if error != nil {
                consoleLogInfo("clearConversationUnreadMessageCount error:\(error?.errorDescription ?? "")", type: .error)
            }
        }
    }
    
    public func loadMessages(start messageId: String, cursor: String?, pageSize: UInt, searchMessage: Bool, completion: @escaping (ChatError?, [ChatMessage], String?) -> Void) {
        let finish: (ChatError?, [ChatMessage], String?) -> Void = { error, messages, cursor in
            completion(error, messages.filter { !$0.hidesModeratorRecallNotice }, cursor)
        }

        if ChatUIKitContext.shared?.chatCache == nil {
            ChatUIKitContext.shared?.chatCache = [String:ChatUserProfileProtocol]()
        }
        if ChatUIKitClient.shared.option.option_UI.loadLocalHistoryMessages {
            ChatClient.shared().chatManager?.getConversationWithConvId(self.to)?.loadMessagesStart(fromId: messageId, count: Int32(pageSize), searchDirection: searchMessage ? .down:.up,completion: { messages, error in
                if error == nil,let messages = messages {
                    for message in messages {
                        // Compatibility with old data: legacy messages have no `senderInfo`, so fall back
                        // to the sender profile previously stored in the message's `ease_chat_uikit_user_info` ext.
                        if message.senderInfo == nil {
                            if let dic = message.ext?["ease_chat_uikit_user_info"] as? Dictionary<String,Any> {
                                let user = ChatUIKitContext.shared?.userCache?[message.from] as? ChatUserProfile
                                if user?.modifyTime ?? 0 < message.timestamp {
                                    let user = ChatUserProfile()
                                    user.setValuesForKeys(dic)
                                    if user.id.isEmpty {
                                        user.id = message.from
                                    }
                                    user.modifyTime = message.timestamp
                                    ChatUIKitContext.shared?.chatCache?[message.from] = user
                                }
                            }
                        }
                        if let dic = message.ext?["ease_chat_uikit_text_url_preview"] as? Dictionary<String,String>,let url = dic["url"] {
                            let content = URLPreviewManager.HTMLContent()
                            if let description = dic["description"] {
                                content.descriptionHTML = description
                            }
                            if let imageURL = dic["imageUrl"] {
                                content.imageURL = imageURL
                            }
                            if let title = dic["title"] {
                                content.title = title
                                URLPreviewManager.caches[url] = content
                            }
                            content.towards = message.direction == .send ? .right:.left
                        }
                    }
                }
                finish(error,messages ?? [],nil)
            })
        } else {
            let type = ChatClient.shared().chatManager?.getConversationWithConvId(self.to)?.type ?? .chat
            let option = ChatFetchServerMessagesOption()
            option.direction = searchMessage ? .down:.up
            let cacheSenderInfo: (ChatMessage) -> Void = { message in
                guard message.senderInfo == nil else { return }
                if let dic = message.ext?["ease_chat_uikit_user_info"] as? Dictionary<String,Any> {
                    let user = ChatUIKitContext.shared?.userCache?[message.from] as? ChatUserProfile
                    if user?.modifyTime ?? 0 < message.timestamp {
                        let user = ChatUserProfile()
                        user.setValuesForKeys(dic)
                        if user.id.isEmpty {
                            user.id = message.from
                        }
                        user.modifyTime = message.timestamp
                        ChatUIKitContext.shared?.chatCache?[message.from] = user
                    }
                }
            }
            if searchMessage {
                // Anchored jump to a specific (locally available) message: page forward from its
                // timestamp. The new server API has no message-id anchor, so we use the time window.
                if let timestamp = ChatClient.shared().chatManager?.getMessageWithMessageId(messageId)?.timestamp {
                    option.startTime = Int(timestamp) + 1
                }
                ChatClient.shared().chatManager?.fetchMessagesFromServer(by: self.to, conversationType: type, cursor: nil, pageSize: pageSize, option: option, completion: { result, error in
                    if error == nil, let messages = result?.list {
                        for message in messages { cacheSenderInfo(message) }
                    }
                    // Anchored search is a one-shot fetch, so there is no continuation cursor.
                    finish(error,result?.list ?? [],nil)
                })
                return
            }
            // Load older page. SDK 5.0 pages via an opaque cursor. The caller owns the cursor and the
            // "no more" flag and passes the cursor in (nil for the first page); we hand back the next one.
            ChatClient.shared().chatManager?.fetchMessagesFromServer(by: self.to, conversationType: type, cursor: cursor, pageSize: pageSize, option: option, completion: { result, error in
                if error == nil, let messages = result?.list {
                    for message in messages { cacheSenderInfo(message) }
                }
                finish(error,result?.list ?? [],result?.cursor)
            })
        }
    }
    
    public func searchMessage(keyword: String, pageSize: UInt, userId: String, completion: @escaping (ChatError?, [ChatMessage]) -> Void) {
        ChatClient.shared().chatManager?.getConversationWithConvId(self.to)?.loadMessages(withKeyword: keyword, timestamp: -1, count: Int32(pageSize), fromUsers: [userId], searchDirection: .up, scope: .content, completion: { messages, error in
            completion(error,messages ?? [])
        })
    }
    
    public func translateMessage(message: ChatMessage, completion: @escaping (ChatError?, ChatMessage?) -> Void) {
        ChatClient.shared().chatManager?.translate(message, targetLanguages: [Appearance.chat.targetLanguage.rawValue], completion: { message,error in
            completion(error,message)
        })
    }
    
    public func pinMessage(messageId: String, completion: @escaping (ChatError?) -> Void) {
        ChatClient.shared().chatManager?.pinMessage(messageId, completion: { message,error in
            completion(error)
        })
    }
    
    public func unpinMessage(messageId: String, completion: @escaping (ChatError?) -> Void) {
        ChatClient.shared().chatManager?.unpinMessage(messageId, completion: { message,error in
            completion(error)
        })
    }
    
    public func pinnedMessages(conversationId: String, completion: @escaping ([ChatMessage]?, ChatError?) -> Void) {
        ChatClient.shared().chatManager?.getPinnedMessages(fromServer: conversationId, completion: { messages, error in
            completion(messages,error)
        })
    }
}

extension ChatServiceImplement: ChatEventsListener {
    
    public func onMessageReadReceipts(_ aReceipts: [MessageReadReceipt]) {
        for listener in self.responseDelegates.allObjects {
            listener.messageReadReceiptReceived(receipt: aReceipts)
        }
    }
    
    public func onMessagePinChanged(_ messageId: String, conversationId: String, operation pinOperation: MessagePinOperation, pinInfo: MessagePinInfo) {
        for listener in self.responseDelegates.allObjects {
            listener.onMessageStickiedTop(conversationId: conversationId, messageId: messageId, operation: pinOperation, info: pinInfo)
        }
    }
    
    public func messagesDidReceive(_ aMessages: [ChatMessage]) {
        for listener in self.responseDelegates.allObjects {
            for message in aMessages {
                if message.senderInfo == nil {
                    if let dic = message.ext?["ease_chat_uikit_user_info"] as? Dictionary<String,Any> {
                        let profile = ChatUserProfile()
                        profile.setValuesForKeys(dic)
                        profile.id = message.from
                        profile.modifyTime = message.timestamp
                        ChatUIKitContext.shared?.chatCache?[message.from] = profile
                        if ChatUIKitContext.shared?.userCache?[message.from] == nil {
                            ChatUIKitContext.shared?.userCache?[message.from] = profile
                        } else {
                            ChatUIKitContext.shared?.userCache?[message.from]?.nickname = profile.nickname
                            ChatUIKitContext.shared?.userCache?[message.from]?.avatarURL = profile.avatarURL
                        }
                    }
                } else {
                    if let profile = message.senderInfo {
                        if ChatUIKitContext.shared?.userCache?[message.from] == nil {
                            let user = ChatUserProfile()
                            user.id = profile.userId ?? message.from
                            user.nickname = profile.nickname ?? ""
                            user.avatarURL = profile.avatarUrl ?? ""
                            user.modifyTime = message.timestamp
                            user.remark = profile.remark ?? ""
                            ChatUIKitContext.shared?.userCache?[message.from] = user
                        } else {
                            ChatUIKitContext.shared?.userCache?[message.from]?.nickname = message.senderInfo?.nickname ?? ""
                            ChatUIKitContext.shared?.userCache?[message.from]?.avatarURL = message.senderInfo?.avatarUrl ?? ""
                        }
                    }
                }
                listener.onMessageDidReceived(message: message)
            }
        }
    }
    
    public func cmdMessagesDidReceive(_ aCmdMessages: [ChatMessage]) {
        for listener in self.responseDelegates.allObjects {
            for message in aCmdMessages {
                listener.onCMDMessageDidReceived(message: message)
            }
        }
    }
    
    public func messagesInfoDidRecall(_ aRecallMessagesInfo: [RecallInfo]) {
        for listener in self.responseDelegates.allObjects {
            for info in aRecallMessagesInfo {
                listener.onMessageDidRecalled(recallInfo: info)
            }
        }
    }
    
    public func messageStatusDidChange(_ aMessage: ChatMessage, error aError: ChatError?) {
        for listener in self.responseDelegates.allObjects {
            listener.onMessageStatusDidChanged(message: aMessage, status: aError == nil ? .succeed:.failure, error: aError)
        }
    }
    
    public func messageAttachmentStatusDidChange(_ aMessage: ChatMessage, error aError: ChatError?) {
        for listener in self.responseDelegates.allObjects {
            listener.onMessageAttachmentStatusChanged(message: aMessage, error: aError)
        }
    }
    
    public func messageReactionDidChange(_ changes: [MessageReactionChange]) {
        for listener in self.responseDelegates.allObjects {
            listener.onMessageReactionChanged(changes: changes)
        }
    }
    
    public func messagesDidDeliver(_ aMessages: [ChatMessage]) {
        for aMessage in aMessages {
            for listener in self.responseDelegates.allObjects {
                listener.onMessageStatusDidChanged(message: aMessage, status: .delivered, error: nil)
            }
        }
    }
    
    public func messagesDidRead(_ aMessages: [ChatMessage]) {
        for aMessage in aMessages {
            for listener in self.responseDelegates.allObjects {
                listener.onMessageStatusDidChanged(message: aMessage, status: .read, error: nil)
            }
        }
    }
    
    public func onMessageContentChanged(_ message: ChatMessage, operatorId: String, operationTime: UInt) {
        for listener in self.responseDelegates.allObjects {
            listener.onMessageDidEdited(message: message)
        }
    }
    
    
    
}


/// Keeps the recaller and original sender separate, including offline SDK callbacks.
struct MessageRecallNotice {
    let conversationId: String
    let messageId: String
    let operatorId: String
    let senderId: String
    let operatorNickname: String
    let senderNickname: String
    let groupId: String
    let isGroup: Bool
    let isThread: Bool
    let timestamp: Int64

    init(message: ChatMessage, operatorId: String, parentGroupId: String = "") {
        self.conversationId = message.conversationId
        self.messageId = message.messageId
        self.operatorId = operatorId
        self.senderId = message.ext?["recallSenderId"] as? String ?? message.from
        self.operatorNickname = Self.nickname(userId: operatorId)
        self.senderNickname = Self.nickname(userId: self.senderId, fallback: message.senderInfo?.nickname ?? "")
        self.isGroup = message.chatType == .groupChat
        self.isThread = message.isChatThreadMessage
        self.groupId = parentGroupId.isEmpty ? message.conversationId : parentGroupId
        self.timestamp = message.timestamp
    }

    init(info: RecallInfo, parentGroupId: String = "") {
        let data = info.ext?.data(using: .utf8)
        let metadata = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let original = info.recallMessage
        self.conversationId = original?.conversationId ?? info.conversationId
        self.messageId = info.recallMessageId
        self.operatorId = info.recallBy
        self.senderId = original?.ext?["recallSenderId"] as? String ?? original?.from ?? metadata["recallSenderId"] as? String ?? ""
        self.operatorNickname = Self.nickname(userId: self.operatorId, fallback: metadata["recallOperatorNickname"] as? String ?? "")
        self.senderNickname = Self.nickname(userId: self.senderId, fallback: original?.senderInfo?.nickname ?? metadata["recallSenderNickname"] as? String ?? "")
        let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(self.conversationId)
        self.isGroup = original.map { $0.chatType == .groupChat } ?? conversation.map { $0.type == .groupChat } ?? (metadata["recallGroupId"] != nil)
        self.isThread = !parentGroupId.isEmpty || (original?.isChatThreadMessage ?? conversation?.isChatThread ?? (metadata["recallIsThread"] as? Bool ?? false))
        let savedGroupId = metadata["recallGroupId"] as? String ?? self.conversationId
        self.groupId = parentGroupId.isEmpty ? (self.isThread ? savedGroupId : self.conversationId) : parentGroupId
        self.timestamp = original?.timestamp ?? metadata["recallTimestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
    }

    var isModeratorRecall: Bool {
        self.isGroup && (self.senderId.isEmpty || self.senderId.caseInsensitiveCompare(self.operatorId) != .orderedSame)
    }

    var isVisible: Bool {
        guard self.isModeratorRecall else { return true }
        let group = ChatGroup(id: self.groupId)
        return group?.permissionType == .owner || group?.permissionType == .admin
    }

    var payload: String? {
        guard self.isGroup else { return nil }
        let metadata: [String: Any] = ["recallSenderId": self.senderId, "recallSenderNickname": self.senderNickname,
                                       "recallOperatorNickname": self.operatorNickname, "recallGroupId": self.groupId,
                                       "recallIsThread": self.isThread, "recallTimestamp": self.timestamp]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func makeMessage() -> ChatMessage {
        var metadata: [String: Any] = ["something": "recalled a message".chat.localize]
        if self.isModeratorRecall {
            metadata["recallOperatorId"] = self.operatorId
            metadata["recallSenderId"] = self.senderId
            metadata["recallOperatorNickname"] = self.operatorNickname
            metadata["recallSenderNickname"] = self.senderNickname
            metadata["recallGroupId"] = self.groupId
        }
        let message = ChatMessage(conversationID: self.conversationId, from: self.operatorId, to: self.conversationId,
                                  body: ChatCustomMessageBody(event: EaseChatUIKit_alert_message, customExt: nil), ext: metadata)
        message.messageId = self.messageId
        message.chatType = self.isGroup ? .groupChat : .chat
        message.isChatThreadMessage = self.isThread
        message.direction = .receive
        message.status = .succeed
        message.timestamp = self.timestamp
        message.localTime = Int64(Date().timeIntervalSince1970 * 1000)
        if let text = message.groupRecallNoticeText {
            message.ext?["something"] = text
        }
        return message
    }

    func store(_ message: ChatMessage) {
        guard let manager = ChatClient.shared().chatManager else { return }
        if manager.getMessageWithMessageId(self.messageId) != nil {
            manager.update(message)
        } else {
            manager.getConversation(self.conversationId, type: self.isGroup ? .groupChat : .chat,
                                    createIfNotExist: true, isThread: self.isThread)?.insert(message, error: nil)
        }
    }

    static func nickname(userId: String, fallback: String = "", groupId: String = "") -> String {
        if let alias = GroupMemberAttributesCache.shared.nickname(groupId: groupId, userId: userId), !alias.isEmpty { return alias }
        let names = [ChatUIKitContext.shared?.userCache?[userId]?.nickname,
                     ChatUIKitContext.shared?.chatCache?[userId]?.nickname,
                     ChatUIKitContext.shared?.currentUserId == userId ? ChatUIKitContext.shared?.currentUser?.nickname : nil,
                     fallback]
        return names.compactMap { $0 }.first(where: { !$0.isEmpty }) ?? (userId.isEmpty ? "group_recall_unknown_member".chat.localize : userId)
    }
}

extension ChatMessage {
    public var groupRecallNoticeText: String? {
        guard let body = self.body as? ChatCustomMessageBody, body.event == EaseChatUIKit_alert_message,
              let operatorId = self.ext?["recallOperatorId"] as? String,
              let senderId = self.ext?["recallSenderId"] as? String else { return nil }
        let operatorName = MessageRecallNotice.nickname(userId: operatorId, fallback: self.ext?["recallOperatorNickname"] as? String ?? "", groupId: self.ext?["recallGroupId"] as? String ?? self.conversationId)
        let contextUserId = ChatUIKitContext.shared?.currentUserId ?? ""
        let currentUserId = contextUserId.isEmpty ? (ChatClient.shared().currentUsername ?? "") : contextUserId
        if !currentUserId.isEmpty, senderId.caseInsensitiveCompare(currentUserId) == .orderedSame {
            return String(format: "group_moderator_recall_self_notice".chat.localize, operatorName)
        }
        let senderName = MessageRecallNotice.nickname(userId: senderId, fallback: self.ext?["recallSenderNickname"] as? String ?? "", groupId: self.ext?["recallGroupId"] as? String ?? self.conversationId)
        return String(format: "group_moderator_recall_notice".chat.localize, operatorName, senderName)
    }

    public var localSystemNoticeText: String? {
        self.groupAdminNoticeText ?? self.groupRecallNoticeText
    }

    public var hidesModeratorRecallNotice: Bool {
        guard self.ext?["recallOperatorId"] != nil,
              let groupId = self.ext?["recallGroupId"] as? String else { return false }
        let group = ChatGroup(id: groupId)
        return group?.permissionType != .owner && group?.permissionType != .admin
    }
}
