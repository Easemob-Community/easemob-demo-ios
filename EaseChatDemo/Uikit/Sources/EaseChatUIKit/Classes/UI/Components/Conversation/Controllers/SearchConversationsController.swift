//
//  SearchConversationController.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/14.
//

import UIKit

@objc open class SearchConversationsController: UIViewController {
    
    private enum SearchSection: Int {
        case conversation
        case contact
        case message
    }
    
    /// Maximum number of contact rows displayed in the contact section before the "more contacts" row appears.
    private let contactDisplayLimit = 3
    
    /// Maximum number of message rows loaded by the global message search.
    private let messageSearchLimit = 50
    
    private var datas: [ConversationInfo] = []
    
    private var rawContacts: [ChatUserProfileProtocol] = []
    
    private var searchConversations: [ConversationInfo] = []
    
    /// Already truncated to `contactDisplayLimit` for display.
    private var searchContacts: [ChatUserProfileProtocol] = []
    
    private var searchMessages: [ChatMessage] = []
    
    private var moreContactsAvailable = false
    
    private var searchText = ""
    
    private var chatClosure: ((ConversationInfo) -> Void)?
    
    /// Override the default behavior(contact row tap opens the chat) if needed.
    public var contactChatClosure: ((ChatUserProfileProtocol) -> Void)?
    
    /// Override the default behavior(message row tap jumps to `SearchResultMessagesController`) if needed.
    public var messageClosure: ((ChatMessage) -> Void)?
    
    private var searchWorkItem: DispatchWorkItem?
    
    public private(set) lazy var searchHeader: SearchHeaderBar = {
        SearchHeaderBar(frame: CGRect(x: 0, y: StatusBarHeight+10, width: ScreenWidth, height: 44), displayStyle: .other).backgroundColor(.clear)
    }()
    
    public private(set) lazy var searchList: UITableView = {
        UITableView(frame: CGRect(x: 0, y: self.searchHeader.frame.maxY+10, width: self.view.frame.width, height: self.view.frame.height-self.searchHeader.frame.maxY-BottomBarHeight-10), style: .plain).delegate(self).dataSource(self).tableFooterView(UIView()).separatorStyle(.none).backgroundColor(.clear)
    }()
    
    public private(set) lazy var empty: EmptyStateView = {
        EmptyStateView(frame: CGRect(x: 0, y: 0, width: self.searchList.frame.width, height: self.searchList.frame.height),emptyImage: UIImage(chatNamed: "empty")) {
            
        }
    }()
    
    @objc(initWithSearchInfos:toChat:)
    public required init(searchInfos: [ConversationInfo],toChat: @escaping (ConversationInfo) -> Void) {
        self.datas = searchInfos
        self.chatClosure = toChat
        super.init(nibName: nil, bundle: nil)
    }
    
    /// Swift only initializer with full mixed search callbacks.
    public required init(searchInfos: [ConversationInfo],contacts: [ChatUserProfileProtocol] = [],toChat: @escaping (ConversationInfo) -> Void,contactChat: ((ChatUserProfileProtocol) -> Void)? = nil,messageTap: ((ChatMessage) -> Void)? = nil) {
        self.datas = searchInfos
        self.rawContacts = contacts
        self.chatClosure = toChat
        self.contactChatClosure = contactChat
        self.messageClosure = messageTap
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.searchWorkItem?.cancel()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.view.backgroundColor = UIColor.theme.neutralColor98
        self.view.addSubViews([self.searchHeader,self.searchList])
        self.searchList.keyboardDismissMode = .onDrag
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
        if self.rawContacts.isEmpty {
            self.loadAllContacts()
        } else {
            self.refreshSearchResults()
        }
        self.searchHeader.textChanged = { [weak self] in
            guard let self = self else { return }
            self.searchText = $0
            self.filterConversationsAndContacts()
            self.debounceMessageSearch()
            self.updateEmptyView()
            self.searchList.reloadData()
        }
        self.searchHeader.actionClosure = { [weak self] in
            guard let self = self else { return }
            self.searchWorkItem?.cancel()
            self.searchText = ""
            self.searchConversations.removeAll()
            self.searchContacts.removeAll()
            self.searchMessages.removeAll()
            self.moreContactsAvailable = false
            self.updateEmptyView()
            self.searchList.reloadData()
            if $0 == .cancel {
                self.pop()
            }
        }
        
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.searchHeader.searchField.becomeFirstResponder()
    }
    
