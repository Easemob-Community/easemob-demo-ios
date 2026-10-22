//
//  GroupInfoViewController.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/24.
//

import UIKit

@objc open class GroupInfoViewController: UIViewController {
    
    /**
     A private variable that represents the index path for editing.
     */
    private var editIndex = IndexPath(row: 1, section: 0)
    private var groupAnnouncement = ""
    private var groupAlias = ""
    private var memberPreviewGeneration = 0
    private var pendingSwitches = Set<String>()
    private let account = saveIdentifier

    private var isOwner: Bool { self.chatGroup.owner == ChatUIKitContext.shared?.currentUserId }
    private var isManager: Bool { self.isOwner || self.chatGroup.permissionType == .admin }

    
    public var chatGroup = ChatGroup()
    
    public private(set) var service: GroupService = ChatUIKitClient.shared.groupService
    
    public private(set) var conversationService = ConversationServiceImplement()
    
    /**
     A private array of `ActionSheetItem` objects representing the owner options in the group info view controller.
     Each `ActionSheetItem` contains a title, type, and tag.

     Example usage:
     ```
     private var ownerOptions = [
         ActionSheetItem(title: "group_details_extend_button_disband".chat.localize, type: .destructive, tag: "disband_group"),
         ActionSheetItem(title: "group_details_extend_button_transfer".chat.localize, type: .destructive, tag: "transfer_owner")
     ]
     ```
     */
    public var ownerOptions = [ActionSheetItem(title: "group_details_extend_button_disband".chat.localize, type: .destructive, tag: "disband_group")]
    
    /**
     A private array that stores the member options for the group.

     Each member option is represented by an `ActionSheetItem` object, which contains the title, type, and tag of the option.

     Example usage:
     ```
     private var memberOptions = [ActionSheetItem(title: "group_details_extend_button_leave".chat.localize, type: .destructive, tag: "quit_group")]
     ```
     */
    public var memberOptions = [ActionSheetItem(title: "group_details_extend_button_leave".chat.localize, type: .destructive, tag: "quit_group")]
    
    public private(set) lazy var navigation: ChatNavigationBar = {
        self.createNavigation()
    }()
    
    /**
     Creates and returns a navigation bar for the GroupInfoViewController.

     - Returns: An instance of EaseChatNavigationBar.
     */
    @objc open func createNavigation() -> ChatNavigationBar {
        ChatNavigationBar(showLeftItem: true, textAlignment: .left, rightImages: self.chatGroup.isDisabled ? []:[UIImage(chatNamed: "more_detail")!] ,hiddenAvatar: true).backgroundColor(.clear)
    }
    
    public var isConversationMuted: Bool {
        (ChatClient.shared().chatManager?.getConversationWithConvId(self.chatGroup.groupId)?.disturbType ?? .all) != .all
    }
    
    public private(set) lazy var datas: [[DetailInfo]] = self.fillDatas()

    @objc open func fillDatas() -> [[DetailInfo]] {
        func row(_ key: String, _ detail: String = "", toggle: Bool? = nil) -> DetailInfo {
            let info = DetailInfo()
            info.title = key.chat.localize
            info.detail = detail
            info.withSwitch = toggle != nil
            info.switchValue = toggle ?? false
            return info
        }
        var information = [row("group_details_id", self.chatGroup.groupId ?? ""),
                           row("group_details_button_name", self.chatGroup.groupName ?? ""),
                           row("group_details_button_announcement", self.groupAnnouncement),
                           row("group_details_button_alias", self.groupAlias)]
        if self.isManager, !self.chatGroup.isDisabled {
            information.append(row("group_management_title"))
        }
        var switches = [row("contact_details_switch_donotdisturb", toggle: self.isConversationMuted),
                        row("group_details_pin", toggle: ChatClient.shared().chatManager?.getConversationWithConvId(self.chatGroup.groupId)?.isPinned ?? false)]
        if self.isOwner, !self.chatGroup.settings.isPublic, !self.chatGroup.isDisabled {
            switches.append(row("group_details_allow_invites", toggle: self.chatGroup.settings.allowInvites))
        }
        return [information, [row("group_details_search_history")], switches, [row("contact_details_button_clearchathistory")]]
    }

