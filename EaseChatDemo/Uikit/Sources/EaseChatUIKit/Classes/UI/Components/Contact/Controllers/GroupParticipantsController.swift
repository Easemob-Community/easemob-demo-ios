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
    case addAdmin
}

/// A view controller that displays the participants of a group.
@objcMembers open class GroupParticipantsController: UIViewController {
    
    private var pageSize = UInt(200)
    
    
    private let service: GroupService = ChatUIKitClient.shared.groupService
    
    
    private var adminIds = Set<String>()
    private var adminRequestInFlight = false
    private var canManageAdmins = false
    private let adminAccount = saveIdentifier
    private var ownerProfile: ChatUserProfileProtocol?
    private var adminLoadGeneration = 0
    private var adminSettingsLoaded = false
    private var memberLoadGeneration = 0
    private var adminMemberCursors = Set<String>()
    private let addAdminButton = UIButton(type: .system)
    private let memberSearch = UISearchBar()
    private var memberKeyword = ""
    public var startsSearching = false
    private var isAdminScreen: Bool { self.operation == .manageAdmins || self.operation == .addAdmin }
    private var displayedParticipants: [ChatUserProfileProtocol] {
        guard !self.memberKeyword.isEmpty else { return self.participants }
        return self.participants.filter { $0.id.localizedCaseInsensitiveContains(self.memberKeyword) || $0.nickname.localizedCaseInsensitiveContains(self.memberKeyword) }
    }
    
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
        self.navigation.separateLine.isHidden = self.operation == .manageAdmins
        self.view.addSubViews([self.navigation,self.participantsList])
        // Do any additional setup after loading the view.
        //click of the navigation
        self.navigation.clickClosure = { [weak self] in
            self?.navigationClick(type: $0, indexPath: $1)
        }
        if self.operation != .manageAdmins {
            self.memberSearch.placeholder = "Search".chat.localize
            self.memberSearch.searchBarStyle = .minimal
            self.memberSearch.delegate = self
            self.memberSearch.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: 52)
            if self.operation != .mention { self.participantsList.tableHeaderView = self.memberSearch }
        }
        if self.operation == .manageAdmins {
            self.participantsList.rowHeight = 60
            self.participantsList.sectionHeaderTopPadding = 0
            self.addAdminButton.setTitle("group_admin_settings_entry".chat.localize, for: .normal)
            self.addAdminButton.titleLabel?.font = UIFont.theme.titleMedium
            self.addAdminButton.layer.cornerRadius = 24
            self.addAdminButton.addAction(UIAction { [weak self] _ in self?.openAddAdmin() }, for: .touchUpInside)
            self.view.addSubview(self.addAdminButton)
        }
        if !self.isAdminScreen {
            self.fetchParticipants()
        }
        
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshList), name: Notification.Name(rawValue: cache_update_notification), object: nil)
        self.service.bindGroupEventsListener(listener: self)
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isAdminScreen {
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
            guard self.adminAccount == saveIdentifier else { return }
            self.participants = self.participants.map { self.operation == .mention && $0.id == "All" ? $0 : GroupInfoProfileLoader.profile(userId: $0.id, groupId: self.chatGroup.groupId) }
            if let owner = self.ownerProfile { self.ownerProfile = GroupInfoProfileLoader.profile(userId: owner.id, groupId: self.chatGroup.groupId) }
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
            text = "group_management_title".chat.localize
        case .addAdmin:
            text = "group_admin_settings_entry".chat.localize
        }
        if !self.isAdminScreen, self.participants.count > 0 {
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
        if self.isAdminScreen { self.loadAdminSettings() }
        else { self.loadMembers() }
    }

    private func loadMembers() {
        self.memberLoadGeneration += 1
        let generation = self.memberLoadGeneration
        GroupInfoProfileLoader.memberIds(groupId: self.chatGroup.groupId, service: self.service) { [weak self] ids, error in
            guard let self = self, self.adminAccount == saveIdentifier, generation == self.memberLoadGeneration else { return }
            if let error = error { self.showToast(toast: error.errorDescription ?? ""); return }
            let visibleIds = ids.filter {
                if self.operation == .transferOwner { return $0 != self.chatGroup.owner }
                if self.operation == .mention { return $0 != ChatUIKitContext.shared?.currentUserId }
                return true
            }
            self.participants = visibleIds.map { GroupInfoProfileLoader.profile(userId: $0, groupId: self.chatGroup.groupId) }
            if self.operation == .mention, ids.count >= Appearance.chat.groupParticipantsLimitCount {
                let all = ChatUserProfile(); all.id = "All"; all.nickname = "All"; all.avatarURL = "all"
                self.participants.insert(all, at: 0)
            }
            self.setupTitle()
            self.participantsList.reloadData()
            GroupInfoProfileLoader.resolve(userIds: visibleIds, groupId: self.chatGroup.groupId) { [weak self] profiles in
                guard let self = self, self.adminAccount == saveIdentifier, generation == self.memberLoadGeneration else { return }
                let all = self.participants.first { $0.id == "All" }
                self.participants = profiles
                if let all = all { self.participants.insert(all, at: 0) }
                self.participantsList.reloadData()
            }
        }
    }

    private func loadAdminSettings() {
        self.adminLoadGeneration += 1
        let generation = self.adminLoadGeneration
        self.canManageAdmins = false
        self.adminSettingsLoaded = false
        self.adminMemberCursors.removeAll()
        self.addAdminButton.isEnabled = false
        self.participantsList.reloadData()
        let loading = UIActivityIndicatorView(style: .medium)
        loading.startAnimating()
        self.participantsList.backgroundView = loading
        self.service.fetchGroupInfo(groupId: self.chatGroup.groupId) { [weak self] group, error in
            DispatchQueue.main.async {
                guard let self = self, self.adminAccount == saveIdentifier, generation == self.adminLoadGeneration else { return }
                self.participantsList.backgroundView = nil
                guard error == nil, let group = group else {
                    self.showToast(toast: error?.errorDescription ?? "group_admin_load_failed".chat.localize)
                    return
                }
                self.chatGroup = group
                self.adminIds = Set(group.adminList ?? [])
                self.canManageAdmins = !group.isDisabled && group.owner == ChatUIKitContext.shared?.currentUserId
                self.ownerProfile = self.adminProfile(userId: group.owner ?? "")
                self.adminSettingsLoaded = true
                guard self.canManageAdmins || (self.operation == .manageAdmins && group.permissionType == .admin && !group.isDisabled) else {
                    self.participants.removeAll()
                    self.participantsList.reloadData()
                    self.addAdminButton.isHidden = true
                    self.showToast(toast: "group_admin_owner_only".chat.localize)
                    self.pop()
                    return
                }
                if self.operation == .manageAdmins {
                    self.participants = self.adminIds.sorted().filter { $0 != group.owner }.map { self.adminProfile(userId: $0) }
                    self.refreshAdminDisplay()
                    self.resolveManagementProfiles()
                } else {
                    self.participants.removeAll()
                    self.fetchAdminMemberPage(cursor: "", generation: generation)
                }
            }
        }
    }

    private func adminProfile(userId: String) -> ChatUserProfileProtocol {
        GroupInfoProfileLoader.profile(userId: userId, groupId: self.chatGroup.groupId)
    }

    private func fetchAdminMemberPage(cursor: String, generation: Int) {
        guard self.adminMemberCursors.insert(cursor).inserted else { return }
        self.service.fetchParticipants(groupId: self.chatGroup.groupId, cursor: cursor, pageSize: self.pageSize) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.adminAccount == saveIdentifier, generation == self.adminLoadGeneration else { return }
                if let error = error {
                    self.showToast(toast: error.errorDescription ?? "group_admin_load_failed".chat.localize)
                    return
                }
                var ids = Set(self.participants.map { $0.id })
                for user in result?.list ?? [] {
                    let userId = user as String
                    if userId != self.chatGroup.owner, !self.adminIds.contains(userId), ids.insert(userId).inserted {
                        self.participants.append(self.adminProfile(userId: userId))
                    }
                }
                self.participantsList.reloadData()
                self.setupTitle()
                self.participantsList.layoutIfNeeded()
                self.requestDisplayInfos()
                let next = result?.cursor ?? ""
                if !next.isEmpty, next != cursor {
                    self.fetchAdminMemberPage(cursor: next, generation: generation)
                } else {
                    GroupInfoProfileLoader.resolve(userIds: self.participants.map { $0.id }, groupId: self.chatGroup.groupId) { [weak self] profiles in
                        guard let self = self, self.adminAccount == saveIdentifier, generation == self.adminLoadGeneration else { return }
                        let byId = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                        self.participants = self.participants.map { byId[$0.id] ?? $0 }
                        self.participantsList.reloadData()
                    }
                }
            }
        }
    }

    private func changeAdmin(profile: ChatUserProfileProtocol) {
        guard self.adminAccount == saveIdentifier, self.canManageAdmins,
              !self.adminRequestInFlight, profile.id != self.chatGroup.owner else { return }
        let removing = self.adminIds.contains(profile.id)
        guard self.operation != .addAdmin || !removing else { return }
        let name = profile.nickname.isEmpty ? profile.id : profile.nickname
        let prompt = String(format: (removing ? "group_admin_remove_confirm" : "group_admin_add_confirm").chat.localize, name)
        DialogManager.shared.showAlert(title: prompt, content: "", showCancel: true, showConfirm: true) { [weak self] _ in
            guard let self = self, self.adminAccount == saveIdentifier, self.canManageAdmins,
                  !self.adminRequestInFlight, self.adminIds.contains(profile.id) == removing else { return }
            self.adminRequestInFlight = true
            self.refreshAdminDisplay()
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
                        if self.operation == .addAdmin {
                            self.pop()
                            return
                        }
                        self.participants.removeAll { $0.id == profile.id }
                        self.showToast(toast: "group_admin_removed".chat.localize)
                    }
                    self.refreshAdminDisplay()
                }
            }
            if removing {
                self.service.removeAdmin(userId: profile.id, from: self.chatGroup.groupId, completion: completion)
            } else {
                self.service.addAdmin(userId: profile.id, to: self.chatGroup.groupId, completion: completion)
            }
        }
    }
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if self.startsSearching { self.startsSearching = false; self.memberSearch.becomeFirstResponder() }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottom = self.view.bounds.height - self.view.safeAreaInsets.bottom - 16
        self.addAdminButton.frame = CGRect(x: 16, y: bottom - 48, width: self.view.bounds.width - 32, height: 48)
        let tableBottom = self.operation == .manageAdmins && self.canManageAdmins ? self.addAdminButton.frame.minY - 12 : self.view.bounds.height
        self.participantsList.frame = CGRect(x: 0, y: self.navigation.frame.maxY, width: self.view.bounds.width, height: max(0, tableBottom - self.navigation.frame.maxY))
    }

    private func openAddAdmin() {
        guard self.canManageAdmins, !self.adminRequestInFlight else { return }
        let controller = ComponentsRegister.shared.GroupParticipantController.init(groupId: self.chatGroup.groupId, operation: .addAdmin)
        ControllerStack.toDestination(vc: controller)
    }

    private func refreshAdminDisplay() {
        self.addAdminButton.isHidden = self.operation != .manageAdmins || !self.canManageAdmins
        self.addAdminButton.isEnabled = self.canManageAdmins && !self.adminRequestInFlight
        self.participantsList.reloadData()
        self.view.setNeedsLayout()
        guard self.operation == .manageAdmins, self.adminSettingsLoaded else { return }
        if self.participants.isEmpty {
            self.participantsList.backgroundView = GroupManagementEmptyView(frame: self.participantsList.bounds)
        } else {
            self.participantsList.backgroundView = nil
        }
    }

    private func resolveManagementProfiles() {
        let generation = self.adminLoadGeneration
        let ids = [self.chatGroup.owner ?? ""].filter { !$0.isEmpty } + self.participants.map { $0.id }
        GroupInfoProfileLoader.resolve(userIds: ids, groupId: self.chatGroup.groupId) { [weak self] profiles in
            guard let self = self, self.adminAccount == saveIdentifier else { return }
            guard generation == self.adminLoadGeneration else { return }
            self.ownerProfile = profiles.first { $0.id == self.chatGroup.owner } ?? self.ownerProfile
            let byId = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            self.participants = self.participants.map { byId[$0.id] ?? $0 }
            self.participantsList.reloadData()
        }
    }

    private func ownerTransferImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            UIColor.black.setStroke()
            let head = UIBezierPath(ovalIn: CGRect(x: 5, y: 2, width: 7, height: 7))
            head.lineWidth = 1.8
            head.stroke()
            let body = UIBezierPath()
            body.lineWidth = 1.8
            body.lineCapStyle = .round
            body.lineJoinStyle = .round
            body.move(to: CGPoint(x: 2, y: 22))
            body.addLine(to: CGPoint(x: 2, y: 18))
            body.addQuadCurve(to: CGPoint(x: 15, y: 18), controlPoint: CGPoint(x: 8.5, y: 9))
            body.addLine(to: CGPoint(x: 15, y: 22))
            body.move(to: CGPoint(x: 16, y: 7))
            body.addLine(to: CGPoint(x: 22, y: 7))
            body.addLine(to: CGPoint(x: 20, y: 5))
            body.move(to: CGPoint(x: 22, y: 11))
            body.addLine(to: CGPoint(x: 16, y: 11))
            body.addLine(to: CGPoint(x: 18, y: 13))
            body.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }

    private func beginOwnerTransfer() {
        guard self.canManageAdmins, !self.adminRequestInFlight else { return }
        let controller = ComponentsRegister.shared.GroupParticipantController.init(groupId: self.chatGroup.groupId, operation: .transferOwner)
        controller.mentionClosure = { [weak self] profile in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.confirmOwnerTransfer(profile: profile)
            }
        }
        ControllerStack.toDestination(vc: controller)
    }

    private func confirmOwnerTransfer(profile: ChatUserProfileProtocol) {
        guard self.adminAccount == saveIdentifier, self.canManageAdmins, !self.adminRequestInFlight, profile.id != self.chatGroup.owner else { return }
        let name = profile.nickname.isEmpty ? profile.id : profile.nickname
        DialogManager.shared.showAlert(title: String(format: "group_management_transfer_confirm".chat.localize, name), content: "", showCancel: true, showConfirm: true) { [weak self] _ in
            guard let self = self, self.adminAccount == saveIdentifier, self.canManageAdmins, !self.adminRequestInFlight else { return }
            self.adminRequestInFlight = true
            self.refreshAdminDisplay()
            self.service.transfer(groupId: self.chatGroup.groupId, userId: profile.id) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self = self, self.adminAccount == saveIdentifier else { return }
                    self.adminRequestInFlight = false
                    if let error = error { self.showToast(toast: error.errorDescription ?? "group_admin_update_failed".chat.localize) }
                    else { self.showToast(toast: "group_management_transfer_success".chat.localize) }
                    self.loadAdminSettings()
                }
            }
        }
    }

}

