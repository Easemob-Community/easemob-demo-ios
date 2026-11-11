//
//  ConversationServiceImplement.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/6.
//

import UIKit



@objc public class ConversationServiceImplement: NSObject {
    private static let localConversationDidChange = Notification.Name("EaseChatUIKit_Conversation_last_message_need_update")

    static func notifyLocalChange(account: String = saveIdentifier) {
        let post = {
            guard account == saveIdentifier else { return }
            NotificationCenter.default.post(name: Self.localConversationDidChange, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
    
    private var responseDelegates: NSHashTable<ConversationServiceListener> = NSHashTable<ConversationServiceListener>.weakObjects()
    private var scheduledRefreshAccount: String?

    private let groupService: GroupService = ChatUIKitClient.shared.groupService
    
    public private(set) var eventsNotifiers: NSHashTable<ConversationEmergencyListener> = NSHashTable<ConversationEmergencyListener>.weakObjects()
    
    public override init() {
        super.init()
        ChatClient.shared().chatManager?.add(self, delegateQueue: .main)
        ChatClient.shared().chatManager?.addConversation(delegate: self, queue: .main)
        for name in [Self.localConversationDidChange, Notification.Name("EaseChatUIKit_clean_history_messages")] {
            NotificationCenter.default.addObserver(self, selector: #selector(receiveLocalNotify), name: name, object: nil)
        }
        self.groupService.bindGroupEventsListener(listener: self)
    }
    
    deinit {
        self.groupService.unbindGroupEventsListener(listener: self)
        ChatClient.shared().chatManager?.remove(self)
        ChatClient.shared().chatManager?.removeConversation(delegate: self)
        NotificationCenter.default.removeObserver(self)
    }

}

extension ConversationServiceImplement: GroupServiceListener {
    public func onGroupAdminNoticeUpdated(message: ChatMessage) {
        self.notifyHandler(message: message, local: true)
    }
}

extension ConversationServiceImplement: ConversationService {
    public func loadIfNotExistCreate(conversationId: String,type: ChatConversationType) -> ChatConversation? {
        if let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(conversationId) {
            return conversation
        }
        return ChatClient.shared().chatManager?.getConversation(conversationId, type: type, createIfNotExist: true)
    }
    
    
    
    public func loadExistConversations() {
        guard let conversations = ChatClient.shared().chatManager?.getAllConversations(true) else { return }
        let list = self.mapper(objects: conversations)
        for listener in self.responseDelegates.allObjects {
            listener.onChatConversationListDidChanged(list: list)
        }
    }

    func scheduleListRefresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleListRefresh() }
            return
        }
        let account = saveIdentifier
        guard self.scheduledRefreshAccount != account else { return }
        self.scheduledRefreshAccount = account
        DispatchQueue.main.async { [weak self] in
            guard let self, self.scheduledRefreshAccount == account else { return }
            self.scheduledRefreshAccount = nil
            guard account == saveIdentifier else { return }
            self.loadExistConversations()
        }
    }
    
    public func setSilentMode(conversationId: String, completion: @escaping (SilentModeResult?, ChatError?) -> Void) {
        if let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(conversationId) {
            let params = SilentModeParam(paramType: .remindType)
            params.remindType = (conversation.type == .chat ? .none:.mentionOnly)
            ChatClient.shared().pushManager?.setSilentModeForConversation(conversationId, conversationType: conversation.type, params: params,completion: { [weak self] result, error in
                self?.handleResult(error: error, type: .setSilent)
                completion(result,error)
            })
        }
    }
    
    public func clearSilentMode(conversationId: String, completion: @escaping (SilentModeResult?, ChatError?) -> Void) {
        if let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(conversationId) {
            let params = SilentModeParam(paramType: .remindType)
            params.remindType = .all
            ChatClient.shared().pushManager?.setSilentModeForConversation(conversationId, conversationType: conversation.type, params: params,completion: { [weak self] result, error in
                self?.handleResult(error: error, type: .setSilent)
                completion(result,error)
            })
        }
    }
    
    public func pin(conversationId: String, completion: @escaping (ChatError?) -> Void) {
        ChatClient.shared().chatManager?.pinConversation(conversationId, isPinned: true, completionBlock: { [weak self] error in
            self?.handleResult(error: error, type: .pin)
            completion(error)
        })
    }
    
    public func unpin(conversationId: String, completion: @escaping (ChatError?) -> Void) {
        ChatClient.shared().chatManager?.pinConversation(conversationId, isPinned: false, completionBlock: { [weak self] error in
            self?.handleResult(error: error, type: .unpin)
            completion(error)
        })
    }
    
    public func deleteConversation(conversationId: String, completion: @escaping (ChatError?) -> Void) {
        if let _ = ChatClient.shared().chatManager?.getConversationWithConvId(conversationId) {
            ChatClient.shared().chatManager?.deleteConversation(conversationId, isDeleteMessages: true, completion: { [weak self] localId, error in
                ChatUIKitContext.shared?.pinnedCache?.removeValue(forKey: conversationId)
                self?.handleResult(error: error, type: .delete)
                completion(error)
            })
        }
        
    }
    
    public func markAllMessagesAsRead(conversationId: String) {
        ChatClient.shared().chatManager?.clearConversationUnreadMessageCount(conversationId) { error in
            self.handleResult(error: error, type: .read)
        }
    }
    
    public func bindConversationEventsListener(listener: ConversationServiceListener) {
        if self.responseDelegates.contains(listener) {
            return
        }
        self.responseDelegates.add(listener)
    }
    
    @objc private func receiveLocalNotify() {
        self.scheduleListRefresh()
    }
    
    public func unbindConversationEventsListener(listener: ConversationServiceListener) {
        if self.responseDelegates.contains(listener) {
            self.responseDelegates.remove(listener)
        }
    }
    
    
    public func registerEmergencyListener(listener: ConversationEmergencyListener) {
        if self.eventsNotifiers.contains(listener) {
            return
        }
        self.eventsNotifiers.add(listener)
    }
    
    public func unregisterEmergencyListener(listener: ConversationEmergencyListener) {
        if self.eventsNotifiers.contains(listener) {
            self.eventsNotifiers.remove(listener)
        }
    }
    
    public func handleResult(error: ChatError?,type: ConversationEmergencyType) {
        for listener in self.eventsNotifiers.allObjects {
            listener.onResult(error: error, type: type)
        }
    }
    
    public func notifyUnreadCount(count: UInt) {
        for listener in self.eventsNotifiers.allObjects {
            listener.onConversationsUnreadCountUpdate(unreadCount: count)
        }
    }
    
    public func mapper(objects: [ChatConversation]) -> [ConversationInfo] {
        objects.map {
            let conversation = ComponentsRegister.shared.Conversation.init()
            let profile = ChatUIKitContext.shared?.conversationProfile(conversation: $0)
            conversation.id = $0.conversationId
            conversation.nickname = profile?.nickname ?? ""
            conversation.remark = profile?.remark ?? ""
            conversation.avatarURL = profile?.avatarURL ?? ""
            conversation.unreadCount = UInt($0.unreadMessagesCount)
            conversation.lastMessage = $0.latestMessage
            conversation.type = ChatUserProfileProviderType(rawValue: UInt($0.type.rawValue)) ?? .chat
            conversation.pinned = $0.isPinned
            conversation.doNotDisturb = $0.disturbType != .all
            
            _ = conversation.showContent
            return conversation
        }
    }
}


extension ConversationServiceImplement: ChatEventsListener {
    