    @objc open func refreshManagementItems() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.account == saveIdentifier else { return }
            self.datas = self.fillDatas()
            self.menuList.reloadData()
            if self.isViewLoaded { self.loadMemberPreview() }
        }
    }

    public private(set) lazy var header: DetailInfoHeader = {
        self.createDetailHeader()
    }()
    
    /// Creates a detail header view for the group info.
    /// - Returns: A `DetailInfoHeader` instance.
    @objc open func createDetailHeader() -> DetailInfoHeader {
        let header = GroupDetailsMembersHeader(frame: CGRect(x: 0, y: 0, width: self.view.frame.width, height: 200), showMenu: false, placeHolder: nil)
        header.showMembers = { [weak self] in self?.openMembers(search: false) }
        header.searchMembers = { [weak self] in self?.openMembers(search: true) }
        header.addMembers = { [weak self] in self?.changeMembers(removing: false) }
        header.removeMembers = { [weak self] in self?.changeMembers(removing: true) }
        header.showProfile = { profile in
            ControllerStack.toDestination(vc: ComponentsRegister.shared.ContactInfoController.init(profile: profile))
        }
        return header
    }
    
    public private(set) lazy var menuList: UITableView = {
        UITableView(frame: CGRect(x: 0, y: NavigationHeight, width: self.view.frame.width, height: self.view.frame.height), style: .plain).delegate(self).dataSource(self).tableFooterView(UIView()).rowHeight(54).tableHeaderView(self.header).backgroundColor(.clear)
    }()
    
    /// A closure that is executed when the group name is changed.
    @objc public var nameClosure: ((String,String) -> Void)?
    
    /// Initializes a new GroupInfoViewController with the specified group id.
    @objc required public init(group: String,nameChanged: @escaping (String,String) -> Void) {
        self.nameClosure = nameChanged
        self.chatGroup = ChatGroup(id: group)
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /**
     Fetches the group information for a given group ID.
     
     - Parameters:
        - groupId: The ID of the group to fetch information for.
     */
    @objc open func fetchGroupInfo(groupId: String) {
        self.service.fetchGroupInfo(groupId: groupId) { [weak self] group, error in
            DispatchQueue.main.async {
                guard let self = self, self.account == saveIdentifier else { return }
                if let group = group, error == nil {
                    self.chatGroup = group
                    let profile = ChatUserProfile()
                    profile.id = groupId
                    profile.nickname = group.groupName ?? ""
                    profile.avatarURL = group.settings.ext ?? ""
                    ChatUIKitContext.shared?.updateCache(type: .group, profile: profile)
                } else if let error = error {
                    self.showToast(toast: error.errorDescription ?? "group_admin_load_failed".chat.localize)
                }
                self.refreshManagementItems()
            }
        }
        self.service.getAnnouncement(groupId: groupId) { [weak self] text, error in
            DispatchQueue.main.async {
                guard let self = self, self.account == saveIdentifier, error == nil else { return }
                self.groupAnnouncement = text ?? ""
                self.datas = self.fillDatas()
                self.menuList.reloadData()
            }
        }
        self.service.fetchMemberAttribute(groupId: groupId, userId: ChatUIKitContext.shared?.currentUserId ?? "") { [weak self] error, attributes in
            DispatchQueue.main.async {
                guard let self = self, self.account == saveIdentifier, error == nil else { return }
                self.fillAlias(nickname: attributes?["nickName"] ?? "")
            }
        }
    }

    /**
     Fills the alias (nickname) for the group details button.
     
     - Parameters:
        - nickname: The nickname to be filled as the alias.
     */
    @objc open func fillAlias(nickname: String) {
        self.groupAlias = nickname
        self.datas = self.fillDatas()
        self.menuList.reloadData()
    }

    /**
     Updates the user state in the group info view controller.
     
     - Parameters:
        - state: The new user state.
     */
    @MainActor @objc public func updateUserState(state: UserState) {
        self.header.userState = state
    }
    

    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.fetchGroupInfo(groupId: self.chatGroup.groupId)
        self.menuList.reloadData()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.theme.neutralColor98
        self.view.addSubViews([self.navigation,self.menuList])
        // Do any additional setup after loading the view.
        //click of the navigation
        self.refreshManagementItems()
        self.navigation.clickClosure = { [weak self] in
            self?.navigationClick(type: $0, indexPath: $1)
        }
        self.navigation.title = "group_details_title".chat.localize
        self.navigation.separateLine.isHidden = true
        self.menuList.separatorStyle = .none
        self.menuList.contentInsetAdjustmentBehavior = .never
        self.service.bindGroupEventsListener(listener: self)
        self.headerActions()
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
        
    }
    
    /**
     This method is responsible for handling the header actions in the GroupInfoViewController.
     It checks if there is a chat action item available in the contact's detail extension action items.
     If found, it sets the action closure to invoke the `alreadyChat()` method when the action is triggered.

     - Note: The `alreadyChat()` method is called with a weak reference to `self` to avoid potential retain cycles.
     */
    @objc open func headerActions() {
        if let chat = Appearance.contact.detailExtensionActionItems.first(where: { $0.featureIdentify == "Chat" }) {
            chat.actionClosure = { [weak self] in
                self?.processHeaderActionEvents(item: $0)
            }
        }
        if let search = Appearance.contact.detailExtensionActionItems.first(where: { $0.featureIdentify == "SearchMessages" }) {
            search.actionClosure = { [weak self] in
                self?.processHeaderActionEvents(item: $0)
            }
        }
    }
    
    @objc open func processHeaderActionEvents(item: ContactListHeaderItemProtocol) {
        switch item.featureIdentify {
        case "Chat": self.alreadyChat()
//        case "AudioCall":
//        case "VideoCall":
        case "SearchMessages": self.searchHistoryMessages()
        default: break
        }
    }
    
    @objc open func searchHistoryMessages() {
        let vc = SearchHistoryMessagesViewController(conversationId: self.chatGroup.groupId) { message in
            
        }
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    /**
     Handles the navigation click events in the GroupInfoViewController.
     
     - Parameters:
        - type: The type of navigation click event.
        - indexPath: The optional index path associated with the event.
     */
    @objc open func navigationClick(type: ChatNavigationBarClickEvent, indexPath: IndexPath?) {
        switch type {
        case .back: self.pop()
        case .rightItems: self.rightActions(indexPath: indexPath ?? IndexPath())
        default:
            break
        }
    }
    
    /**
     Opens the chat conversation for the current group.
     
     This method is called when the user wants to open the chat conversation for the current group. It performs the following steps:
     1. Acknowledges the conversation read by calling `ackConversationRead` method of the shared `ChatClient` instance.
     2. Checks if the previous view controller in the navigation stack is `MessageListController`.
         - If it is, pops to the view controller before that and then pushes a new instance of `ComponentsRegister.shared.MessageViewController` with the conversation ID and chat type set to `.group`.
         - If it is not, directly pushes a new instance of `ComponentsRegister.shared.MessageViewController` with the conversation ID and chat type set to `.group`.
     3. If the navigation stack is empty, checks if the presenting view controller is `MessageListController`.
         - If it is, dismisses the presenting view controller and then presents a new instance of `ComponentsRegister.shared.MessageViewController` with the conversation ID and chat type set to `.group`.
         - If it is not, presents a new instance of `ComponentsRegister.shared.MessageViewController` with the conversation ID and chat type set to `.group` using the full screen modal presentation style.
     4. If there is no presenting view controller, creates a new instance of `ComponentsRegister.shared.MessageViewController` with the conversation ID and chat type set to `.group` and navigates to it using `ControllerStack.toDestination` method.
     */
    @objc open func alreadyChat() {
        ChatClient.shared().chatManager?.clearConversationUnreadMessageCount(self.chatGroup.groupId) { error in
            consoleLogInfo("ackConversationRead error:\(error?.errorDescription ?? "")", type: .error)
        }
        if let count = self.navigationController?.viewControllers.count {
            if self.navigationController?.viewControllers[safe: count - 2] is MessageListController {
                if let root = self.navigationController?.viewControllers[safe: count - 3] {
                    self.navigationController?.popToViewController(root, animated: true)
                    let vc = ComponentsRegister.shared.MessageViewController.init(conversationId: self.chatGroup.groupId,chatType: .group)
                    vc.modalPresentationStyle = .fullScreen
                    ControllerStack.toDestination(vc: vc)
                }
            } else {
                let vc = ComponentsRegister.shared.MessageViewController.init(conversationId: self.chatGroup.groupId,chatType: .group)
                vc.modalPresentationStyle = .fullScreen
                ControllerStack.toDestination(vc: vc)
            }
        } else {
            if let presentingVC = self.presentingViewController {
                if presentingVC is MessageListController {
                    self.dismiss(animated: false) {
                        presentingVC.dismiss(animated: false) {
                            let vc = ComponentsRegister.shared.MessageViewController.init(conversationId: self.chatGroup.groupId,chatType: .group)
                            vc.modalPresentationStyle = .fullScreen
                            UIViewController.currentController?.present(vc, animated: true)
                        }
                    }
                } else {
                    let vc = ComponentsRegister.shared.MessageViewController.init(conversationId: self.chatGroup.groupId,chatType: .group)
                    vc.modalPresentationStyle = .fullScreen
                    self.present(vc, animated: true)
                }
            } else {
                let desiredViewController = ComponentsRegister.shared.MessageViewController.init(conversationId: self.chatGroup.groupId,chatType: .group)
                desiredViewController.modalPresentationStyle = .fullScreen
                ControllerStack.toDestination(vc: desiredViewController)
            }
            
        }
    }
    
    /**
     Pops the current view controller from the navigation stack or dismisses it if there is no navigation controller.

     - Note: If the view controller is embedded in a navigation controller, it will be popped from the navigation stack with animation. If there is no navigation controller, the view controller will be dismissed with animation.
     */
    @objc open func pop() {
        if self.navigationController != nil {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true)
        }
    }

    /**
     Handles the right actions for a given indexPath in the GroupInfoViewController.
     
     - Parameters:
         - indexPath: The index path of the selected row.
     */
    @objc open func rightActions(indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            DialogManager.shared.showActions(actions: self.chatGroup.permissionType == .owner ? self.ownerOptions:self.memberOptions) { [weak self] item in
                guard let `self` = self else { return }
                switch item.tag {
                case "disband_group": self.disband()
                case "transfer_owner": self.transfer()
                case "quit_group": self.leave()
                default:
                    break
                }
            }
        default:
            break
        }
    }
    
    /**
     Disbands the group.
     This method shows an alert to confirm the disbanding of the group. If the user confirms, it calls the `disband` method of the `service` object to disband the group. After successful disbanding, it posts a notification with the group ID and pops the current view controller from the navigation stack. If there is an error during the disbanding process, it logs the error message.
     */
    @objc open func disband() {
        DialogManager.shared.showAlert(title: "group_details_extend_button_disband_alert_title".chat.localize, content: "group_details_extend_button_disband_alert_subtitle".chat.localize, showCancel: true, showConfirm: true) { [weak self] _ in
            self?.disbandRequest()
        }
        
    }
    
    @objc open func disbandRequest() {
        self.service.disband(groupId: self.chatGroup.groupId) { [weak self] error in
            guard let `self` = self else { return }
            if error == nil {
                NotificationCenter.default.post(name: Notification.Name("EaseChatUIKit_leaveGroup"), object: self.chatGroup.groupId)
                self.pop()
            } else {
                consoleLogInfo("disband error:\(error?.errorDescription ?? "")", type: .error)
            }
        }
    }
    
    /**
     Transfers the ownership of the group to another participant.
     */
    @objc open func transfer() {
        let vc =
        ComponentsRegister.shared.GroupParticipantController.init(groupId: self.chatGroup.groupId, operation: .transferOwner)
        vc.mentionClosure = { [weak self] in
            guard let `self` = self else { return }
            self.transferConfirm(profile: $0)
        }
        if vc.presentingViewController != nil {
            vc.modalPresentationStyle = .fullScreen
        }
        ControllerStack.toDestination(vc: vc)
    }
    
    private func transferConfirm(profile: ChatUserProfileProtocol) {
        var user = ChatUIKitContext.shared?.userCache?[profile.id]
        if user == nil {
            user = ChatUIKitContext.shared?.chatCache?[profile.id]
        }
        var nickname = user?.remark ?? ""
        if nickname.isEmpty {
            nickname = user?.nickname ?? ""
        }
        if nickname.isEmpty {
            nickname = profile.id
        }
        DialogManager.shared.showAlert(title: "", content: "group_details_extend_button_transfer".chat.localize+" to ".chat.localize+"\(nickname)?", showCancel: true, showConfirm: true) { [weak self] text in
            guard let `self` = self else { return }
            self.service.transfer(groupId: self.chatGroup.groupId, userId: profile.id, completion: { [weak self] group, error in
                guard let `self` = self else { return }
                if error == nil {
                    self.datas.removeLast()
                    self.menuList.reloadData()
                    NotificationCenter.default.post(name: Notification.Name("EaseChatUIKit_leaveGroup"), object: profile.id)
                    DispatchQueue.main.asyncAfter(wallDeadline: .now()+0.5) {
                        self.pop()
                    }
                } else {
                    consoleLogInfo("transfer owner error:\(error?.errorDescription ?? "")", type: .error)
                }
            })
        }
    }
    
    /**
     Method to leave the group.
     
     This method displays an alert to confirm leaving the group. If the user confirms, it calls the `leave` method of the `service` object to leave the group. If leaving the group is successful, it pops the current view controller. Otherwise, it logs an error message.
     */
    @objc open func leave() {
        DialogManager.shared.showAlert(title: "group_details_extend_button_leave_alert_title".chat.localize, content: "group_details_extend_button_leave_alert_subtilte".chat.localize, showCancel: true, showConfirm: true) { [weak self] _ in
            self?.service.leave(groupId: self?.chatGroup.groupId ?? "") { error in
                if error == nil {
                    NotificationCenter.default.post(name: Notification.Name("EaseChatUIKit_leaveGroup"), object: self?.chatGroup.groupId ?? "")
                    self?.pop()
                } else {
                    consoleLogInfo("disband error:\(error?.errorDescription ?? "")", type: .error)
                }
            }
        }
        
    }

    deinit { self.service.unbindGroupEventsListener(listener: self) }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.menuList.frame = CGRect(x: 0, y: self.navigation.frame.maxY, width: self.view.bounds.width,
                                     height: self.view.bounds.height - self.navigation.frame.maxY)
        if let header = self.header as? GroupDetailsMembersHeader {
            header.frame.size = CGSize(width: self.menuList.bounds.width, height: header.contentHeight)
            if self.menuList.tableHeaderView?.frame.height != header.contentHeight { self.menuList.tableHeaderView = header }
        }
    }

    private func loadMemberPreview() {
        self.memberPreviewGeneration += 1
        let generation = self.memberPreviewGeneration
        let groupId = self.chatGroup.groupId ?? ""
        self.service.fetchParticipants(groupId: groupId, cursor: "", pageSize: 10) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.account == saveIdentifier, generation == self.memberPreviewGeneration else { return }
                var ids = ([self.chatGroup.owner ?? ""] + (self.chatGroup.adminList ?? [])).filter { !$0.isEmpty }
                for id in result?.list ?? [] where !ids.contains(id as String) { ids.append(id as String) }
                ids = Array(ids.prefix(10))
                self.updateMemberPreview(profiles: ids.map { GroupInfoProfileLoader.profile(userId: $0, groupId: self.chatGroup.groupId) })
                GroupInfoProfileLoader.resolve(userIds: ids, groupId: self.chatGroup.groupId) { [weak self] profiles in
                    guard let self = self, self.account == saveIdentifier, generation == self.memberPreviewGeneration else { return }
                    self.updateMemberPreview(profiles: profiles)
                }
                if let error = error { consoleLogInfo("group preview: \(error.errorDescription ?? "")", type: .error) }
            }
        }
    }

    private func updateMemberPreview(profiles: [ChatUserProfileProtocol]) {
        guard let header = self.header as? GroupDetailsMembersHeader else { return }
        let canInvite = !self.chatGroup.isDisabled && (self.isManager || (!self.chatGroup.settings.isPublic && self.chatGroup.settings.allowInvites))
        header.configure(profiles: profiles, canInvite: canInvite, canRemove: self.isManager && !self.chatGroup.isDisabled)
        header.frame.size.height = header.contentHeight
        self.menuList.tableHeaderView = header
    }

    private func openMembers(search: Bool) {
        let controller = ComponentsRegister.shared.GroupParticipantController.init(groupId: self.chatGroup.groupId)
        controller.startsSearching = search
        ControllerStack.toDestination(vc: controller)
    }

    private func changeMembers(removing: Bool) {
        guard !self.chatGroup.isDisabled else { return }
        guard removing ? self.isManager : (self.isManager || (!self.chatGroup.settings.isPublic && self.chatGroup.settings.allowInvites)) else { return }
        GroupInfoProfileLoader.memberIds(groupId: self.chatGroup.groupId, service: self.service) { [weak self] ids, error in
            guard let self = self, self.account == saveIdentifier else { return }
            if let error = error { self.showToast(toast: error.errorDescription ?? ""); return }
            if removing {
                let profiles = ids.filter { $0 != self.chatGroup.owner && !(self.chatGroup.permissionType == .admin && (self.chatGroup.adminList ?? []).contains($0)) }.map { GroupInfoProfileLoader.profile(userId: $0, groupId: self.chatGroup.groupId) }
                let controller = ComponentsRegister.shared.RemoveGroupParticipantController.init(group: self.chatGroup, profiles: profiles) { [weak self] _ in
                    guard let self = self else { return }
                    self.fetchGroupInfo(groupId: self.chatGroup.groupId)
                }
                ControllerStack.toDestination(vc: controller)
            } else {
                let controller = ComponentsRegister.shared.ContactsController.init(headerStyle: .addGroupParticipant, ignoreIds: ids)
                controller.confirmClosure = { [weak self, weak controller] users in
                    guard let self = self, self.account == saveIdentifier else { return }
                    self.service.invite(userIds: users.map { $0.id }, to: self.chatGroup.groupId, message: "") { [weak self, weak controller] _, error in
                        DispatchQueue.main.async {
                            guard let self = self, self.account == saveIdentifier else { return }
                            if let error = error { self.showToast(toast: error.errorDescription ?? ""); return }
                            if let controller = controller { controller.navigationController?.popViewController(animated: true) }
                            self.fetchGroupInfo(groupId: self.chatGroup.groupId)
                        }
                    }
                }
                ControllerStack.toDestination(vc: controller)
            }
        }
    }

}


