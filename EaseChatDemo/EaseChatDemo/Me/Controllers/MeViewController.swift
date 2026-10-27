//
//  MeViewController.swift
//  EaseChatDemo
//

import UIKit
import EaseChatUIKit
import SwiftFFDBHotFix

final class MeViewController: UIViewController {
    private enum Action { case business, website, sdk, uikit, registration, policies, status, profile, general, notification, blocked }
    private struct Row {
        let title: String
        let detail: String
        let action: Action
        init(_ title: String, _ detail: String = "", _ action: Action) { self.title = title; self.detail = detail; self.action = action }
        var navigable: Bool { [.policies, .status, .profile, .general, .notification, .blocked].contains(self.action) }
        var link: Bool { self.action == .business || self.action == .website }
        var selectable: Bool { ![.sdk, .uikit, .registration].contains(self.action) }
    }
    private var menusData: [[Row]] {
        var settings = [Row("online_status", PresenceManager.shared.currentUserStatus, .status), Row("Personal Info", "", .profile), Row("General", "", .general), Row("me_message_notifications", "", .notification)]
        if Appearance.contact.enableBlock { settings.append(Row("block_list", "", .blocked)) }
        return [[Row("me_contact_business", "400-622-1776", .business), Row("me_visit_easemob", "www.easemob.com", .website), Row("me_sdk_version", "Easemob SDK v" + ChatClient.shared().version, .sdk), Row("me_uikit_version", "Easemob UIKit v" + ChatUIKit_VERSION, .uikit), Row("ICP", "京ICP备2023000793号-10A", .registration), Row("me_privacy_and_agreements", "", .policies)], settings]
    }
    private var currentUserId: String {
        let userId = ChatUIKitContext.shared?.currentUserId ?? ""
        return userId.isEmpty ? (ChatUIKitContext.shared?.currentUser?.id ?? "") : userId
    }
    private var profileGeneration = 0
    private var signature = ""
    private var limited = false
    private var customStatus = ""
    @UserDefault("EaseChatDemoUserPhone", defaultValue: "") private var phone
    private lazy var avatarEditor = UserAvatarEditor(presenter: self)
    private lazy var header = MeProfileHeader(frame: CGRect(x: 0, y: 0, width: self.view.bounds.width, height: 104))
    private let logoutButton = UIButton(type: .system)
    private let deregisterButton = UIButton(type: .system)
    private lazy var accountFooter: UIView = {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: self.view.bounds.width, height: 172))
        self.logoutButton.setTitle("me_logout".localized(), for: .normal)
        self.deregisterButton.setTitle("me_delete_account".localized(), for: .normal)
        for button in [self.logoutButton, self.deregisterButton] {
            button.titleLabel?.font = UIFont.theme.labelLarge
            button.layer.cornerRadius = 25
            footer.addSubview(button)
        }
        self.logoutButton.addAction(UIAction { [weak self] _ in self?.logout() }, for: .touchUpInside)
        self.deregisterButton.addAction(UIAction { [weak self] _ in self?.deregister() }, for: .touchUpInside)
        return footer
    }()
    private lazy var menuList: UITableView = {
        // Grouped section headers scroll with their rows instead of pinning to the top.
        let list = UITableView(frame: .zero, style: .grouped)
        list.backgroundColor = .clear
        list.separatorStyle = .none
        list.rowHeight = 54
        list.sectionHeaderTopPadding = 0
        list.sectionFooterHeight = .leastNormalMagnitude
        list.estimatedSectionHeaderHeight = 0
        list.estimatedSectionFooterHeight = 0
        list.contentInsetAdjustmentBehavior = .never
        list.tableHeaderView = self.header
        list.tableFooterView = self.accountFooter
        list.delegate = self
        list.dataSource = self
        list.register(MeMenuCell.self, forCellReuseIdentifier: "MeMenuCell")
        return list
    }()
    private lazy var limitCount: UILabel = {
        UILabel(frame: CGRect(x: 0, y: 13, width: 50, height: 22)).font(UIFont.theme.bodyLarge).text("0/20")
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(self.menuList)
        self.header.avatarTapped = { [weak self] in self?.avatarEditor.showActions() }
        self.header.profileTapped = { [weak self] in self?.viewProfile() }
        self.header.signatureTapped = { [weak self] in self?.editSignature() }
        self.header.copyIdentifier = { [weak self] in
            UIPasteboard.general.string = self?.currentUserId ?? ""
            self?.showToast(toast: "Copied".chat.localize)
        }
        self.refreshProfile()
        PresenceManager.shared.addHandler(handler: self)
        self.showUserStatus()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshProfile), name: NSNotification.Name(userAvatarUpdated), object: nil)
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        self.refreshProfile()
        self.fetchUserInfo()
        self.menuList.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = self.view.safeAreaInsets.top
        let tabTop = self.tabBarController?.tabBar.frame.minY ?? (self.view.bounds.height - self.view.safeAreaInsets.bottom)
        self.menuList.frame = CGRect(x: 0, y: top, width: self.view.bounds.width, height: max(0, min(self.view.bounds.height, tabTop) - top))
        self.header.frame.size.width = self.menuList.bounds.width
        self.accountFooter.frame.size.width = self.menuList.bounds.width
        self.logoutButton.frame = CGRect(x: 16, y: 48, width: self.menuList.bounds.width - 32, height: 50)
        self.deregisterButton.frame = CGRect(x: 16, y: 110, width: self.menuList.bounds.width - 32, height: 50)
    }

    @objc private func refreshProfile() {
        self.profileGeneration += 1
        let userId = self.currentUserId
        let user = ChatUIKitContext.shared?.currentUser
        self.header.configure(nickname: (user?.nickname.isEmpty == false ? user?.nickname : userId) ?? userId, signature: self.signature, userId: userId, avatarURL: user?.avatarURL ?? "")
    }

    private func fetchUserInfo() {
        let userId = ChatUIKitContext.shared?.currentUserId ?? ""
        guard !userId.isEmpty else { return }
        let account = saveIdentifier
        let generation = self.profileGeneration
        ChatClient.shared().userInfoManager?.fetchUserInfo(byId: [userId], type: [0, 1, 5]) { [weak self] infoMap, error in
            DispatchQueue.main.async {
                guard let self = self, account == saveIdentifier, generation == self.profileGeneration else { return }
                guard let info = infoMap?[userId], error == nil else { return }
                let existing = (EaseChatProfile.select(where: "id = ?", values: [userId]) as? [EaseChatProfile])?.first
                let profile = existing ?? EaseChatProfile()
                profile.id = userId
                profile.nickname = info.nickname ?? ""
                profile.avatarURL = info.avatarUrl ?? ""
                profile.modifyTime = Int64(Date().timeIntervalSince1970 * 1000)
                if existing == nil { profile.insert() } else { profile.updateFFDB() }
                ChatUIKitContext.shared?.currentUser = profile
                ChatUIKitContext.shared?.userCache?[userId] = profile
                self.signature = info.sign ?? ""
                self.refreshProfile()
            }
        }
    }

    private func showUserStatus() {
        let account = saveIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let self = self, account == saveIdentifier else { return }
            let presence = PresenceManager.shared.presences[ChatUIKitContext.shared?.currentUserId ?? ""]
            let state = presence.map { PresenceManager.status(with: $0) } ?? .online
            self.header.showStatus(state)
            self.menuList.reloadData()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        PresenceManager.shared.removeHandler(handler: self)
    }
}