    /// Loads contacts from the local database when no contacts were injected on initialization.
    @objc open func loadAllContacts() {
        guard let contacts = ChatClient.shared().contactManager?.getAllContacts() else { return }
        self.rawContacts = contacts.map {
            let profile = ChatUserProfile()
            profile.id = $0.userId
            profile.nickname = $0.userInfo?.nickname ?? ChatUIKitContext.shared?.userCache?[$0.userId]?.nickname ?? ""
            profile.avatarURL = $0.userInfo?.avatarUrl ?? ChatUIKitContext.shared?.userCache?[$0.userId]?.avatarURL ?? ""
            profile.remark = $0.remark ?? ChatUIKitContext.shared?.userCache?[$0.userId]?.remark ?? ""
            return profile
        }
        self.refreshSearchResults()
    }
    
    private func refreshSearchResults() {
        self.filterConversationsAndContacts()
        self.updateEmptyView()
        self.searchList.reloadData()
    }
    
    /// Exact display name used by ``ConversationSearchCell/refresh(info:keyword:)``.
    private func displayName(of info: ConversationInfo) -> String {
        var showName = ChatUIKitContext.shared?.userCache?[info.id]?.remark ?? ""
        if showName.isEmpty {
            if info.type == .chat {
                showName = ChatUIKitContext.shared?.userCache?[info.id]?.nickname ?? ""
            } else {
                showName = ChatUIKitContext.shared?.groupCache?[info.id]?.nickname ?? ""
            }
        }
        if showName.isEmpty {
            showName = info.id
        }
        return showName
    }
    
    /// Exact display name used by ``ContactCell/refresh(profile:keyword:)``.
    /// - Note: ``ContactCell`` is cache-first and never falls back to the fields on ``profile``,
    /// so filtering must mirror that order or invisible fields(like an SDK-only remark) would leak into results.
    private func displayName(of profile: ChatUserProfileProtocol) -> String {
        var showName = ChatUIKitContext.shared?.userCache?[profile.id]?.remark ?? ""
        if showName.isEmpty {
            showName = ChatUIKitContext.shared?.userCache?[profile.id]?.nickname ?? ""
        }
        if showName.isEmpty {
            showName = profile.id
        }
        return showName
    }
    
    private func filterConversationsAndContacts() {
        let keyword = self.searchText.lowercased()
        //Nothing is shown until the user types a keyword.
        guard !keyword.isEmpty else {
            self.searchConversations.removeAll()
            self.searchContacts.removeAll()
            self.moreContactsAvailable = false
            return
        }
        //Search exactly the field that will be rendered & highlighted in the cell, so every visible row always highlights the keyword.
        self.searchConversations = self.datas.filter {
            self.displayName(of: $0).lowercased().contains(keyword)
        }
        let matched = self.rawContacts.filter {
            self.displayName(of: $0).lowercased().contains(keyword)
        }
        self.moreContactsAvailable = matched.count > self.contactDisplayLimit
        self.searchContacts = Array(matched.prefix(self.contactDisplayLimit))
    }
    