extension GroupParticipantsController: GroupServiceListener {
    public func onAttributesChangedOfGroupMember(groupId: String, userId: String, operatorId: String, attributes: [String: String]) {
        guard groupId == self.chatGroup.groupId, self.adminAccount == saveIdentifier else { return }
        self.refreshList()
    }

    public func onGroupAdminUpdated(groupId: String, userId: String, added: Bool) {
        guard self.isAdminScreen, self.adminAccount == saveIdentifier, groupId == self.chatGroup.groupId else { return }
        DispatchQueue.main.async {
            guard self.adminAccount == saveIdentifier else { return }
            if userId == ChatUIKitContext.shared?.currentUserId { self.loadAdminSettings(); return }
            if added { self.adminIds.insert(userId) } else { self.adminIds.remove(userId) }
            if self.operation == .manageAdmins {
                if added, !self.participants.contains(where: { $0.id == userId }) { self.participants.append(self.adminProfile(userId: userId)) }
                if !added { self.participants.removeAll { $0.id == userId } }
                self.resolveManagementProfiles()
                self.refreshAdminDisplay()
            } else {
                self.participants.removeAll { self.adminIds.contains($0.id) }
                self.participantsList.reloadData()
            }
        }
    }
    public func onGroupOwnerUpdated(groupId: String, ownerId: String, userId: String) {
        guard self.isAdminScreen, self.adminAccount == saveIdentifier, groupId == self.chatGroup.groupId else { return }
        DispatchQueue.main.async {
            guard self.adminAccount == saveIdentifier else { return }
            self.loadAdminSettings()
        }
    }
}