extension MeViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { self.menusData.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.menusData[section].count }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 28 }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { .leastNormalMagnitude }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = Theme.style == .dark ? UIColor.theme.neutralColor0 : UIColor.theme.neutralColor95
        let label = UILabel(frame: CGRect(x: 16, y: 4, width: tableView.bounds.width - 32, height: 20))
        label.autoresizingMask = [.flexibleWidth]
        label.font = UIFont.theme.bodyMedium
        label.textColor = Theme.style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
        label.text = (section == 0 ? "About" : "Setting").localized()
        header.addSubview(label)
        return header
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MeMenuCell", for: indexPath) as! MeMenuCell
        let row = self.menusData[indexPath.section][indexPath.row]
        cell.configure(title: row.title.localized(), detail: row.detail, navigable: row.navigable, link: row.link, selectable: row.selectable)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch self.menusData[indexPath.section][indexPath.row].action {
        case .business: self.openURL("tel:4006221776")
        case .website: self.openURL("https://www.easemob.com")
        case .policies:
            let controller = PrivacyPolicyViewController()
            controller.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(controller, animated: true)
        case .status: self.showOnlineStatusDialog()
        case .profile: self.viewProfile()
        case .general: self.viewGeneral()
        case .notification: self.viewNotification()
        case .blocked:
            let controller = BlockContactsViewController()
            controller.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(controller, animated: true)
        case .sdk, .uikit, .registration: break
        }
    }
    private func openURL(_ address: String) {
        guard let url = URL(string: address), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:])
    }
    private func deregister() {
        DialogManager.shared.showAlert(title: "Deregister".localized(), content: "Deregister Alert".localized(), showCancel: true, showConfirm: true) { _ in
            EasemobBusinessRequest.shared.sendDELETERequest(api: .deregister(self.phone), params: [:]) { result, error in
                if error == nil {
                    DispatchQueue.main.async {
                        if error == nil {
                            ChatUIKitClient.shared.logout(unbindNotificationDeviceToken: false) { _ in
                                NotificationCenter.default.post(name: Notification.Name(backLoginPage), object: nil, userInfo: nil)
                            }
                            
                        } else {
                            NotificationCenter.default.post(name: Notification.Name(backLoginPage), object: nil, userInfo: nil)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        if let error = error as? EasemobError {
                            self.showToast(toast: "\(error.message ?? "")")
                        } else {
                            self.showToast(toast: "\(error?.localizedDescription ?? "")")
                        }
                    }
                }
            }
        }
    }
    
    private func viewProfile() {
        let vc = PersonalInfoViewController()
        vc.signature = self.signature
        vc.signatureDidChange = { [weak self] signature in self?.updateSignature(signature) }
        vc.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(vc, animated: true)
    }

    private func editSignature() {
        let controller = UserSignatureEditViewController(signature: self.signature) { [weak self] signature in
            self?.updateSignature(signature)
        }
        controller.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(controller, animated: true)
    }

    private func updateSignature(_ signature: String) {
        self.signature = signature
        self.refreshProfile()
    }
    
    private func viewGeneral() {
        let vc = GeneralViewController()
        vc.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    private func viewNotification() {
        let vc = NotificationSettingViewController()
        vc.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    private func logout() {
        DialogManager.shared.showAlert(title: "Confirm Logout".localized(), content: "", showCancel: true, showConfirm: true) { _ in
            NotificationCenter.default.post(name: Notification.Name(backLoginPage), object: nil, userInfo: nil)
        }
    }
    
    @objc func showOnlineStatusDialog() {
        let actions = [ActionSheetItem(title: "Online".localized(), type: .normal, tag: "online"),
                       ActionSheetItem(title: "Busy".localized(), type: .normal, tag: "busy"),
                       ActionSheetItem(title: "Do Not Disturb".localized(), type: .normal, tag: "disturb"),
                       ActionSheetItem(title: "Away".localized(), type: .normal, tag: "away"),
                       ActionSheetItem(title: "Custom Status".localized().localized(), type: .normal, tag: "custom_status")]
        DialogManager.shared.showActions(actions: actions) { [weak self] in
            self?.publishPresenceState(item: $0)
        }
    }
    
    @objc func publishPresenceState(item: ActionSheetItemProtocol) {
        var status: String?
        switch item.tag {
        case "busy":
            status = "\(PresenceManager.State.busy.rawValue)"
        case "disturb":
            status = "\(PresenceManager.State.doNotDisturb.rawValue)"
        case "away":
            status = "\(PresenceManager.State.away.rawValue)"
        case "custom_status":
            self.showCustomOnlineStatusAlert()
        default:
            break
        }
        PresenceManager.shared.publishPresence(description: status) { [weak self] error in
            if error != nil {
                self?.showToast(toast: "发布状态失败！")
            }
        }
    }
    
    @objc func showCustomOnlineStatusAlert() {
        let size = Appearance.alertContainerConstraintsSize
        let alert = AlertView().background(color: Theme.style == .dark ? UIColor.theme.neutralColor2:UIColor.theme.neutralColor98).title(title: "Custom Status".localized()).cornerRadius(Appearance.alertStyle == .small ? .extraSmall:.medium).titleColor(color: Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1)
        alert.textField(font: UIFont.theme.bodyLarge).textField(color: Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1).textFieldPlaceholder(color: Theme.style == .dark ? UIColor.theme.neutralColor5:UIColor.theme.neutralColor6).textFieldPlaceholder(placeholder: "Please input".chat.localize).textFieldRadius(cornerRadius: Appearance.alertStyle == .small ? .extraSmall:.medium).textFieldBackground(color: Theme.style == .dark ? UIColor.theme.neutralColor3:UIColor.theme.neutralColor95).textFieldDelegate(delegate: self).textFieldRightView(rightView: UIView {
            UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50)).backgroundColor(.clear)
            self.limitCount
        })
        alert.textField.becomeFirstResponder()
        alert.leftButton(color: Theme.style == .dark ? UIColor.theme.neutralColor95:UIColor.theme.neutralColor3).leftButtonBorder(color: Theme.style == .dark ? UIColor.theme.neutralColor4:UIColor.theme.neutralColor7).leftButton(title: "report_button_click_menu_button_cancel".chat.localize).leftButtonRadius(cornerRadius: Appearance.alertStyle == .small ? .extraSmall:.large)
        alert.rightButtonBackground(color: Theme.style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor).rightButton(color: UIColor.theme.neutralColor98).rightButtonTapClosure { [weak self] _ in
            guard let `self` = self else { return }
            if self.limited {
                self.showToast(toast: "The length of the custom status should be less than 20 characters".chat.localize)
                return
            } else {
                self.limitCount.text = "0/20"
                PresenceManager.shared.publishPresence(description: self.customStatus) { [weak self] error in
                    if error != nil {
                        self?.showToast(toast: "发布状态失败！")
                    }
                }
            }
        }.rightButton(title: "Confirm".chat.localize).rightButtonRadius(cornerRadius: Appearance.alertStyle == .small ? .extraSmall:.large)
        let alertVC = AlertViewController(custom: alert,size: size, customPosition: true)
        let vc = UIViewController.currentController
        if vc != nil {
            vc?.presentViewController(alertVC)
        }
    }
    
    private func publishCustomStatus() {
        PresenceManager.shared.publishPresence(description: self.customStatus) { [weak self] error in
            if error != nil {
                self?.showToast(toast: "自定义状态设置失败")
            } else {
                self?.menuList.reloadData()
            }
        }
    }
}
extension MeViewController: UITextFieldDelegate,PresenceDidChangedListener {
    