extension GroupInfoViewController: UITableViewDelegate,UITableViewDataSource {
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        self.datas.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.datas[safe: section]?.count ?? 0
    }
    
    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section < self.datas.count - 1 ? 12 : 0
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footer = UIView()
        footer.backgroundColor = Theme.style == .dark ? UIColor.theme.neutralColor0 : UIColor.theme.neutralColor95
        return footer
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        self.datas[indexPath.section][indexPath.row].title == "group_details_button_announcement".chat.localize ? 76 : 54
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        self.cellForRowAt(indexPath: indexPath)
    }
    
    /**
     Returns a table view cell for the specified index path.

     - Parameters:
        - indexPath: The index path of the cell.

     - Returns: A table view cell for the specified index path.
     */
    @objc open func cellForRowAt(indexPath: IndexPath) -> UITableViewCell {
        let cell = self.menuList.dequeueReusableCell(withIdentifier: "GroupDetailsRowCell") as? GroupDetailsRowCell
            ?? GroupDetailsRowCell(style: .default, reuseIdentifier: "GroupDetailsRowCell")
        let info = self.datas[indexPath.section][indexPath.row]
        cell.configure(info: info)
        cell.toggle.isEnabled = !self.chatGroup.isDisabled && !self.pendingSwitches.contains(info.title)
        cell.toggleChanged = { [weak self] value in self?.switchChanged(isOn: value, indexPath: indexPath) }
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.didSelectRowAt(indexPath: indexPath)
    }

    /**
     Handles the selection of a table view cell at a specific index path.
     
     - Parameters:
         - indexPath: The index path of the selected cell.
     */
    @objc open func didSelectRowAt(indexPath: IndexPath) {
        if let info = self.datas[safe: indexPath.section]?[safe: indexPath.row] {
            self.editIndex = indexPath
            switch info.title {
            case "group_details_id".chat.localize:
                UIPasteboard.general.string = self.chatGroup.groupId
                self.showToast(toast: "Copied".chat.localize)
            case "group_details_button_name".chat.localize: self.edit(type: .name, detail: info.detail)
            case "group_details_button_alias".chat.localize: self.edit(type: .alias, detail: info.detail)
            case "group_details_button_announcement".chat.localize: self.edit(type: .announcement, detail: info.detail)
            case "group_details_button_members".chat.localize: self.viewParticipants()
            case "group_management_title".chat.localize: self.viewAdministrators()
            case "group_details_button_description".chat.localize: self.edit(type: .description, detail: info.detail)
            case "group_details_search_history".chat.localize: self.searchHistoryMessages()
            case "contact_details_button_clearchathistory".chat.localize: self.cleanHistoryMessages()
            default: break
            }
        }
    }
    
    /// Opens the view to display the participants of the chat group.
    @objc open func viewParticipants() {
        let vc = ComponentsRegister.shared.GroupParticipantController.init(groupId: self.chatGroup.groupId)
        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
    }

    @objc open func viewAdministrators() {
        guard !self.chatGroup.isDisabled,
              self.isManager else { return }
        let vc = ComponentsRegister.shared.GroupParticipantController.init(groupId: self.chatGroup.groupId, operation: .manageAdmins)
        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
    }
    
    /**
     Cleans the history messages of the group.
     */
    @objc open func cleanHistoryMessages() {
        DialogManager.shared.showAlert(title: "group_details_button_clearchathistory".chat.localize, content: "", showCancel: true, showConfirm: true) { [weak self] _ in
            guard let `self` = self else { return }
            ChatClient.shared().chatManager?.getConversationWithConvId(self.chatGroup.groupId)?.deleteAllMessages(nil)
            NotificationCenter.default.post(name: Notification.Name("EaseChatUIKit_clean_history_messages"), object: self.chatGroup.groupId)
        }
        
    }
    
    /**
     Opens the edit view for the group information.
     
     - Parameters:
        - type: The type of information to edit.
        - detail: The current detail of the information being edited.
     */
    @objc open func edit(type: GroupInfoEditType, detail: String) {
        // Check if the group is disabled
        if self.chatGroup.isDisabled {
            DialogManager.shared.showAlert(title: "Group was disabled".chat.localize, content: "", showCancel: false, showConfirm: true) { _ in
                
            }
            return
        }
        
        // Create an instance of GroupInfoEditViewController
        let vc = GroupInfoEditViewController(groupId: self.chatGroup.groupId, type: type, rawText: detail) { [weak self] result in
            self?.handleEditCallback(text: result, type: type)
        }
        
        vc.editable = type == .alias || self.isOwner || (type == .announcement && self.isManager)
        // Push the edit view controller to the navigation stack
        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
    }
    
    /**
     Handles the callback for editing group information.
     
     - Parameters:
        - text: The edited text.
        - type: The type of information being edited.
     */
    @objc open func handleEditCallback(text: String, type: GroupInfoEditType) {
        guard self.account == saveIdentifier else { return }
        if type == .name {
            self.nameClosure?(self.chatGroup.groupId, text)
            if let profile = ChatUIKitContext.shared?.groupCache?[self.chatGroup.groupId] {
                profile.nickname = text
                ChatUIKitContext.shared?.updateCache(type: .group, profile: profile)
            } else {
                let profile = ChatUserProfile()
                profile.id = self.chatGroup.groupId
                profile.nickname = text
                profile.avatarURL = self.chatGroup.settings.ext
                ChatUIKitContext.shared?.updateCache(type: .group, profile: profile)
            }
            ChatUIKitContext.shared?.onGroupNameUpdated?(self.chatGroup.groupId, text)
            self.header.nickName.text = text
        }
        if type == .alias { self.groupAlias = text }
        if type == .announcement { self.groupAnnouncement = text }
        self.datas = self.fillDatas()
        self.menuList.reloadData()
    }
    
    /**
        This method is called when the switch is changed in the GroupInfoViewController.
        
        - Parameters:
            - isOn: A boolean value indicating whether the switch is turned on or off.
            - indexPath: The index path of the cell containing the switch.
    */
    @objc open func switchChanged(isOn: Bool, indexPath: IndexPath) {
        guard self.account == saveIdentifier, !self.chatGroup.isDisabled,
              let info = self.datas[safe: indexPath.section]?[safe: indexPath.row], info.withSwitch,
              self.pendingSwitches.insert(info.title).inserted else { return }
        let title = info.title
        let completed: (ChatError?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self, self.account == saveIdentifier else { return }
                self.pendingSwitches.remove(title)
                if let error = error {
                    self.showToast(toast: error.errorDescription ?? "group_details_update_failed".chat.localize)
                } else if title == "contact_details_switch_donotdisturb".chat.localize {
                    self.processSilentMode(name: title, isOn: isOn)
                }
                self.datas = self.fillDatas()
                self.menuList.reloadData()
            }
        }
        info.switchValue = isOn
        self.menuList.reloadData()
        if title == "contact_details_switch_donotdisturb".chat.localize || title == "group_details_pin".chat.localize {
            guard ChatClient.shared().chatManager?.getConversation(self.chatGroup.groupId, type: .groupChat, createIfNotExist: true) != nil else {
                completed(ChatError(description: "group_details_update_failed".chat.localize, code: .general))
                return
            }
        }
        switch title {
        case "contact_details_switch_donotdisturb".chat.localize:
            if isOn { self.conversationService.setSilentMode(conversationId: self.chatGroup.groupId) { _, error in completed(error) } }
            else { self.conversationService.clearSilentMode(conversationId: self.chatGroup.groupId) { _, error in completed(error) } }
        case "group_details_pin".chat.localize:
            if isOn { self.conversationService.pin(conversationId: self.chatGroup.groupId, completion: completed) }
            else { self.conversationService.unpin(conversationId: self.chatGroup.groupId, completion: completed) }
        case "group_details_allow_invites".chat.localize:
            guard self.isOwner, let update = self.service.updateAllowInvites else {
                self.pendingSwitches.remove(title)
                self.datas = self.fillDatas()
                self.menuList.reloadData()
                return
            }
            update(self.chatGroup.groupId, isOn) { [weak self] group, error in
                DispatchQueue.main.async {
                    guard let self = self, self.account == saveIdentifier else { return }
                    if let group = group, error == nil { self.chatGroup = group }
                    completed(error)
                }
            }
        default:
            self.pendingSwitches.remove(title)
        }
    }

    @objc open func processSilentMode(name: String,isOn: Bool) {
        if name == "contact_details_switch_donotdisturb".chat.localize,let groupId = self.chatGroup.groupId {
            NotificationCenter.default.post(name: Notification.Name(rawValue: disturb_change), object: nil,userInfo: ["id":groupId,"value":isOn])
        }
    }
    
    
}

