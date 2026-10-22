//
//  GroupMemberAttributesCache.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/12/19.
//

import UIKit

@objc public final class GroupMemberAttributesCache: NSObject {

    public static let shared = GroupMemberAttributesCache()
    public static let nicknameKey = "nickName"
    private let lock = NSRecursiveLock()
    private var account = ""
    private var pending = Set<String>()
    private var waiters: [String: [(Bool) -> Void]] = [:]
    private var parentGroups: [String: String] = [:]

    private func ensureAccount() {
        let current = saveIdentifier
        if self.account != current {
            self.attributes.removeAll()
            self.profiles.removeAll()
            self.pending.removeAll()
            self.waiters.removeAll()
            self.parentGroups.removeAll()
            self.account = current
        }
    }

    public func nickname(groupId: String, userId: String) -> String? {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        return self.attributes[groupId]?[userId]?[Self.nicknameKey]
    }

    public func registerThread(conversationId: String, groupId: String) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        self.parentGroups[conversationId] = groupId
    }

    public func groupId(conversationId: String) -> String {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        return self.parentGroups[conversationId] ?? conversationId
    }

    /// Return a group-scoped copy; global nicknames and contact remarks must stay unchanged.
    public func displayProfile(groupId: String, profile: ChatUserProfileProtocol) -> ChatUserProfileProtocol {
        guard let name = self.nickname(groupId: groupId, userId: profile.id), !name.isEmpty else { return profile }
        let copy = ChatUserProfile()
        copy.id = profile.id
        copy.avatarURL = profile.avatarURL
        copy.nickname = name
        copy.remark = ""
        return copy
    }

    /// Fetch only unknown names, in SDK-sized batches. Completion always runs on the main queue.
    public func fetchNicknames(groupId: String, userIds: [String], service: GroupService, completion: @escaping (Bool) -> Void) {
        self.lock.lock()
        self.ensureAccount()
        let account = self.account
        let ids = Set(userIds).filter { !$0.isEmpty && self.attributes[groupId]?[$0]?[Self.nicknameKey] == nil && !self.pending.contains(groupId + "\u{0}" + $0) }.sorted()
        if ids.isEmpty {
            let waiting = userIds.contains { self.pending.contains(groupId + "\u{0}" + $0) }
            if waiting { self.waiters[groupId, default: []].append(completion) }
            self.lock.unlock()
            if !waiting { DispatchQueue.main.async { completion(false) } }
            return
        }
        ids.forEach { self.pending.insert(groupId + "\u{0}" + $0) }
        self.lock.unlock()
        let batches = stride(from: 0, to: ids.count, by: 100).map { Array(ids[$0..<min($0 + 100, ids.count)]) }
        func fetch(_ index: Int, changed: Bool) {
            guard account == saveIdentifier else { return }
            guard index < batches.count else {
                self.lock.lock()
                let done = !self.pending.contains { $0.hasPrefix(groupId + "\u{0}") }
                let callbacks = done ? (self.waiters.removeValue(forKey: groupId) ?? []) : []
                self.lock.unlock()
                completion(changed)
                callbacks.forEach { $0(changed) }
                return
            }
            let batch = batches[index]
            service.fetchMembersAttribute(groupId: groupId, userIds: batch, keys: [Self.nicknameKey]) { error, attributes in
                DispatchQueue.main.async {
                    guard account == saveIdentifier else { return }
                    self.lock.lock()
                    batch.forEach { self.pending.remove(groupId + "\u{0}" + $0) }
                    if error == nil {
                        for id in batch {
                            // A callback received during the request has the newer value.
                            if self.nickname(groupId: groupId, userId: id) == nil {
                                self.cache(groupId: groupId, userId: id, key: Self.nicknameKey, value: attributes?[id]?[Self.nicknameKey] ?? "")
                            }
                        }
                    }
                    self.lock.unlock()
                    fetch(index + 1, changed: changed || error == nil)
                }
            }
        }
        DispatchQueue.main.async { fetch(0, changed: false) }
    }

    @objc public private(set) var attributes: Dictionary<String,Dictionary<String,Dictionary<String,String>>> = [:]
    
    @objc public var profiles: Dictionary<String,Dictionary<String,ChatUserProfileProtocol>> = [:]
    
    /// Cache a group member attribute for key.
    /// - Parameters:
    ///   - groupId: ID of the group.
    ///   - userId: ID of the user
    ///   - key: Attribute key
    ///   - value:  Attribute value
    @objc(cacheWithGroupId:userId:key:value:)
    public func cache(groupId: String, userId: String, key: String, value: String) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        var usesAttributes = self.attributes[groupId] ?? [:]
        var attributes = usesAttributes[userId] ?? [:]
        attributes[key] = value
        usesAttributes[userId] = attributes
        self.attributes[groupId] = usesAttributes
    }
    
    /// Cache a conform ``ChatUserProfileProtocol`` object.
    /// - Parameters:
    ///   - groupId: ID of the group.
    ///   - profile: ``ChatUserProfileProtocol``
    @objc public func cacheProfile(groupId: String,profile: ChatUserProfileProtocol) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        var profiles = self.profiles[groupId] ?? [:]
        profiles[profile.id] = profile
        self.profiles[groupId] = profiles
    }
    
    /// Remove a cache of the group member attribute.
    /// - Parameters:
    ///   - groupId: ID of the group.
    ///   - userId: ID of the user.
    @objc public func removeCache(groupId: String,userId: String = "") {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        if userId.isEmpty {
            self.attributes.removeValue(forKey: groupId)
        } else {
            self.attributes[groupId]?.removeValue(forKey: userId)
        }
    }
    
    /// Remove  a conform ``ChatUserProfileProtocol`` cache object..
    /// - Parameters:
    ///   - groupId: ID of the group.
    ///   - profile: ``ChatUserProfileProtocol``
    @objc(removeProfileCacheWithGroupId:profile:)
    public func removeCacheProfile(groupId: String,profile: ChatUserProfileProtocol) {
        self.profiles[groupId]?.removeValue(forKey: profile.id)
    }
    
    /// Fetch attributes of the group member.
    /// - Parameters:
    ///   - groupId: ID of the group.
    ///   - userIds: Array of the user's id.
    ///   - key: Attribute key
    ///   - completion: callback,result contain error&attribute value.
    @objc(fetchCacheValueWithGroupId:userIds:key:completion:)
    public func fetchCacheValue(groupId: String, userIds: [String], key: String, completion: @escaping (ChatError?,[String]?) -> Void) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.ensureAccount()
        var values = [String]()
        for id in userIds {
            if let value = self.attributes[groupId]?[id]?[key] {
                values.append(value)
            }
        }
        completion(nil, values)
    }
    
}