    func presenceStatusChanged(users: [String]) {
        self.showUserStatus()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        self.customStatus = (textField.text! as NSString).replacingCharacters(in: range, with: string)
        if self.customStatus.count > 0 {
            self.limited = self.customStatus.count > 20
            self.limitCount.text = "\(self.customStatus.count)/20"
            if self.customStatus.count > 20 {
                self.limitCount.textColor = Theme.style == .dark ? UIColor.theme.errorColor5:UIColor.theme.errorColor6
            } else {
                self.limitCount.textColor = Theme.style == .dark ? UIColor.theme.neutralColor4:UIColor.theme.neutralColor7
            }
        } else {
            self.limitCount.text = "0/20"
        }
        return true
    }
}



extension MeViewController: ThemeSwitchProtocol {
    func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1 : UIColor.theme.neutralColor98
        self.limitCount.textColor = style == .dark ? UIColor.theme.neutralColor4 : UIColor.theme.neutralColor7
        for button in [self.logoutButton, self.deregisterButton] { button.backgroundColor = style == .dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor95 }
        self.logoutButton.setTitleColor(style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1, for: .normal)
        self.deregisterButton.setTitleColor(style == .dark ? UIColor.theme.errorColor5 : UIColor.theme.errorColor6, for: .normal)
        self.menuList.reloadData()
    }
}