extension GroupInfoViewController: ThemeSwitchProtocol {
    open func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
        self.header.setNeedsLayout()
        self.menuList.reloadData()
    }
}


extension GroupInfoViewController: GroupServiceListener {
    public func onAttributesChangedOfGroupMember(groupId: String, userId: String, operatorId: String, attributes: [String: String]) {
        guard groupId == self.chatGroup.groupId, self.account == saveIdentifier else { return }
        DispatchQueue.main.async {
            guard self.account == saveIdentifier else { return }
            if userId == ChatUIKitContext.shared?.currentUserId, let name = attributes[GroupMemberAttributesCache.nicknameKey] { self.fillAlias(nickname: name) }
            self.loadMemberPreview()
        }
    }

    public func onGroupAdminUpdated(groupId: String, userId: String, added: Bool) {
        guard groupId == self.chatGroup.groupId else { return }
        self.fetchGroupInfo(groupId: groupId)
    }
    public func onGroupOwnerUpdated(groupId: String, ownerId: String, userId: String) {
        guard groupId == self.chatGroup.groupId else { return }
        self.fetchGroupInfo(groupId: groupId)
    }
    public func onUserJoinedGroup(groupId: String, userIds: [String]) {
        guard groupId == self.chatGroup.groupId else { return }
        self.fetchGroupInfo(groupId: groupId)
    }
    public func onUserLeaveGroup(groupId: String, userIds: [String]) {
        guard groupId == self.chatGroup.groupId else { return }
        self.fetchGroupInfo(groupId: groupId)
    }
}