extension GroupParticipantsController: UITableViewDelegate,UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.operation == .manageAdmins && section == 0 ? (self.ownerProfile == nil ? 0 : 1) : self.displayedParticipants.count
    }

    public func numberOfSections(in tableView: UITableView) -> Int { self.operation == .manageAdmins ? 2 : 1 }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        self.operation == .manageAdmins ? 32 : 0
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard self.operation == .manageAdmins else { return nil }
        let label = UILabel(frame: CGRect(x: 16, y: 4, width: tableView.bounds.width - 32, height: 24))
        label.text = (section == 0 ? "group_management_owner" : "group_management_admins").chat.localize
        label.font = UIFont.theme.labelMedium
        label.textColor = Theme.style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
        let header = UIView()
        header.backgroundColor = self.view.backgroundColor
        header.addSubview(label)
        return header
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        self.cellForRowAt(indexPath: indexPath)
    }
    
    @objc open func cellForRowAt(indexPath: IndexPath) -> UITableViewCell {
        let identifier = self.operation == .manageAdmins ? "GroupManagementMemberCell" : "GroupParticipantCell"
        var cell = self.participantsList.dequeueReusableCell(withIdentifier: identifier) as? GroupParticipantCell
        if cell == nil {
            cell = self.operation == .manageAdmins ? GroupManagementMemberCell(displayStyle: .normal, identifier: identifier) : GroupParticipantCell(displayStyle: .normal, identifier: identifier)
        }
        let profile = self.operation == .manageAdmins && indexPath.section == 0 ? self.ownerProfile : self.displayedParticipants[safe: indexPath.row]
        if let profile = profile {
            cell?.refresh(profile: profile, keyword: self.memberKeyword)
            cell?.avatar.layer.cornerRadius = 20
            if self.operation == .manageAdmins && self.canManageAdmins {
                let transferring = indexPath.section == 0
                let button = UIButton(type: .system)
                button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                button.setImage(transferring ? self.ownerTransferImage() : UIImage(chatNamed: "members_remove"), for: .normal)
                button.tintColor = Theme.style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
                button.accessibilityLabel = (transferring ? "group_details_extend_button_transfer" : "group_admin_remove_action").chat.localize
                button.isEnabled = !self.adminRequestInFlight
                button.addAction(UIAction { [weak self] _ in
                    if transferring { self?.beginOwnerTransfer() } else { self?.changeAdmin(profile: profile) }
                }, for: .touchUpInside)
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
                if let nickName = self.displayedParticipants[safe: indexPath.row]?.nickname,nickName.isEmpty {
                    if let unknownId = self.displayedParticipants[safe: indexPath.row]?.id {
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
                    let display = GroupMemberAttributesCache.shared.displayProfile(groupId: self.chatGroup.groupId, profile: value)
                    participant.nickname = display.nickname
                    participant.avatarURL = display.avatarURL
                    participant.remark = display.remark
                }
            }
        }
        self.participantsList.reloadData()
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard self.operation != .manageAdmins else { return }
        if let profile = self.displayedParticipants[safe: indexPath.row] {
            switch self.operation {
            case .normal:
                let vc = ComponentsRegister.shared.ContactInfoController.init(profile: profile)
                vc.modalPresentationStyle = .fullScreen
                ControllerStack.toDestination(vc: vc)
            case .mention,.transferOwner:
                self.mentionClosure?(profile)
                self.pop()
            case .manageAdmins:
                break
            case .addAdmin:
                self.changeAdmin(profile: profile)
            }
            
        }
    }
}