    public func messagesDidReceive(_ aMessages: [ChatMessage]) {
        for message in aMessages {
            self.notifyHandler(message: message, local: false)
        }
    }
    
    public func messagesInfoDidRecall(_ aRecallMessagesInfo: [RecallInfo]) {
        for info in aRecallMessagesInfo {
            let notice = MessageRecallNotice(info: info)
            if notice.isVisible {
                let message = notice.makeMessage()
                notice.store(message)
                if !notice.isThread {
                    self.notifyHandler(message: message, local: true)
                }
            } else {
                ChatClient.shared().chatManager?.getConversationWithConvId(notice.conversationId)?.deleteMessage(withId: notice.messageId, error: nil)
            }
        }
        self.scheduleListRefresh()
    }
    
    public func onMessageContentChanged(_ message: ChatMessage, operatorId: String, operationTime: UInt) {
        self.notifyHandler(message: message, local: false)
    }
    
    private func notifyHandler(message: ChatMessage,local: Bool) {
        guard let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(message.conversationId) else {
            return
        }
        if conversation.ext == nil {
            conversation.ext = [:]
        }
        if !message.mention.isEmpty {
            conversation.ext?["EaseChatUIKit_mention"] = true
        }
        let list = self.mapper(objects: [conversation])
        for listener in self.responseDelegates.allObjects {
            if let info = list.first {
                listener.onConversationLastMessageUpdate(message: message, info: info)
            }
        }
        DispatchQueue.main.asyncAfter(wallDeadline: .now()+0.5) {
            for handler in self.eventsNotifiers.allObjects {
                if let info = list.first {
                    handler.onConversationLastMessageUpdate(message: message, info: info)
                }
            }
        }
    }
    
    public func onConversationRead(_ from: String, to: String) {
        if from == ChatUIKitContext.shared?.currentUserId ?? "" {
            if let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(to) {
                self.onConversationReadCallback(conversation: conversation)
            } else {
                if let conversation = ChatClient.shared().chatManager?.getConversationWithConvId(from) {
                    self.onConversationReadCallback(conversation: conversation)
                }
            }
        }
        
    }
    
    @objc open func onConversationReadCallback(conversation: ChatConversation ) {
//        conversation.markAllMessages(asRead: nil)
        if let info = self.mapper(objects: [conversation]).first{
            info.unreadCount = 0
            for listener in self.responseDelegates.allObjects {
                listener.onConversationMessageAlreadyReadOnOtherDevice(info: info)
            }
            
            for handler in self.eventsNotifiers.allObjects {
                handler.onResult(error: nil, type: .read)
            }
        }
    }

}

extension ConversationServiceImplement: ChatConversationDelegate {
    @objc public func conversationListDidUpdate(_ aConversationList: [ChatConversation]) {
        self.scheduleListRefresh()
    }
}