/// Resolves display profiles without making view controllers depend on a particular profile provider.
enum GroupInfoProfileLoader {
    static func profile(userId: String, groupId: String? = nil) -> ChatUserProfileProtocol {
        let cached = ChatUIKitContext.shared?.userCache?[userId] ?? ChatUIKitContext.shared?.chatCache?[userId]
        let profile = ChatUserProfile()
        profile.id = userId
        profile.nickname = cached?.nickname ?? ""
        profile.avatarURL = cached?.avatarURL ?? ""
        profile.remark = cached?.remark ?? ""
        return groupId.map { GroupMemberAttributesCache.shared.displayProfile(groupId: $0, profile: profile) } ?? profile
    }

    static func resolve(userIds: [String], groupId: String? = nil, completion: @escaping ([ChatUserProfileProtocol]) -> Void) {
        let account = saveIdentifier
        let unknown = userIds.filter { profile(userId: $0).nickname.isEmpty }
        let finish: ([ChatUserProfileProtocol]) -> Void = { fetched in
            DispatchQueue.main.async {
                guard account == saveIdentifier else { return }
                let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                let deliver = {
                    completion(userIds.map { id in
                        let base = byId[id] ?? profile(userId: id)
                        return groupId.map { GroupMemberAttributesCache.shared.displayProfile(groupId: $0, profile: base) } ?? base
                    })
                }
                if let groupId = groupId {
                    GroupMemberAttributesCache.shared.fetchNicknames(groupId: groupId, userIds: userIds, service: ChatUIKitClient.shared.groupService) { _ in deliver() }
                } else { deliver() }
            }
        }
        guard !unknown.isEmpty else { finish([]); return }
        // The SDK profile endpoint accepts batches; large groups must not be sent as one request.
        let batches = stride(from: 0, to: unknown.count, by: 100).map { Array(unknown[$0..<min($0 + 100, unknown.count)]) }
        if let provider = ChatUIKitContext.shared?.userProfileProvider {
            Task {
                var fetched: [ChatUserProfileProtocol] = []
                for batch in batches {
                    guard account == saveIdentifier else { return }
                    fetched.append(contentsOf: await provider.fetchProfiles(profileIds: batch))
                }
                finish(fetched)
            }
        } else if let provider = ChatUIKitContext.shared?.userProfileProviderOC {
            func fetchBatch(_ index: Int, _ fetched: [ChatUserProfileProtocol]) {
                guard account == saveIdentifier else { return }
                guard index < batches.count else { finish(fetched); return }
                provider.fetchProfiles(profileIds: batches[index]) { profiles in
                    DispatchQueue.main.async { fetchBatch(index + 1, fetched + profiles) }
                }
            }
            fetchBatch(0, [])
        } else {
            finish([])
        }
    }