final class MeProfileHeader: UIView, ThemeSwitchProtocol {
    private let avatarPlaceholder = Appearance.avatarPlaceHolder
        ?? UIImage(named: "default_avatar", in: .chatBundle, with: nil)
        ?? UIImage(systemName: "person.crop.circle.fill")
    private let avatar = ImageView(frame: .zero)
    private let avatarButton = UIButton(type: .custom)
    private let profileButton = UIButton(type: .custom)
    private let signatureButton = UIButton(type: .custom)
    private let nickname = UILabel()
    private let signature = UILabel()
    private let identifier = UIButton(type: .system)
    private let status = UIImageView()
    private var statusState = PresenceManager.State.online
    var avatarTapped: (() -> Void)?
    var profileTapped: (() -> Void)?
    var signatureTapped: (() -> Void)?
    var copyIdentifier: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.avatar.contentMode = .scaleAspectFill
        self.avatar.clipsToBounds = true
        self.avatar.image = self.avatarPlaceholder
        self.nickname.font = UIFont.theme.headlineMedium
        self.signature.font = UIFont.theme.bodyMedium
        self.identifier.contentHorizontalAlignment = .left
        self.status.contentMode = .scaleAspectFit
        self.status.layer.cornerRadius = 9
        self.status.clipsToBounds = true
        self.status.layer.borderWidth = 2
        self.avatarButton.accessibilityLabel = "me_change_avatar".localized()
        self.avatarButton.addAction(UIAction { [weak self] _ in self?.avatarTapped?() }, for: .touchUpInside)
        self.profileButton.accessibilityLabel = "Personal Info".localized()
        self.profileButton.addAction(UIAction { [weak self] _ in self?.profileTapped?() }, for: .touchUpInside)
        self.signatureButton.accessibilityLabel = "me_edit_signature".localized()
        self.signatureButton.addAction(UIAction { [weak self] _ in self?.signatureTapped?() }, for: .touchUpInside)
        self.identifier.accessibilityLabel = "me_copy_id".localized()
        self.identifier.addAction(UIAction { [weak self] _ in self?.copyIdentifier?() }, for: .touchUpInside)
        self.addSubViews([self.avatar, self.nickname, self.signature, self.avatarButton, self.profileButton, self.signatureButton, self.identifier, self.status])
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(nickname: String, signature: String, userId: String, avatarURL: String) {
        self.nickname.text = nickname
        self.signature.text = signature.isEmpty ? "me_signature_placeholder".localized() : signature
        self.signatureButton.accessibilityValue = self.signature.text
        self.avatar.image(with: avatarURL, placeHolder: self.avatarPlaceholder)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "ID: " + userId
        configuration.image = UIImage(named: "doc_on_doc")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.contentInsets = .zero
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes; attributes.font = UIFont.theme.bodySmall; return attributes
        }
        self.identifier.configuration = configuration
        self.identifier.accessibilityValue = userId
        self.switchTheme(style: Theme.style)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        self.avatar.frame = CGRect(x: 16, y: 16, width: 72, height: 72)
        self.avatar.cornerRadius(Appearance.avatarRadius)
        self.avatarButton.frame = self.avatar.frame
        self.nickname.frame = CGRect(x: 100, y: 18, width: self.bounds.width - 116, height: 26)
        self.signature.frame = CGRect(x: 100, y: 48, width: self.bounds.width - 116, height: 20)
        self.profileButton.frame = CGRect(x: 96, y: 12, width: self.bounds.width - 112, height: 32)
        self.signatureButton.frame = CGRect(x: 96, y: 44, width: self.bounds.width - 112, height: 24)
        self.identifier.frame = CGRect(x: 100, y: 68, width: self.bounds.width - 116, height: 24)
        self.status.frame = CGRect(x: self.avatar.frame.maxX - 20, y: self.avatar.frame.maxY - 20, width: 20, height: 20)
    }
    func showStatus(_ state: PresenceManager.State) {
        self.statusState = state
        self.status.image = nil
        switch state {
        case .online: self.status.backgroundColor = UIColor.theme.secondaryColor5
        case .offline: self.status.backgroundColor = UIColor.theme.neutralColor6
        case .busy: self.status.backgroundColor = Theme.style == .dark ? UIColor.theme.errorColor5 : UIColor.theme.errorColor6
        default:
            self.status.backgroundColor = self.backgroundColor
            self.status.image = PresenceManager.presenceImagesMap[state] as? UIImage
        }
    }
    func switchTheme(style: ThemeStyle) {
        self.backgroundColor = style == .dark ? UIColor.theme.neutralColor1 : UIColor.theme.neutralColor98
        self.nickname.textColor = style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        self.signature.textColor = style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor4
        self.identifier.configuration?.baseForegroundColor = style == .dark ? UIColor.theme.neutralColor5 : UIColor.theme.neutralColor7
        self.status.layer.borderColor = self.backgroundColor?.cgColor
        self.showStatus(self.statusState)
    }
}

extension FFObject {
    @discardableResult
    public func updateFFDB() -> Bool {
        do {
            var values = [Any]()
            for column in subType.columnsOfSelf() {
                let value = valueNotNullFrom(column)
                values.append(value)
            }
            values.append(valueNotNullFrom("id"))
//            values.append(valueNotNullFrom(subType.primaryKeyColumn()))
            return try FFDBManager.update(subType, set: subType.columnsOfSelf(), where: "id = ?",values:values)
        } catch {
            consoleLogInfo("failed: \(error.localizedDescription)", type: .error)
        }
        return false
    }
}

