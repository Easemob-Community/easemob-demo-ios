//
//  GroupParticipantsController.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/27.
//

import UIKit

/**
 An enumeration representing the possible operations for group participants.
 
 - normal: Represents a normal operation.
 - mention: Represents an operation related to mentioning participants.
 - transferOwner: Represents an operation related to transferring ownership of the group.
 */
@objc public enum GroupParticipantsOperation: UInt {
    case normal
    case mention
    case transferOwner
    case manageAdmins
}

/// A view controller that displays the participants of a group.
@objcMembers open class GroupParticipantsController: UIViewController {
    
    private var pageSize = UInt(200)
    
    private var recursiveCount = 5
    
    private let service: GroupService = ChatUIKitClient.shared.groupService
    
    private var cursor = ""
    
    private var loadFinished = false
    private var adminIds = Set<String>()
    private var adminRequestInFlight = false
    private var canManageAdmins = false
    private let adminAccount = saveIdentifier
    
    /**
     The array of participants in the group.
     */
    public private(set) var participants: [ChatUserProfileProtocol] = []
    
    public private(set) var chatGroup = ChatGroup()
    
    public var mentionClosure: ((ChatUserProfileProtocol) -> Void)?
    
    public private(set) var operation = GroupParticipantsOperation.normal
    
    public private(set) lazy var navigation: ChatNavigationBar = {
        self.createNavigation()
    }()
    
    /// Creates and returns a navigation bar for the GroupParticipantsController.
    /// - Returns: An instance of EaseChatNavigationBar.
    @objc open func createNavigation() -> ChatNavigationBar {
        ChatNavigationBar(show: self.operation == .mention ? CGRect(x: 0, y: 0, width: ScreenWidth, height: 44):CGRect(x: 0, y: 0, width: ScreenWidth, height: NavigationHeight),showLeftItem: true, textAlignment: .left, rightImages:  self.rightImages ,hiddenAvatar: true).backgroundColor(.clear)
    }
    
    private var rightImages: [UIImage] {
        ((self.chatGroup.owner == ChatUIKitContext.shared?.currentUserId ?? "" && !self.chatGroup
            .isDisabled)&&self.operation == .normal) ? [UIImage(chatNamed: "person_add")!,UIImage(chatNamed: "members_remove")!]:[]
    }
    
    public private(set) lazy var participantsList: UITableView = {
        UITableView(frame: CGRect(x: 0, y: self.navigation.frame.height, width: self.view.frame.width, height: self.view.frame.height-self.navigation.frame.height), style: .plain).delegate(self).dataSource(self).tableFooterView(UIView()).rowHeight(60).backgroundColor(.clear).separatorStyle(.none)
    }()
    