    static func memberIds(groupId: String, service: GroupService, completion: @escaping ([String], ChatError?) -> Void) {
        let account = saveIdentifier
        var ids: [String] = []
        var seenCursors = Set<String>()
        func fetch(_ cursor: String) {
            guard seenCursors.insert(cursor).inserted else { completion(ids, nil); return }
            service.fetchParticipants(groupId: groupId, cursor: cursor, pageSize: 200) { result, error in
                DispatchQueue.main.async {
                    guard account == saveIdentifier else { return }
                    if let error = error { completion([], error); return }
                    for id in result?.list ?? [] where !ids.contains(id as String) { ids.append(id as String) }
                    let next = result?.cursor ?? ""
                    if next.isEmpty { completion(ids, nil) } else { fetch(next) }
                }
            }
        }
        service.fetchGroupInfo(groupId: groupId) { group, error in
            DispatchQueue.main.async {
                guard account == saveIdentifier else { return }
                guard let group = group, error == nil else { completion([], error); return }
                // The SDK member endpoint excludes the owner and administrators.
                ids = ([group.owner ?? ""] + (group.adminList ?? [])).filter { !$0.isEmpty }
                ids = ids.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                fetch("")
            }
        }
    }
}

final class GroupDetailsMembersHeader: DetailInfoHeader {
    private final class Adapter: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        weak var header: GroupDetailsMembersHeader?
        init(header: GroupDetailsMembersHeader) { self.header = header }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { self.header?.itemCount ?? 0 }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell { self.header!.memberCell(collectionView, at: indexPath) }
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) { self.header?.selectMember(at: indexPath) }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize { CGSize(width: floor(collectionView.bounds.width / 4), height: 98) }
    }
    private lazy var adapter = Adapter(header: self)
    private let search = UIButton(type: .system)
    private let viewAll = UIButton(type: .system)
    private let members = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private var profiles: [ChatUserProfileProtocol] = []
    private var canInvite = false
    private var canRemove = false
    var showMembers: (() -> Void)?
    var searchMembers: (() -> Void)?
    var addMembers: (() -> Void)?
    var removeMembers: (() -> Void)?
    var showProfile: ((ChatUserProfileProtocol) -> Void)?
    private var itemCount: Int { self.profiles.count + (self.canInvite ? 1 : 0) + (self.canRemove ? 1 : 0) }
    var contentHeight: CGFloat { 56 + CGFloat(max(1, (self.itemCount + 3) / 4)) * 98 + 52 }

    required init(frame: CGRect, showMenu: Bool, placeHolder: UIImage?) {
        super.init(frame: frame, showMenu: false, placeHolder: nil)
        [self.avatar, self.status, self.nickName, self.detail].forEach { $0.isHidden = true }
        self.members.backgroundColor = .clear
        self.members.isScrollEnabled = false
        self.members.dataSource = self.adapter
        self.members.delegate = self.adapter
        self.members.register(GroupDetailsMemberCell.self, forCellWithReuseIdentifier: "Member")
        if let layout = self.members.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 0
        }
        self.search.contentHorizontalAlignment = .left
        self.search.titleLabel?.font = UIFont.theme.bodyLarge
        self.search.setTitle("  " + "Search".chat.localize, for: .normal)
        self.search.setImage(UIImage(chatNamed: "search")?.withRenderingMode(.alwaysTemplate), for: .normal)
        self.search.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        self.search.layer.cornerRadius = 18
        self.search.addAction(UIAction { [weak self] _ in self?.searchMembers?() }, for: .touchUpInside)
        var viewAllConfiguration = UIButton.Configuration.plain()
        viewAllConfiguration.title = "group_details_view_all".chat.localize
        viewAllConfiguration.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        viewAllConfiguration.imagePlacement = .trailing
        viewAllConfiguration.imagePadding = 6
        viewAllConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.theme.bodySmall
            return attributes
        }
        self.viewAll.configuration = viewAllConfiguration
        self.viewAll.addAction(UIAction { [weak self] _ in self?.showMembers?() }, for: .touchUpInside)
        self.addSubViews([self.search, self.members, self.viewAll])
        self.applyColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(profiles: [ChatUserProfileProtocol], canInvite: Bool, canRemove: Bool) {
        self.profiles = profiles
        self.canInvite = canInvite
        self.canRemove = canRemove
        self.members.reloadData()
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.applyColors()
        self.search.frame = CGRect(x: 16, y: 4, width: self.bounds.width - 32, height: 36)
        self.members.frame = CGRect(x: 8, y: 56, width: self.bounds.width - 16, height: self.contentHeight - 108)
        self.viewAll.frame = CGRect(x: 16, y: self.members.frame.maxY + 4, width: self.bounds.width - 32, height: 44)
        self.members.collectionViewLayout.invalidateLayout()
    }

    private func applyColors() {
        self.search.backgroundColor = Theme.style == .dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor95
        self.search.tintColor = Theme.style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
        self.search.setTitleColor(Theme.style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5, for: .normal)
        self.viewAll.configuration?.baseForegroundColor = Theme.style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor4
    }

    private func memberCell(_ collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Member", for: indexPath) as! GroupDetailsMemberCell
        if let profile = self.profiles[safe: indexPath.item] {
            cell.configure(profile: profile, removing: false)
        } else {
            cell.configure(profile: nil, removing: indexPath.item == self.profiles.count + (self.canInvite ? 1 : 0))
        }
        return cell
    }
    private func selectMember(at indexPath: IndexPath) {
        if let profile = self.profiles[safe: indexPath.item] { self.showProfile?(profile) }
        else if indexPath.item == self.profiles.count && self.canInvite { self.addMembers?() }
        else { self.removeMembers?() }
    }
}

