//
//  ContactServiceImplement.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/1.
//

import UIKit

@objc public class ContactServiceImplement: NSObject {
        
    private var responseDelegates: NSHashTable<ContactEventsResponse> = NSHashTable<ContactEventsResponse>.weakObjects()
    
    private var eventsNotifiers: NSHashTable<ContactEmergencyListener> = NSHashTable<ContactEmergencyListener>.weakObjects()
    
    @objc public override init() {
        super.init()
        ChatClient.shared().contactManager?.add(self, delegateQueue: .main)
    }
    
    deinit {
        ChatClient.shared().contactManager?.removeDelegate(self)
    }
}

extension ContactServiceImplement: ContactServiceProtocol {
    
    public func registerEmergencyListener(listener: ContactEmergencyListener) {
        if self.eventsNotifiers.contains(listener) {
            return
        }
        self.eventsNotifiers.add(listener)
    }
    
    public func unregisterEmergencyListener(listener: ContactEmergencyListener) {
        if self.eventsNotifiers.contains(listener) {
            self.eventsNotifiers.remove(listener)
        }
    }
        
    public func bindContactEventListener(listener: ContactEventsResponse) {
        if self.responseDelegates.contains(listener) {
            return
        }
        self.responseDelegates.add(listener)
    }
    
    public func unbindContactEventListener(listener: ContactEventsResponse) {
        if self.responseDelegates.contains(listener) {
            self.responseDelegates.remove(listener)
        }
    }
    
    public func addContact(userId: String, invitation: String, completion: @escaping (ChatError?, String) -> Void) {
        ChatClient.shared().contactManager?.addContact(userId, message: invitation, completion: { [weak self] useId, error in
            guard let `self` = self else { return }
            completion(error,userId)
            self.handleResult(error: error, type: .add, operatorId: ChatUIKitContext.shared?.currentUserId ?? "")
        })
    }
    
    public func removeContact(userId: String, removeChannel: Bool = false, completion: @escaping (ChatError?, String) -> Void) {
        let account = saveIdentifier
        ChatClient.shared().contactManager?.deleteContact(userId, isDeleteConversation: removeChannel, completion: { [weak self] userId, error in
            if error == nil, !removeChannel {
                ConversationServiceImplement.notifyLocalChange(account: account)
            }
            completion(error,userId ?? "")
            self?.handleResult(error: error, type: .remove, operatorId: ChatUIKitContext.shared?.currentUserId ?? "")
        })
    }
    
    public func agreeFriendRequest(from userId: String, completion: @escaping (ChatError?, String) -> Void) {
        let store = FriendRequestStore()
        ChatClient.shared().contactManager?.approveFriendRequest(fromUser: userId, completion: { [weak self] _, error in
            DispatchQueue.main.async {
                if error == nil, store.ownerIdentifier == saveIdentifier {
                    store.updateStatus(.accepted, userId: userId)
                    Self.openFriendConversation(userId: userId)
                }
                completion(error,userId)
                self?.handleResult(error: error, type: .agree, operatorId: ChatUIKitContext.shared?.currentUserId ?? "")
            }
        })
    }
    
    public func declineFriendRequest(from userId: String, completion: @escaping (ChatError?, String) -> Void) {
        let store = FriendRequestStore()
        ChatClient.shared().contactManager?.declineFriendRequest(fromUser: userId, completion: { [weak self] _, error in
            if error == nil {
                store.updateStatus(.declined, userId: userId)
            }
            completion(error,userId)
            self?.handleResult(error: error, type: .decline, operatorId: ChatUIKitContext.shared?.currentUserId ?? "")
        })
    }
    
    public func userBlackList(completion: @escaping (ChatError?, [String]) -> Void) {
        ChatClient.shared().contactManager?.getBlackListFromServer(completion: { userIds, error in
            completion(error,userIds ?? [])
        })
    }
    