    /// Debounces the database message search while the user is typing.
    private func debounceMessageSearch() {
        self.searchWorkItem?.cancel()
        let keyword = self.searchText.lowercased()
        guard !keyword.isEmpty else {
            self.searchMessages.removeAll()
            return
        }
        let item = DispatchWorkItem { [weak self] in
            self?.performMessageSearch(keyword: keyword)
        }
        self.searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
    
    /// Global text message search across all conversations via the chat manager.
    /// - Note: `timestamp` must be the current time; a `.down` search from 0 would return nothing.
    @objc open func performMessageSearch(keyword: String) {
        ChatClient.shared().chatManager?.loadMessages(withKeyword: keyword, timestamp: -1, count: Int32(self.messageSearchLimit), fromUser: nil, searchDirection: .down, scope: .content, completion: { [weak self] messages, error in
            guard let self = self else { return }
            guard error == nil else {
                consoleLogInfo("SearchConversationsController search message error:\(error?.errorDescription ?? "")", type: .error)
                return
            }
            let matched = (messages ?? []).filter({ $0.body.type == .text })
            DispatchQueue.main.async {
                // Discard the result if the keyword changed while the search was running.
                guard self.searchText.lowercased() == keyword else { return }
                self.searchMessages = matched
                self.updateEmptyView()
                self.searchList.reloadData()
            }
        })
    }
    
    private func updateEmptyView() {
        DispatchQueue.main.async {
            self.searchList.backgroundView = self.visibleSections.isEmpty ? self.empty : nil
        }
    }
    
    private var visibleSections: [SearchSection] {
        var sections = [SearchSection]()
        if !self.searchConversations.isEmpty {
            sections.append(.conversation)
        }
        if !self.searchContacts.isEmpty || self.moreContactsAvailable {
            sections.append(.contact)
        }
        if !self.searchMessages.isEmpty {
            sections.append(.message)
        }
        return sections
    }
    
    /// Localized section title with a Chinese fallback until the new keys land in the string tables.
    private func localized(_ key: String, fallback: String) -> String {
        let value = key.chat.localize
        return value == key ? fallback : value
    }
    
    private func title(of section: SearchSection) -> String {
        switch section {
        case .conversation: return self.localized("search_section_conversations", fallback: "会话")
        case .contact: return self.localized("search_section_contacts", fallback: "联系人")
        case .message: return self.localized("search_section_messages", fallback: "消息")
        }
    }
    
    @objc open func openChat(with userId: String) {
        ChatClient.shared().chatManager?.clearConversationUnreadMessageCount(userId) { error in
            if error != nil {
                consoleLogInfo("SearchConversationsController clearConversationUnreadMessageCount error:\(error?.errorDescription ?? "")", type: .error)
            }
        }
        let vc = ComponentsRegister.shared.MessageViewController.init(conversationId: userId)
        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
    }
    
    private func showMoreContacts() {
        let vc = ContactSearchResultController(headerStyle: .contact) { [weak self] profile in
            guard let self = self else { return }
            if let closure = self.contactChatClosure {
                closure(profile)
            } else {
                self.openChat(with: profile.id)
            }
        }
        ControllerStack.toDestination(vc: vc)
    }
}

extension SearchConversationsController: UITableViewDelegate,UITableViewDataSource {
    
