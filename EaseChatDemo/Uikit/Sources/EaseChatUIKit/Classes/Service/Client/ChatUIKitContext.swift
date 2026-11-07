//
//  ChatUIKitContext.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/6.
//

import UIKit

@objcMembers public class ChatUIKitContext: NSObject {
    
    @objc public static let shared: ChatUIKitContext? = ChatUIKitContext()

    private let syncRefresh = DataSyncUIRefresh()

    public var currentUserId: String {
        ChatClient.shared().currentUsername ?? ""
    }

    public var pinnedCache: Dictionary<String, Bool>? = [:]
    public var userProfileProvider: ChatUserProfileProvider?
    
    public var userProfileProviderOC: ChatUserProfileProviderOC?
    
    public var groupProfileProvider: ChatGroupProfileProvider?
    
    public var groupProfileProviderOC: ChatGroupProfileProviderOC?
    public var onGroupNameUpdated: ((String, String) -> Void)?

    /// Read the SDK's local user data. Contact remarks remain owned by contactManager.
    public func userProfile(id: String) -> ChatUserProfileProtocol? {
        guard !id.isEmpty else { return nil }
        let info = ChatClient.shared().userInfoManager?.getUserInfo(byIds: [id])?[id]
        let contact = ChatClient.shared().contactManager?.getContact(id)
        guard info != nil || contact != nil else { return nil }
        let profile = ChatUserProfile()
        profile.id = id
        profile.nickname = info?.nickname ?? ""
        profile.avatarURL = info?.avatarUrl ?? ""
        profile.remark = contact?.remark ?? ""
        return profile
    }

    public func groupProfile(id: String) -> ChatUserProfileProtocol? {
        guard let group = ChatClient.shared().groupManager?.getJoinedGroups()?.first(where: { $0.groupId == id }) else { return nil }
        return self.groupProfile(group: group)
    }

    public func groupProfile(group: ChatGroup) -> ChatUserProfileProtocol {
        let profile = ChatUserProfile()
        profile.id = group.groupId
        profile.nickname = group.groupName ?? ""
        let avatar = group.groupAvatar ?? ""
        profile.avatarURL = avatar.isEmpty ? (group.settings?.ext ?? "") : avatar
        return profile
    }

    /// Conversation metadata takes priority independently for name and avatar.
    public func conversationProfile(conversation: ChatConversation) -> ChatUserProfileProtocol {
        let fallback = conversation.type == .chat
            ? self.userProfile(id: conversation.conversationId)
            : self.groupProfile(id: conversation.conversationId)
        let profile = ChatUserProfile()
        profile.id = conversation.conversationId
        let name = conversation.conversationName() ?? ""
        let avatar = conversation.conversationAvatar() ?? ""
        profile.nickname = name.isEmpty ? (fallback?.nickname ?? "") : name
        profile.avatarURL = avatar.isEmpty ? (fallback?.avatarURL ?? "") : avatar
        profile.remark = fallback?.remark ?? ""
        return profile
    }

    /// Merge SDK sync completions into one trailing refresh after one second of quiet.
    public func scheduleDataSyncRefresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleDataSyncRefresh() }
            return
        }
        let account = self.currentUserId
        self.syncRefresh.schedule { [weak self] in
            guard let self = self, account == self.currentUserId else { return }
            self.notifyProfilesChanged()
        }
    }

    public func cancelDataSyncRefresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.cancelDataSyncRefresh() }
            return
        }
        self.syncRefresh.cancel()
    }

    /// Notify pages after SDK data changes. UI observers always run on the main queue.
    public func notifyProfilesChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Notification.Name(profile_update_notification), object: nil)
        } else {
            DispatchQueue.main.async { [weak self] in self?.notifyProfilesChanged() }
        }
    }
}

/// Confined to the main queue, like the SDK data-sync delegate and UI notifications.
final class DataSyncUIRefresh {
    private var pending: DispatchWorkItem?
    private var generation = 0
    private let interval: TimeInterval

    init(interval: TimeInterval = 1) {
        self.interval = interval
    }

    func schedule(_ refresh: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.cancel()
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, generation == self.generation else { return }
            self.pending = nil
            refresh()
        }
        self.pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + self.interval, execute: work)
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        self.generation += 1
        self.pending?.cancel()
        self.pending = nil
    }

    deinit {
        self.pending?.cancel()
    }
}