    public func addUserToBlackList(userId: String, completion: @escaping (ChatError?, String) -> Void) {
        ChatClient.shared().contactManager?.addUser(toBlackList: userId, completion: { userId, error in
            completion(error,userId ?? "")
        })
    }
    
    public func removeUserFromBlackList(userId: String, completion: @escaping (ChatError?, String) -> Void) {
        ChatClient.shared().contactManager?.removeUser(fromBlackList: userId, completion: { userId, error in
            completion(error,userId ?? "")
        })
    }
    
    public func deviceIdsOnOtherPlatformOfCurrentUser(completion: @escaping (ChatError?, [String]) -> Void) {
        ChatClient.shared().contactManager?.getSelfIdsOnOtherPlatform(completion: { deviceIds, error in
            completion(error,deviceIds ?? [])
        })
    }
    
    public func setRemark(userId: String, remark: String, completion: @escaping (ChatError?, Contact?) -> Void) {
        ChatClient.shared().contactManager?.setContactRemark(userId,remark: remark,completion: { [weak self] contact, error in
            completion(error,contact)
            self?.handleResult(error: error, type: .setRemark, operatorId: ChatUIKitContext.shared?.currentUserId ?? "")
        })
    }
}

extension ContactServiceImplement: ContactEventsListener {
    
    public func friendshipDidAdd(byUser aUsername: String) {
        FriendRequestStore().updateStatus(.accepted, userId: aUsername)
        for listener in self.responseDelegates.allObjects {
            listener.friendshipDidAddSuccessful(by: aUsername)
        }
        self.handleResult(error: nil, type: .add, operatorId: aUsername)
    }
    
    public func friendshipDidRemove(byUser aUsername: String) {
        for listener in self.responseDelegates.allObjects {
            listener.friendshipDidRemove(by: aUsername)
        }
        if ChatClient.shared().chatManager?.getConversationWithConvId(aUsername) != nil {
            ConversationServiceImplement.notifyLocalChange()
        }
        self.handleResult(error: nil, type: .remove, operatorId: aUsername)
    }
    
    public func friendRequestDidApprove(byUser aUsername: String) {
        Self.openFriendConversation(userId: aUsername)
        for listener in self.responseDelegates.allObjects {
            listener.friendRequestDidAgree(by: aUsername)
        }
        self.handleResult(error: nil, type: .agree, operatorId: aUsername)
    }

    static let newFriendChat = Notification.Name("New Friend Chat")

    static func openFriendConversation(userId: String, onlyIfEmpty: Bool = false) {
        guard !userId.isEmpty,
              let conversation = ChatClient.shared().chatManager?.getConversation(userId, type: .chat, createIfNotExist: true) else { return }
        if onlyIfEmpty, conversation.latestMessage != nil { return }
        let text = "You have added".chat.localize + " " + userId + " " + "to say hello".chat.localize
        let message = ChatMessage(conversationID: userId, body: ChatCustomMessageBody(event: EaseChatUIKit_alert_message, customExt: nil), ext: ["something": text])
        message.status = .succeed
        var error: ChatError?
        conversation.insert(message, error: &error)
        if let error {
            consoleLogInfo("Insert friend welcome message failed: \(error.errorDescription ?? "")", type: .error)
        }
        NotificationCenter.default.post(name: Self.newFriendChat, object: error == nil ? message : nil)
    }
    
    public func friendRequestDidDecline(byUser aUsername: String) {
        for listener in self.responseDelegates.allObjects {
            listener.friendRequestDidDecline(by: aUsername)
        }
        self.handleResult(error: nil, type: .decline, operatorId: aUsername)
    }
    
    public func friendRequestDidReceive(fromUser aUsername: String, message aMessage: String?) {
        self.saveFriendRequest(from: aUsername)
        for listener in self.responseDelegates.allObjects {
            listener.friendRequestDidReceive(by: aUsername)
        }
        DispatchQueue.main.asyncAfter(wallDeadline: .now()+0.3) {
            self.handleResult(error: nil, type: .add, operatorId: aUsername)
        }
    }
    