extension GroupParticipantsController: ThemeSwitchProtocol {
    open func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
        self.addAdminButton.backgroundColor = style == .dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor95
        self.addAdminButton.setTitleColor(style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1, for: .normal)
        self.memberSearch.overrideUserInterfaceStyle = style == .dark ? .dark : .light
        self.participantsList.reloadData()
        if self.isAdminScreen, self.adminSettingsLoaded { self.refreshAdminDisplay() }
    }
}


extension GroupParticipantsController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.memberKeyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.participantsList.reloadData()
    }
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}

private final class GroupManagementEmptyView: UIView {
    private let image = UIImageView(image: UIImage(chatNamed: "empty"))
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.image.contentMode = .scaleAspectFit
        self.label.text = "group_management_no_admins".chat.localize
        self.label.font = UIFont.theme.bodyMedium
        self.label.textColor = Theme.style == .dark ? UIColor.theme.neutralColor4 : UIColor.theme.neutralColor7
        self.label.textAlignment = .center
        self.addSubViews([self.image, self.label])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        self.image.frame = CGRect(x: (self.bounds.width - 108) / 2, y: max(130, self.bounds.height / 2 - 50), width: 108, height: 108)
        self.label.frame = CGRect(x: 16, y: self.image.frame.maxY + 12, width: self.bounds.width - 32, height: 22)
    }
}

private final class GroupManagementMemberCell: GroupParticipantCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        self.separatorLine.frame.size.width = self.bounds.width - self.separatorLine.frame.minX
    }
}