    private func pop() {
        if self.navigationController != nil {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true)
        }
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        self.visibleSections.count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = self.visibleSections[safe: section] else { return 0 }
        switch sectionType {
        case .conversation:
            return self.searchConversations.count
        case .contact:
            return self.searchContacts.count + (self.moreContactsAvailable ? 1 : 0)
        case .message:
            return self.searchMessages.count
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let sectionType = self.visibleSections[safe: indexPath.section] else { return Appearance.conversation.rowHeight }
        switch sectionType {
        case .conversation, .message:
            return Appearance.conversation.rowHeight
        case .contact:
            return indexPath.row < self.searchContacts.count ? Appearance.contact.rowHeight : 44
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        36
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionType = self.visibleSections[safe: section] else { return nil }
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 36)).backgroundColor(.clear)
        let label = UILabel(frame: CGRect(x: 16, y: 0, width: header.frame.width-32, height: 36)).backgroundColor(.clear)
        label.font = UIFont.theme.bodyLarge
        label.textColor = Theme.style == .dark ? UIColor.theme.neutralColor6:UIColor.theme.neutralColor5
        label.text = self.title(of: sectionType)
        header.addSubview(label)
        return header
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = self.visibleSections[safe: indexPath.section] else { return UITableViewCell() }
        switch sectionType {
        case .conversation:
            var cell = tableView.dequeueReusableCell(withIdentifier: "ConversationSearchCell") as? ConversationSearchCell
            if cell == nil {
                cell = ConversationSearchCell(style: .default, reuseIdentifier: "ConversationSearchCell")
            }
            if let info = self.searchConversations[safe: indexPath.row] {
                cell?.refresh(info: info, keyword: self.searchText)
            }
            cell?.selectionStyle = .none
            return cell ?? UITableViewCell()
        case .contact:
            if indexPath.row < self.searchContacts.count {
                var cell = tableView.dequeueReusableCell(with: ComponentsRegister.shared.ContactsCell.self, reuseIdentifier: "EaseUIKit_ContactsCell_MixedSearch")
                if cell == nil {
                    cell = ComponentsRegister.shared.ContactsCell.init(displayStyle: .normal, identifier: "EaseUIKit_ContactsCell_MixedSearch")
                }
                cell?.backgroundColor = .clear
                if let info = self.searchContacts[safe: indexPath.row] {
                    cell?.refresh(profile: info, keyword: self.searchText)
                }
                cell?.selectionStyle = .none
                return cell ?? UITableViewCell()
            } else {
                //"More contacts" row.
                var cell = tableView.dequeueReusableCell(withIdentifier: "EaseUIKit_MoreContactsCell")
                if cell == nil {
                    cell = UITableViewCell(style: .default, reuseIdentifier: "EaseUIKit_MoreContactsCell")
                }
                cell?.backgroundColor = .clear
                cell?.selectionStyle = .none
                cell?.textLabel?.font = UIFont.theme.labelMedium
                cell?.textLabel?.textColor = Theme.style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor
                cell?.textLabel?.text = self.localized("search_more_contacts", fallback: "更多联系人")
                cell?.separatorInset = UIEdgeInsets(top: 0, left: 16 + 50 + 12, bottom: 0, right: 0)
                return cell ?? UITableViewCell()
            }
        case .message:
            var cell = tableView.dequeueReusableCell(withIdentifier: "EaseUIKit_SearchHistoryMessageCell") as? SearchHistoryMessageCell
            if cell == nil {
                cell = SearchHistoryMessageCell(style: .default, reuseIdentifier: "EaseUIKit_SearchHistoryMessageCell")
            }
            if let item = self.searchMessages[safe: indexPath.row],let info = item.user {
                info.remark = ChatUIKitContext.shared?.userCache?[item.from]?.remark ?? ""
                cell?.refresh(message: item, info: info, keyword: self.searchText)
            }
            cell?.selectionStyle = .none
            cell?.backgroundColor = .clear
            return cell ?? UITableViewCell()
        }
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionType = self.visibleSections[safe: indexPath.section] else { return }
        switch sectionType {
        case .conversation:
            if let info = self.searchConversations[safe: indexPath.row] {
                self.chatClosure?(info)
            }
        case .contact:
            if indexPath.row < self.searchContacts.count {
                if let info = self.searchContacts[safe: indexPath.row] {
                    if let closure = self.contactChatClosure {
                        closure(info)
                    } else {
                        self.openChat(with: info.id)
                    }
                }
            } else {
                self.showMoreContacts()
            }
        case .message:
            if let message = self.searchMessages[safe: indexPath.row] {
                if let closure = self.messageClosure {
                    closure(message)
                } else {
                    let vc = SearchResultMessagesController(conversationId: message.conversationId, chatType: message.chatType == .chat ? .chat:.group, searchMessageId: message.messageId)
                    ControllerStack.toDestination(vc: vc)
                }
            }
        }
    }
    
}

extension SearchConversationsController: ThemeSwitchProtocol {
    public func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
        self.searchList.reloadData()
    }
}