    /**
     Initializes a `GroupParticipantsController` with the specified group ID and operation.
     
     - Parameters:
        - groupId: The ID of the group.
        - operation: The operation to be performed on the group participants. Default value is `.normal`.
     
     - Returns: An initialized `GroupParticipantsController` instance.
     */
    @objc required public init(groupId: String, operation: GroupParticipantsOperation = .normal) {
        self.chatGroup = ChatGroup(id: groupId)
        self.operation = operation
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    


    open override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.view.backgroundColor = UIColor.theme.neutralColor98
        self.setupTitle()
        self.view.addSubViews([self.navigation,self.participantsList])
        // Do any additional setup after loading the view.
        //click of the navigation
        self.navigation.clickClosure = { [weak self] in
            self?.navigationClick(type: $0, indexPath: $1)
        }
        if self.operation != .manageAdmins {
            self.fetchParticipants()
        }
        
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshList), name: Notification.Name(rawValue: cache_update_notification), object: nil)
        if self.operation == .manageAdmins {
            self.service.bindGroupEventsListener(listener: self)
        }
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.operation == .manageAdmins {
            self.fetchParticipants()
        }
        self.refreshList()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.service.unbindGroupEventsListener(listener: self)
    }
    
    @objc private func refreshList() {
        DispatchQueue.main.async {
            for participant in self.participants {
                if let user = ChatUIKitContext.shared?.userCache?[participant.id]{
                    participant.nickname = user.nickname
                    participant.remark = user.remark
                    participant.avatarURL = user.avatarURL
                }
            }
            self.participantsList.reloadData()
        }
    }
    
    private func setupTitle() {
        var text = ""
        switch self.operation {
        case .normal:
            text = "group_details_button_members".chat.localize
        case .mention:
            text = "group_mention_title".chat.localize
        case .transferOwner:
            text = "group_details_extend_button_transfer".chat.localize
        case .manageAdmins:
            text = "group_admin_settings_title".chat.localize
        }
        if self.participants.count > 0 {
            text += "(\(self.participants.count))"
        }
        self.navigation.title = text
    }
    
    
    /**
     Handles the navigation bar click events.
     
     - Parameters:
        - type: The type of navigation bar click event.
        - indexPath: The index path associated with the event (optional).
     */
    @objc open func navigationClick(type: ChatNavigationBarClickEvent, indexPath: IndexPath?) {
        switch type {
        case .back: self.pop()
        case .rightItems: self.rightActions(indexPath: indexPath ?? IndexPath())
        default:
            break
        }
    }
    
    @objc open func pop() {
        if self.navigationController != nil {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true)
        }
    }

    private func rightActions(indexPath: IndexPath) {
        switch indexPath.row {
        case 0: self.toAdd()
        case 1: self.toRemove()
        default:
            break
        }
    }
    
    @objc open func ignoreContacts() -> [String] {
        let contacts = ChatClient.shared().contactManager?.getContacts() ?? []
        var ignoreIds = [String]()
        for participant in self.participants {
            for id in contacts {
                if id == participant.id {
                    ignoreIds.append(id)
                }
            }
        }
        return ignoreIds
    }
    
    @objc open func toAdd() {
        let vc = ComponentsRegister.shared.ContactsController.init(headerStyle: .addGroupParticipant,ignoreIds: self.ignoreContacts())
        vc.confirmClosure = { [weak self] users in
            guard let `self` = self else { return }
            self.service
                .invite(userIds: users.map({ $0.id }), to: self.chatGroup.groupId, message: "", completion: { [weak self] group, error in
                    if error == nil {
                        self?.participants.append(contentsOf: users)
                        self?.participantsList.reloadData()
                        self?.setupTitle()
                        self?.pop()
                    } else {
                        consoleLogInfo("Add participants  error:\(error?.errorDescription ?? "")", type: .error)
                    }
                })
        }
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc open func toRemove() {
        let vc = ComponentsRegister.shared.RemoveGroupParticipantController.init(group: self.chatGroup, profiles: self.participants.filter({ $0.id != self.chatGroup.owner })) { [weak self] userIds in
            for userId in userIds {
                self?.participants.removeAll(where: { $0.id == userId })
            }
            self?.participantsList.reloadData()
            self?.setupTitle()
        }
        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
    }

    @objc open func fetchParticipants() {
        if self.operation == .manageAdmins {
            self.loadAdminSettings()
            return
        }
        if self.participants.count < Appearance.chat.groupParticipantsLimitCount {
            self.service.fetchParticipants(groupId: self.chatGroup.groupId, cursor: self.cursor, pageSize: self.pageSize) { [weak self] result, error in
                guard let `self` = self else { return }
                if error == nil {
                    if let list = result?.list {
                        if self.cursor.isEmpty {
                            self.participants.removeAll()
                            self.participants = list.map({
                                let profile = ChatUserProfile()
                                let id = $0 as String
                                profile.id = id
                                if let user = ChatUIKitContext.shared?.userCache?[id] {
                                    profile.nickname = user.nickname
                                    profile.avatarURL = user.avatarURL
                                }
                                if let user = ChatUIKitContext.shared?.chatCache?[id] {
                                    profile.nickname = user.nickname
                                    profile.avatarURL = user.avatarURL
                                }
                                
                                return profile
                            })
                            if list.count <= self.pageSize {
                                if self.operation != .transferOwner {
                                    let profile = ChatUserProfile()
                                    profile.id = self.chatGroup.owner
                                    if let user = ChatUIKitContext.shared?.userCache?[self.chatGroup.owner] {
                                        profile.nickname = user.nickname
                                        profile.avatarURL = user.avatarURL
                                    }
                                    if let user = ChatUIKitContext.shared?.chatCache?[self.chatGroup.owner] {
                                        profile.nickname = user.nickname
                                        profile.avatarURL = user.avatarURL
                                    }
                                    self.participants.insert(profile, at: 0)
                                }
                                self.loadFinished = true
                                self.participantsList.reloadData()
                                return
                            }
                        } else {
                            self.participants.append(contentsOf: list.map({
                                let profile = ChatUserProfile()
                                profile.id = $0 as String
                                if let user = ChatUIKitContext.shared?.userCache?[profile.id] {
                                    profile.nickname = user.nickname
                                    profile.avatarURL = user.avatarURL
                                }
                                if let user = ChatUIKitContext.shared?.chatCache?[profile.id] {
                                    profile.nickname = user.nickname
                                    profile.avatarURL = user.avatarURL
                                }
                                return profile
                            }))
                        }
                    }
                    self.cursor = result?.cursor ?? ""
                    if self.operation == .mention {
                        self.participants.removeAll { $0.id == ChatUIKitContext.shared?.currentUserId ?? "" }
                    }
                    self.participantsList.reloadData()
                    self.recursiveCount -= 1
                    if self.participants.count < Appearance.chat.groupParticipantsLimitCount {
                        self.fetchParticipants()
                    }
                } else {
                    consoleLogInfo("GroupParticipantsController fetch error:\(error?.errorDescription ?? "")", type: .error)
                    showToast(toast: error?.errorDescription ?? "")
                }
                
                self.setupTitle()
            }
        } else {
            if self.operation == .mention {
                let profile = ChatUserProfile()
                profile.id = "All"
                profile.nickname = "All"
                profile.avatarURL = "all"
                self.participants.insert(profile, at: 0)
            }
            self.participantsList.reloadData()
        }
    }

    private func loadAdminSettings() {
        self.canManageAdmins = false
        self.participantsList.reloadData()
        let loading = UIActivityIndicatorView(style: .medium)
        loading.startAnimating()
        self.participantsList.backgroundView = loading
        self.service.fetchGroupInfo(groupId: self.chatGroup.groupId) { [weak self] group, error in
            DispatchQueue.main.async {
                guard let self = self, self.adminAccount == saveIdentifier else { return }
                self.participantsList.backgroundView = nil
                guard error == nil, let group = group else {
                    self.showToast(toast: error?.errorDescription ?? "group_admin_load_failed".chat.localize)
                    return
                }
                self.chatGroup = group
                self.adminIds = Set(group.adminList ?? [])
                self.canManageAdmins = !group.isDisabled && group.owner == ChatUIKitContext.shared?.currentUserId
                guard self.canManageAdmins else {
                    self.participantsList.reloadData()
                    self.showToast(toast: "group_admin_owner_only".chat.localize)
                    return
                }
                // Admin IDs come from fresh group details, so existing admins are
                // available even if a member page doesn't include them.
                self.participants = self.adminIds.sorted().filter { $0 != group.owner }.map { self.adminProfile(userId: $0) }
                self.fetchAdminMemberPage(cursor: "")
            }
        }
    }

    private func adminProfile(userId: String) -> ChatUserProfileProtocol {
        let profile = ChatUserProfile()
        profile.id = userId
        let cached = ChatUIKitContext.shared?.userCache?[userId] ?? ChatUIKitContext.shared?.chatCache?[userId]
        profile.nickname = cached?.nickname ?? ""
        profile.avatarURL = cached?.avatarURL ?? ""
        return profile
    }

    private func fetchAdminMemberPage(cursor: String) {
        self.service.fetchParticipants(groupId: self.chatGroup.groupId, cursor: cursor, pageSize: self.pageSize) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.adminAccount == saveIdentifier else { return }
                if let error = error {
                    self.showToast(toast: error.errorDescription ?? "group_admin_load_failed".chat.localize)
                    return
                }
                var ids = Set(self.participants.map { $0.id })
                for user in result?.list ?? [] {
                    let userId = user as String
                    if userId != self.chatGroup.owner, ids.insert(userId).inserted {
                        self.participants.append(self.adminProfile(userId: userId))
                    }
                }
                self.participantsList.reloadData()
                self.setupTitle()
                self.participantsList.layoutIfNeeded()
                self.requestDisplayInfos()
                let next = result?.cursor ?? ""
                if !next.isEmpty, next != cursor {
                    self.fetchAdminMemberPage(cursor: next)
                }
            }
        }
    }

    private func changeAdmin(profile: ChatUserProfileProtocol) {
        guard self.adminAccount == saveIdentifier, self.canManageAdmins,
              !self.adminRequestInFlight, profile.id != self.chatGroup.owner else { return }
        let removing = self.adminIds.contains(profile.id)
        let name = profile.nickname.isEmpty ? profile.id : profile.nickname
        let prompt = String(format: (removing ? "group_admin_remove_confirm" : "group_admin_add_confirm").chat.localize, name)
        DialogManager.shared.showAlert(title: "", content: prompt, showCancel: true, showConfirm: true) { [weak self] _ in
            guard let self = self, self.adminAccount == saveIdentifier, self.canManageAdmins,
                  !self.adminRequestInFlight, self.adminIds.contains(profile.id) == removing else { return }
            self.adminRequestInFlight = true
            self.participantsList.reloadData()
            let completion: (ChatGroup?, ChatError?) -> Void = { [weak self] group, error in
                DispatchQueue.main.async {
                    guard let self = self, self.adminAccount == saveIdentifier else { return }
                    self.adminRequestInFlight = false
                    if let error = error {
                        self.showToast(toast: error.errorDescription ?? "group_admin_update_failed".chat.localize)
                    } else {
                        if removing { self.adminIds.remove(profile.id) }
                        else { self.adminIds.insert(profile.id) }
                        if let group = group { self.chatGroup = group }
                    }
                    self.participantsList.reloadData()
                }
            }
            if removing {
                self.service.removeAdmin(userId: profile.id, from: self.chatGroup.groupId, completion: completion)
            } else {
                self.service.addAdmin(userId: profile.id, to: self.chatGroup.groupId, completion: completion)
            }
        }
    }
}