    public func onFriendInfoChanged(_ contact: Contact) {
        ChatUIKitContext.shared?.notifyProfilesChanged()
        self.handleResult(error: nil, type: .fetchContacts, operatorId: contact.userId)
    }
    
    private func saveFriendRequest(from userId: String) {
        let store = FriendRequestStore()
        store.receive(userId: userId)
        if let index = Appearance.contact.listHeaderExtensionActions.firstIndex(where: { $0.featureIdentify == "NewFriendRequest" }) {
            let item = Appearance.contact.listHeaderExtensionActions[index]
            item.showBadge = true
            let unreadCount = store.requests.filter({ $0["read"] as? Int == 0 }).count
            item.numberCount = UInt(unreadCount)
            Appearance.contact.listHeaderExtensionActions[index].numberCount = UInt(unreadCount)
        }
    }
    
    func handleResult(error: ChatError?,type: ContactEmergencyType,operatorId: String) {
        for listener in self.eventsNotifiers.allObjects {
            listener.onResult(error: error, type: type, operatorId: operatorId)
        }
    }
    
}

@objc public enum NewContactRequestStatus: Int {
    case pending = 0
    case accepted = 1
    case declined = 2
}

/// Keeps request history in the existing, app-key and account scoped storage.
/// Missing status values belong to pending requests saved by older versions.
struct FriendRequestStore {
    static let didChange = Notification.Name("EaseChatUIKit_friend_request_did_change")
    private static let storageKey = "EaseChatUIKit_contact_new_request"
    private static let lock = NSLock()

    let ownerIdentifier: String
    private let defaults: UserDefaults

    init(ownerIdentifier: String = saveIdentifier, defaults: UserDefaults = .standard) {
        self.ownerIdentifier = ownerIdentifier
        self.defaults = defaults
    }

    var requests: [[String: Any]] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return self.allRequests[self.ownerIdentifier] ?? []
    }

    private var allRequests: [String: [[String: Any]]] {
        self.defaults.object(forKey: Self.storageKey) as? [String: [[String: Any]]] ?? [:]
    }

    static func status(of request: [String: Any]) -> NewContactRequestStatus {
        NewContactRequestStatus(rawValue: request["status"] as? Int ?? 0) ?? .pending
    }

    func receive(userId: String) {
        guard !userId.isEmpty else { return }
        self.mutate { requests in
            // SDK and view-model callbacks can both deliver the same request.
            guard !requests.contains(where: {
                $0["userId"] as? String == userId && Self.status(of: $0) == .pending
            }) else { return false }
            requests.append(["userId": userId, "timestamp": Date().timeIntervalSince1970 * 1000,
                             "groupApply": 0, "read": 0, "status": NewContactRequestStatus.pending.rawValue])
            return true
        }
    }

    func updateStatus(_ status: NewContactRequestStatus, userId: String) {
        guard status != .pending else { return }
        self.mutate { requests in
            var changed = false
            for index in requests.indices where requests[index]["userId"] as? String == userId
                && Self.status(of: requests[index]) == .pending {
                requests[index]["status"] = status.rawValue
                requests[index]["read"] = 1
                changed = true
            }
            return changed
        }
    }

    func markAllRead() {
        self.mutate { requests in
            var changed = false
            for index in requests.indices where requests[index]["read"] as? Int != 1 {
                requests[index]["read"] = 1
                changed = true
            }
            return changed
        }
    }

    private func mutate(_ change: (inout [[String: Any]]) -> Bool) {
        Self.lock.lock()
        var all = self.allRequests
        var requests = all[self.ownerIdentifier] ?? []
        let changed = change(&requests)
        if changed {
            all[self.ownerIdentifier] = requests
            self.defaults.set(all, forKey: Self.storageKey)
        }
        Self.lock.unlock()
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChange, object: self.ownerIdentifier)
            }
        }
    }
}

