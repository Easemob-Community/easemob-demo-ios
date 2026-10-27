import UIKit

struct GroupReceiptPerson {
    var id: String
    var name: String
    var avatarURL: String
    var joinedTimestamp: Int64 = 0
}

struct GroupReceiptPage {
    var people: [GroupReceiptPerson]
    var cursor: String
    var total: Int = 0
}

protocol GroupReceiptProviding {
    func refreshGroup(groupId: String, completion: @escaping () -> Void)
    func readers(message: ChatMessage, cursor: String, completion: @escaping (Result<GroupReceiptPage, Error>) -> Void)
    func members(groupId: String, cursor: String, completion: @escaping (Result<GroupReceiptPage, Error>) -> Void)
}

extension GroupReceiptProviding {
    func refreshGroup(groupId: String, completion: @escaping () -> Void) { completion() }
}

private struct ReceiptLoadError: LocalizedError {
    let errorDescription: String?
    init(_ text: String? = nil) { errorDescription = text ?? "group_receipt_load_failed".chat.localize }
}

final class GroupReceiptSDKProvider: GroupReceiptProviding {
    func refreshGroup(groupId: String, completion: @escaping () -> Void) {
        guard let manager = ChatClient.shared().groupManager else { completion(); return }
        manager.getGroupSpecificationFromServer(withId: groupId) { _, _ in completion() }
    }

    private func person(id: String, groupId: String, namecard: String?, nickname: String?, avatar: String?, joined: Int64 = 0) -> GroupReceiptPerson {
        let cached = ChatUIKitContext.shared?.userCache?[id] ?? ChatUIKitContext.shared?.chatCache?[id]
        let names = [namecard, GroupMemberAttributesCache.shared.nickname(groupId: groupId, userId: id), cached?.remark, nickname, cached?.nickname, id]
        let name = names.compactMap { $0 }.first { !$0.isEmpty } ?? id
        return GroupReceiptPerson(id: id, name: name, avatarURL: (avatar?.isEmpty == false ? avatar : cached?.avatarURL) ?? "", joinedTimestamp: joined)
    }

    private func hydrate(_ page: GroupReceiptPage, completion: @escaping (Result<GroupReceiptPage, Error>) -> Void) {
        let ids = page.people.filter { $0.name == $0.id || $0.avatarURL.isEmpty }.map(\.id)
        guard !ids.isEmpty, let manager = ChatClient.shared().userInfoManager else { completion(.success(page)); return }
        manager.fetchUserInfo(byId: ids, type: [0, 1]) { info, _ in
            var result = page
            result.people = page.people.map { original in
                var person = original
                if let user = info?[person.id] {
                    if person.name == person.id, let name = user.nickname, !name.isEmpty { person.name = name }
                    if person.avatarURL.isEmpty { person.avatarURL = user.avatarUrl ?? "" }
                }
                return person
            }
            completion(.success(result))
        }
    }

    func readers(message: ChatMessage, cursor: String, completion: @escaping (Result<GroupReceiptPage, Error>) -> Void) {
        guard let manager = ChatClient.shared().chatManager else { completion(.failure(ReceiptLoadError())); return }
        manager.asyncFetchGroupMessageReadUsers(fromServer: message.messageId, groupId: message.conversationId, readReceiptId: cursor, pageSize: 20) { result, error, total in
            guard error == nil, let result = result else { completion(.failure(ReceiptLoadError(error?.errorDescription))); return }
            let people = (result.list ?? []).map { receipt in
                let member = receipt.from
                return self.person(id: member.userId, groupId: message.conversationId, namecard: member.namecard, nickname: member.nickname, avatar: member.avatarUrl)
            }
            self.hydrate(GroupReceiptPage(people: people, cursor: result.cursor ?? "", total: Int(total)), completion: completion)
        }
    }

    func members(groupId: String, cursor: String, completion: @escaping (Result<GroupReceiptPage, Error>) -> Void) {
        guard let manager = ChatClient.shared().groupManager else { completion(.failure(ReceiptLoadError())); return }
        manager.fetchGroupMemberInfoListFromServer(withGroupId: groupId, cursor: cursor, limit: 100) { result, error in
            guard error == nil, let result = result else { completion(.failure(ReceiptLoadError(error?.errorDescription))); return }
            let people = (result.list ?? []).map { member in
                self.person(id: member.userId, groupId: groupId, namecard: member.namecard, nickname: member.nickname, avatar: member.avatarUrl, joined: Int64(member.joinedTimestamp))
            }
            self.hydrate(GroupReceiptPage(people: people, cursor: result.cursor ?? ""), completion: completion)
        }
    }
}

/// Keeps paginated receipts and the roster separate: a missing receipt page must never turn readers into unread members.
final class GroupMessageReceiptViewModel: NSObject, ChatResponseListener {
    let entity: MessageEntity
    private let provider: GroupReceiptProviding
    private let service: ChatServiceImplement
    private let account = ChatClient.shared().currentUsername
    private var generation = 0
    private var refreshScheduled = false
    private var reloadAfterLoading = false
    private var membersById = [String: GroupReceiptPerson]()
    private var readersById = [String: GroupReceiptPerson]()
    private(set) var readers = [GroupReceiptPerson]()
    private(set) var unread = [GroupReceiptPerson]()
    private(set) var readCount: Int
    private(set) var readersLoading = false
    private(set) var membersLoading = false
    private(set) var readersError: String?
    private(set) var membersError: String?
    var changed: (() -> Void)?
    var readCountChanged: ((Int) -> Void)?