private final class GroupDetailsMemberCell: UICollectionViewCell, ThemeSwitchProtocol {
    private let avatar = ImageView(frame: .zero)
    private let name = UILabel()
    private let action = UIImageView()
    private var isAction = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.avatar.contentMode = .scaleAspectFill
        self.avatar.clipsToBounds = true
        self.name.font = UIFont.theme.bodyMedium
        self.name.textAlignment = .center
        self.name.lineBreakMode = .byTruncatingTail
        self.action.contentMode = .center
        self.contentView.addSubViews([self.avatar, self.name, self.action])
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(profile: ChatUserProfileProtocol?, removing: Bool) {
        self.isAction = profile == nil
        self.avatar.isHidden = self.isAction
        self.name.isHidden = self.isAction
        self.action.isHidden = !self.isAction
        if let profile = profile {
            self.avatar.image(with: profile.avatarURL, placeHolder: Appearance.conversation.singlePlaceHolder)
            self.name.text = profile.nickname.isEmpty ? profile.id : profile.nickname
            self.accessibilityLabel = self.name.text
        } else {
            self.action.image = UIImage(systemName: removing ? "minus" : "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .ultraLight))
            self.accessibilityLabel = (removing ? "remove_participants" : "add_group_members").chat.localize
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(58, self.contentView.bounds.width - 12)
        self.avatar.frame = CGRect(x: (self.bounds.width - size) / 2, y: 8, width: size, height: size)
        self.avatar.layer.cornerRadius = size / 2
        self.name.frame = CGRect(x: 2, y: size + 12, width: self.bounds.width - 4, height: 20)
        self.action.frame = self.avatar.frame
        self.action.layer.cornerRadius = size / 2
        self.action.layer.borderWidth = 0.5
    }
    func switchTheme(style: ThemeStyle) {
        self.name.textColor = style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor4
        self.action.tintColor = style == .dark ? UIColor.theme.neutralColor5 : UIColor.theme.neutralColor7
        self.action.layer.borderColor = (style == .dark ? UIColor.theme.neutralColor3 : UIColor.theme.neutralColor9).cgColor
    }
}

private final class GroupDetailsRowCell: UITableViewCell, ThemeSwitchProtocol {
    private let name = UILabel()
    private let detail = UILabel()
    private let indicator = UIImageView()
    private let line = UIView()
    let toggle = UISwitch()
    var toggleChanged: ((Bool) -> Void)?
    private var info = DetailInfo()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.name.font = UIFont.theme.titleMedium
        self.detail.font = UIFont.theme.bodyLarge
        self.indicator.contentMode = .scaleAspectFit
        self.contentView.addSubViews([self.name, self.detail, self.indicator, self.line, self.toggle])
        self.toggle.addTarget(self, action: #selector(toggleValueChanged), for: .valueChanged)
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(info: DetailInfo) {
        self.info = info
        self.name.text = info.title
        self.detail.text = info.detail
        self.toggle.isHidden = !info.withSwitch
        self.toggle.isOn = info.switchValue
        self.indicator.isHidden = info.withSwitch || info.title == "contact_details_button_clearchathistory".chat.localize
        self.selectionStyle = info.withSwitch ? .none : .default
        self.switchTheme(style: Theme.style)
        self.setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.contentView.bounds.width
        let height = self.contentView.bounds.height
        let announcement = self.info.title == "group_details_button_announcement".chat.localize
        let detailWidth = min(width * 0.62, self.detail.sizeThatFits(CGSize(width: width, height: 24)).width)
        self.name.frame = CGRect(x: 14, y: announcement ? 10 : (height - 24) / 2, width: self.info.withSwitch ? width - 88 : width - detailWidth - 62, height: 24)
        self.detail.frame = announcement ? CGRect(x: 14, y: 34, width: width - 62, height: 36) : CGRect(x: width - detailWidth - 38, y: (height - 24) / 2, width: detailWidth, height: 24)
        self.detail.numberOfLines = announcement ? 2 : 1
        self.detail.textAlignment = announcement ? .left : .right
        self.detail.font = announcement ? UIFont.theme.bodyMedium : UIFont.theme.bodyLarge
        self.indicator.frame = CGRect(x: width - 32, y: (height - 20) / 2, width: 18, height: 20)
        self.toggle.sizeToFit()
        self.toggle.center = CGPoint(x: width - self.toggle.bounds.width / 2 - 16, y: height / 2)
        self.line.frame = CGRect(x: 14, y: height - 0.5, width: width - 14, height: 0.5)
    }
    @objc private func toggleValueChanged() { self.toggleChanged?(self.toggle.isOn) }
    func switchTheme(style: ThemeStyle) {
        self.name.textColor = style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        self.detail.textColor = style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
        self.toggle.onTintColor = style == .dark ? UIColor.theme.primaryDarkColor : UIColor.theme.primaryLightColor
        self.line.backgroundColor = style == .dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor9
        self.indicator.image = UIImage(chatNamed: self.info.title == "group_details_id".chat.localize ? "copy" : "chevron_right")?.withRenderingMode(.alwaysTemplate)
        self.indicator.tintColor = style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
    }
}