extension GroupParticipantsController: GroupServiceListener {
    public func onGroupAdminUpdated(groupId: String, userId: String, added: Bool) {
        guard self.operation == .manageAdmins, self.adminAccount == saveIdentifier,
              groupId == self.chatGroup.groupId else { return }
        if added { self.adminIds.insert(userId) }
        else { self.adminIds.remove(userId) }
        self.participantsList.reloadData()
    }
}


extension GroupParticipantsController: UITableViewDelegate,UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.participants.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        self.cellForRowAt(indexPath: indexPath)
    }
    
    @objc open func cellForRowAt(indexPath: IndexPath) -> UITableViewCell {
        var cell = self.participantsList.dequeueReusableCell(withIdentifier: "GroupParticipantCell") as? GroupParticipantCell
        if cell == nil {
            cell = GroupParticipantCell(displayStyle: .normal, identifier: "GroupParticipantCell")
        }
        if let profile = self.participants[safe: indexPath.row] {
            cell?.refresh(profile: profile, keyword: "")
            if self.operation == .manageAdmins {
                let removing = self.adminIds.contains(profile.id)
                let button = UIButton(type: .system)
                button.frame = CGRect(x: 0, y: 0, width: 96, height: 44)
                button.titleLabel?.font = UIFont.theme.labelMedium
                button.setTitle((removing ? "group_admin_remove_action" : "group_admin_settings_entry").chat.localize, for: .normal)
                button.setTitleColor(removing ? UIColor.theme.errorColor5 : (Theme.style == .dark ? UIColor.theme.primaryDarkColor : UIColor.theme.primaryLightColor), for: .normal)
                button.isEnabled = self.canManageAdmins && !self.adminRequestInFlight
                button.addAction(UIAction { [weak self] _ in self?.changeAdmin(profile: profile) }, for: .touchUpInside)
                cell?.accessoryView = button
            } else {
                cell?.accessoryView = nil
            }
        }
        cell?.selectionStyle = .none
        return cell ?? GroupParticipantCell()
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView.isKind(of: UICollectionView.self) {
            return
        }
        self.requestDisplayInfos()
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.requestDisplayInfos()
        }
    }
    
    @objc open func requestDisplayInfos() {
        var unknownInfoIds = [String]()
        if let visiblePaths = self.participantsList.indexPathsForVisibleRows {
            for indexPath in visiblePaths {
                if let nickName = self.participants[safe: indexPath.row]?.nickname,nickName.isEmpty {
                    if let unknownId = self.participants[safe: indexPath.row]?.id {
                        unknownInfoIds.append(unknownId)
                    }
                }
            }
        }
        if ChatUIKitContext.shared?.userProfileProvider != nil {
            if !unknownInfoIds.isEmpty {
                Task {
                    let profiles = await ChatUIKitContext.shared?.userProfileProvider?.fetchProfiles(profileIds: unknownInfoIds) ?? []
                    self.fillCache(profiles: profiles)
                    DispatchQueue.main.async {
                        self.processCacheProfiles(values: profiles)
                    }
                }
            }
        } else {
            ChatUIKitContext.shared?.userProfileProviderOC?.fetchProfiles(profileIds: unknownInfoIds, completion: { [weak self] profiles in
                guard let `self` = self else { return }
                self.fillCache(profiles: profiles)
                self.processCacheProfiles(values: profiles)
            })
        }
    }
    
    private func fillCache(profiles: [ChatUserProfileProtocol]) {
        for profile in profiles {
            if let cached = ChatUIKitContext.shared?.userCache?[profile.id] {
                cached.nickname = profile.nickname
                cached.remark = profile.remark
                cached.avatarURL = profile.avatarURL
            } else {
                ChatUIKitContext.shared?.userCache?[profile.id] = profile
            }
        }
    }
    
    private func processCacheInfos(values: [String]) {
        for participant in self.participants {
            for value in values {
                if value == participant.id {
                    participant.nickname = value
                }
            }
        }
        self.participantsList.reloadData()
    }
    
    private func processCacheProfiles(values: [ChatUserProfileProtocol]) {
        for participant in self.participants {
            for value in values {
                if value.id == participant.id {
                    participant.nickname = value.nickname
                    participant.avatarURL = value.avatarURL
                    participant.remark = value.remark
                }
            }
        }
        self.participantsList.reloadData()
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let profile = self.participants[safe: indexPath.row] {
            switch self.operation {
            case .normal:
                let vc = ComponentsRegister.shared.ContactInfoController.init(profile: profile)
                vc.modalPresentationStyle = .fullScreen
                ControllerStack.toDestination(vc: vc)
            case .mention,.transferOwner:
                self.mentionClosure?(profile)
                self.pop()
            case .manageAdmins:
                self.changeAdmin(profile: profile)
            }
            
        }
    }
}

extension GroupParticipantsController: ThemeSwitchProtocol {
    open func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
    }
}