    init(entity: MessageEntity, provider: GroupReceiptProviding = GroupReceiptSDKProvider()) {
        self.entity = entity
        self.provider = provider
        self.service = ChatServiceImplement(to: entity.message.conversationId)
        self.readCount = entity.effectiveGroupReadCount
        super.init()
        self.service.bindChatEventsListener(listener: self)
    }

    deinit { service.unbindChatEventsListener(listener: self) }

    var unreadCount: Int? {
        guard let total = entity.groupReceiptRecipientCount else { return nil }
        return max(0, total - readCount)
    }

    var unreadReady: Bool { !readersLoading && !membersLoading && readersError == nil && membersError == nil && readers.count == readCount }
    var unreadIncomplete: Bool { unreadCount == nil || unreadCount != unread.count }

    func reload() {
        generation += 1
        let version = generation
        readersLoading = true; membersLoading = true
        readersError = nil; membersError = nil
        readersById.removeAll(); membersById.removeAll(); readers.removeAll(); unread.removeAll()
        reloadAfterLoading = false
        changed?()
        provider.refreshGroup(groupId: entity.message.conversationId) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.valid(version) else { return }
                self.readCountChanged?(self.readCount)
                self.changed?()
            }
        }
        loadReaders(cursor: "", visited: [], version: version)
        loadMembers(cursor: "", visited: [], version: version)
    }

    private func valid(_ version: Int) -> Bool { generation == version && account == ChatClient.shared().currentUsername }

    private func loadReaders(cursor: String, visited: Set<String>, version: Int) {
        provider.readers(message: entity.message, cursor: cursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.valid(version) else { return }
                switch result {
                case .failure(let error):
                    self.readersError = error.localizedDescription
                    self.readersLoading = false
                case .success(let page):
                    for person in page.people where person.id != self.entity.message.from && !person.id.isEmpty { self.readersById[person.id] = person }
                    self.readers = self.sorted(self.readersById)
                    self.readCount = max(self.readCount, page.total, self.readers.count)
                    self.entity.groupReadCount = self.readCount
                    self.readCountChanged?(self.readCount)
                    if page.cursor.isEmpty {
                        self.readersLoading = false
                        if self.readers.count != self.readCount { self.readersError = "group_receipt_changed_retry".chat.localize }
                    } else if page.cursor == cursor || visited.contains(page.cursor) {
                        self.readersLoading = false
                        self.readersError = "group_receipt_load_failed".chat.localize
                    } else {
                        self.loadReaders(cursor: page.cursor, visited: visited.union([cursor]), version: version)
                    }
                }
                self.updated()
            }
        }
    }

    private func loadMembers(cursor: String, visited: Set<String>, version: Int) {
        provider.members(groupId: entity.message.conversationId, cursor: cursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.valid(version) else { return }
                switch result {
                case .failure(let error):
                    self.membersError = error.localizedDescription
                    self.membersLoading = false
                case .success(let page):
                    for person in page.people where !person.id.isEmpty { self.membersById[person.id] = person }
                    if page.cursor.isEmpty {
                        self.membersLoading = false
                    } else if page.cursor == cursor || visited.contains(page.cursor) {
                        self.membersLoading = false
                        self.membersError = "group_receipt_load_failed".chat.localize
                    } else {
                        self.loadMembers(cursor: page.cursor, visited: visited.union([cursor]), version: version)
                    }
                }
                self.updated()
            }
        }
    }

    private func sorted(_ people: [String: GroupReceiptPerson]) -> [GroupReceiptPerson] {
        people.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updated() {
        if unreadReady {
            let targets = Set(entity.message.receiverList ?? [])
            let sent = entity.message.timestamp
            unread = sorted(membersById.filter { id, member in
                // SDK variants expose join time in seconds or milliseconds.
                let joined = member.joinedTimestamp > 0 && member.joinedTimestamp < 100_000_000_000 ? member.joinedTimestamp * 1000 : member.joinedTimestamp
                return id != entity.message.from && readersById[id] == nil
                    && (targets.isEmpty || targets.contains(id)) && (joined == 0 || joined <= sent)
            })
        } else {
            unread = []
        }
        changed?()
        if !readersLoading && !membersLoading && reloadAfterLoading { scheduleRefresh() }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.refreshScheduled = false
            guard self.account == ChatClient.shared().currentUsername else { return }
            if self.readersLoading || self.membersLoading { self.reloadAfterLoading = true } else { self.reload() }
        }
    }

    func messageReadReceiptReceived(receipt: [MessageReadReceipt]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.account == ChatClient.shared().currentUsername,
                  let newest = receipt.filter({ $0.conversationId == self.entity.message.conversationId && $0.messageId == self.entity.message.messageId }).map(\.readCount).max(), newest > self.readCount else { return }
            self.readCount = newest
            self.entity.groupReadCount = newest
            self.readCountChanged?(newest)
            self.updated()
            self.scheduleRefresh()
        }
    }

    func onCMDMessageDidReceived(message: ChatMessage) {}
    func onMessageDidReceived(message: ChatMessage) {}
    func onMessageDidRecalled(recallInfo: RecallInfo) {}
    func onMessageDidEdited(message: ChatMessage) {}
    func onMessageStatusDidChanged(message: ChatMessage, status: ChatMessageStatus, error: ChatError?) {}
    func onMessageAttachmentStatusChanged(message: ChatMessage, error: ChatError?) {}
    func onMessageReactionChanged(changes: [MessageReactionChange]) {}
    func onMessageStickiedTop(conversationId: String, messageId: String, operation: MessagePinOperation, info: MessagePinInfo) {}
    func messagesAlreadyRead(conversationId: String) {}
}
