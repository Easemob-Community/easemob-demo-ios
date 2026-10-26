//
//  PersonalInfoViewController.swift
//  EaseChatDemo
//
//  Created by 朱继超 on 2024/3/6.
//

import UIKit
import EaseChatUIKit
import MobileCoreServices
import AVFoundation
import SwiftFFDBHotFix
import EaseCallUIKit

let userAvatarUpdated = "userAvatarUpdated"

final class PersonalInfoViewController: UIViewController {
    var signature = ""
    var signatureDidChange: ((String) -> Void)?
    private var signatureGeneration = 0
    private lazy var avatarEditor = UserAvatarEditor(presenter: self)
    private let account = saveIdentifier
    
    private lazy var infos: [Dictionary<String,String>] = {
        var userId = ChatUIKitContext.shared?.currentUserId ?? ""
        if let nickname = ChatUIKitContext.shared?.currentUser?.nickname {
            userId = nickname
        }
        return [["title":"Avatar".localized(),"detail":ChatUIKitContext.shared?.currentUser?.avatarURL ?? ""],["title":"Nickname".localized(),"detail":userId],["title":"me_signature_title".localized(),"detail":self.signature]]
    }()
    
    private lazy var navigation: ChatNavigationBar = {
        ChatNavigationBar(textAlignment: .left)
    }()
    
    private lazy var infoList: UITableView = {
        UITableView(frame: CGRect(x: 0, y: EaseChatUIKit.NavigationHeight, width: self.view.frame.width, height: self.view.frame.height-EaseChatUIKit.NavigationHeight), style: .plain).separatorStyle(.none).tableFooterView(UIView()).backgroundColor(.clear).delegate(self).dataSource(self)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubViews([self.navigation,self.infoList])
        self.infoList.reloadData()
        self.fetchSignature()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAvatar), name: NSNotification.Name(userAvatarUpdated), object: nil)
        if let url = ChatUIKitContext.shared?.currentUser?.avatarURL,!url.isEmpty {
            self.navigation.avatarURL = url
        }
        
        self.navigation.title = "Personal Info".localized()
        self.navigation.clickClosure = { [weak self] _,_ in
            self?.navigationController?.popViewController(animated: true)
        }
        // Do any additional setup after loading the view.
        EaseChatUIKit.Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: EaseChatUIKit.Theme.style)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

extension PersonalInfoViewController {
    private func fetchSignature() {
        guard let userId = ChatUIKitContext.shared?.currentUserId, !userId.isEmpty else { return }
        let generation = self.signatureGeneration
        ChatClient.shared().userInfoManager?.fetchUserInfo(byId: [userId], type: [5]) { [weak self] infos, error in
            DispatchQueue.main.async {
                guard let self, self.account == saveIdentifier, self.signatureGeneration == generation,
                      error == nil, let info = infos?[userId] else { return }
                self.signature = info.sign ?? ""
                self.infos[2]["detail"] = self.signature
                self.infoList.reloadData()
            }
        }
    }

    private func editSignature() {
        let controller = UserSignatureEditViewController(signature: self.signature) { [weak self] signature in
            guard let self else { return }
            self.signatureGeneration += 1
            self.signature = signature
            self.infos[2]["detail"] = signature
            self.infoList.reloadData()
            self.signatureDidChange?(signature)
        }
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func refreshAvatar() {
        guard self.account == saveIdentifier else { return }
        self.infos[0]["detail"] = ChatUIKitContext.shared?.currentUser?.avatarURL ?? ""
        self.navigation.avatarURL = self.infos[0]["detail"]
        self.infoList.reloadData()
    }
}

extension PersonalInfoViewController: UITableViewDelegate,UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        54
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.infos.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "PersonalInfoCell") as? PersonalInfoCell
        if cell == nil {
            cell = PersonalInfoCell(style: .default, reuseIdentifier: "PersonalInfoCell")
        }
        if let title = self.infos[safe:indexPath.row]?["title"] as? String, let detail = self.infos[safe:indexPath.row]?["detail"] as? String {
            cell?.refresh(title: title, detail: detail)
        }
        
        cell?.accessoryType = .disclosureIndicator
        cell?.selectionStyle = .none
        return cell ?? UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let title = self.infos[safe:indexPath.row]?["title"] as? String {
            switch title {
            case "Avatar".localized():
                self.avatarEditor.showActions()
            case "Nickname".localized(): self.editName()
            case "me_signature_title".localized(): self.editSignature()
            default:
                break
            }
        }
    }
    
    private func editName() {
        guard let userId = ChatUIKitContext.shared?.currentUserId else { return }
        let vc = MineContactRemarkEditViewController(userId: userId, rawText: self.infos[1]["detail"] ?? "") { [weak self] nickname in
            guard let `self` = self else { return }
            self.updateUserInfo(userId: userId, nickname: nickname)
        }
        vc.navigation.title = "Modify Nickname".localized()
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    private func updateUserInfo(userId: String,nickname: String) {
        ChatClient.shared().userInfoManager?.updateOwnUserInfo(nickname, with: .nickName, completion: { [weak self] info, error in
            guard let `self` = self else { return }
            DispatchQueue.main.async {
                if error == nil {
                    self.infos[1]["detail"] = nickname
                    self.infoList.reloadData()
                    ChatUIKitContext.shared?.currentUser?.nickname = nickname
                    ChatUIKitContext.shared?.userCache?[userId]?.nickname = nickname
                    ChatUIKitContext.shared?.chatCache?[userId]?.nickname = nickname
                    (ChatUIKitContext.shared?.userCache?[userId] as? ChatUserProfile)?.modifyTime = Int64(Date().timeIntervalSince1970*1000)
                    (ChatUIKitContext.shared?.chatCache?[userId] as? ChatUserProfile)?.modifyTime = Int64(Date().timeIntervalSince1970*1000)
                    CallKitManager.shared.currentUserInfo?.nickname = nickname
                    CallKitManager.shared.usersCache[userId]?.nickname = nickname
                    if let user = ChatUIKitContext.shared?.currentUser {
                        let profile = EaseChatProfile()
                        profile.modifyTime = Int64(Date().timeIntervalSince1970*1000)
                        profile.nickname = nickname
                        profile.avatarURL = user.avatarURL
                        profile.updateFFDB()
                        ChatUIKitContext.shared?.chatCache?[userId] = profile
                        ChatUIKitContext.shared?.userCache?[userId] = profile
                    }
                } else {
                    DialogManager.shared.showAlert(title: "error".chat.localize, content: "update nickname failed".chat.localize, showCancel: false, showConfirm: true) { _ in
                        
                    }
                }
            }
        })
    }
    
}

final class UserSignatureEditViewController: UIViewController, UITextViewDelegate, EaseChatUIKit.ThemeSwitchProtocol {
    private let account = saveIdentifier
    private let maximumLength = 256
    private let originalSignature: String
    private let signatureDidSave: (String) -> Void
    private var isSaving = false
    private let container = UIView()
    private let editor = CustomTextView()
    private let countLabel = UILabel()
    private lazy var navigation = ChatNavigationBar(textAlignment: .left, rightTitle: "Save".chat.localize)

    init(signature: String, onSaved: @escaping (String) -> Void) {
        self.originalSignature = signature
        self.signatureDidSave = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigation.title = "me_edit_signature".localized()
        self.navigation.clickClosure = { [weak self] type, _ in
            guard let self else { return }
            if type == .back, !self.isSaving { self.navigationController?.popViewController(animated: true) }
            if type == .rightTitle { self.save() }
        }
        self.editor.font = UIFont.theme.bodyLarge
        self.editor.text = self.originalSignature
        self.editor.placeholder = "me_signature_placeholder".localized()
        self.editor.delegate = self
        self.editor.accessibilityLabel = "me_signature_title".localized()
        self.countLabel.font = UIFont.theme.bodyMedium
        self.countLabel.textAlignment = .right
        self.container.layer.cornerRadius = 8
        self.container.addSubViews([self.editor, self.countLabel])
        self.view.addSubViews([self.container, self.navigation])
        EaseChatUIKit.Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: EaseChatUIKit.Theme.style)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.container.frame = CGRect(x: 16, y: self.navigation.frame.maxY + 16, width: self.view.bounds.width - 32, height: 180)
        self.editor.frame = CGRect(x: 12, y: 8, width: self.container.bounds.width - 24, height: 132)
        self.countLabel.frame = CGRect(x: 12, y: 146, width: self.container.bounds.width - 24, height: 22)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.editor.becomeFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) { self.updateCount() }

    private func updateCount() {
        let count = (self.editor.text ?? "").count
        self.countLabel.text = "\(count)/\(self.maximumLength)"
        self.countLabel.textColor = count > self.maximumLength
            ? (EaseChatUIKit.Theme.style == .dark ? UIColor.theme.errorColor5 : UIColor.theme.errorColor6)
            : (EaseChatUIKit.Theme.style == .dark ? UIColor.theme.neutralColor5 : UIColor.theme.neutralColor7)
        self.navigation.rightItem.isEnabled = !self.isSaving && count <= self.maximumLength
    }

    private func save() {
        guard !self.isSaving else { return }
        let signature = self.editor.text ?? ""
        guard signature.count <= self.maximumLength else {
            self.showToast(toast: "Reach content character limit.".chat.localize)
            return
        }
        guard self.account == saveIdentifier, !(ChatUIKitContext.shared?.currentUserId ?? "").isEmpty,
              let manager = ChatClient.shared().userInfoManager else {
            self.showToast(toast: "me_signature_update_failed".localized())
            return
        }
        self.isSaving = true
        self.editor.isEditable = false
        self.updateCount()
        manager.updateOwnUserInfo(signature, with: .sign) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.account == saveIdentifier else { return }
                self.isSaving = false
                self.editor.isEditable = true
                self.updateCount()
                if let error {
                    self.showToast(toast: error.errorDescription ?? "me_signature_update_failed".localized())
                    return
                }
                self.signatureDidSave(signature)
                self.view.endEditing(true)
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    func switchTheme(style: EaseChatUIKit.ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1 : UIColor.theme.neutralColor98
        self.container.backgroundColor = style == .dark ? UIColor.theme.neutralColor3 : UIColor.theme.neutralColor95
        self.editor.backgroundColor = .clear
        self.editor.textColor = style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        self.editor.tintColor = style == .dark ? UIColor.theme.primaryDarkColor : UIColor.theme.primaryLightColor
        self.updateCount()
    }
}

/// Shared by the profile header and the personal-info avatar row.
final class UserAvatarEditor: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    @UserDefault("EaseChatDemoServerConfig", defaultValue: Dictionary<String,String>()) private var serverConfig
    private weak var presenter: UIViewController?
    private let account = saveIdentifier
    private var isUploading = false

    init(presenter: UIViewController) { self.presenter = presenter; super.init() }

    func showActions() {
        guard self.account == saveIdentifier, let presenter = self.presenter else { return }
        guard !self.isUploading else { presenter.showToast(toast: "me_avatar_updating".localized()); return }
        guard self.serverConfig["debug_mode"] != "1" else {
            presenter.showToast(toast: "me_avatar_debug_unsupported".localized())
            return
        }
        guard presenter.presentedViewController == nil else { return }
        let actions = [ActionSheetItem(title: "input_extension_menu_photo".chat.localize, type: .normal, tag: "Photo", image: UIImage(named: "photo", in: .chatBundle, with: nil)), ActionSheetItem(title: "input_extension_menu_camera".chat.localize, type: .normal, tag: "Camera", image: UIImage(named: "camera_fill", in: .chatBundle, with: nil))]
        DialogManager.shared.showActions(actions: actions) { [weak self] item in
            if item.tag == "Photo" { self?.showPicker(source: .photoLibrary) }
            if item.tag == "Camera" { self?.requestCamera() }
        }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: self.showPicker(source: .camera)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.showPicker(source: .camera) }
                    else { self?.showUnavailable(source: .camera) }
                }
            }
        default: self.showUnavailable(source: .camera)
        }
    }

    private func showUnavailable(source: UIImagePickerController.SourceType) {
        guard self.account == saveIdentifier else { return }
        DialogManager.shared.showAlert(title: "permissions disable".chat.localize, content: (source == .camera ? "camera_disable" : "photo_disable").chat.localize, showCancel: false, showConfirm: true) { _ in }
    }

    private func showPicker(source: UIImagePickerController.SourceType) {
        guard self.account == saveIdentifier, let presenter = self.presenter else { return }
        guard UIImagePickerController.isSourceTypeAvailable(source) else { self.showUnavailable(source: source); return }
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.mediaTypes = [kUTTypeImage as String]
        picker.allowsEditing = true
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        picker.dismiss(animated: true) { [weak self] in
            guard let image = image else { return }
            self?.upload(image: image.fixOrientation())
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }

    func upload(image: UIImage) {
        guard self.account == saveIdentifier, !self.isUploading else { return }
        self.isUploading = true
        self.presenter?.showToast(toast: "me_avatar_updating".localized())
        EasemobRequest.shared.uploadImage(image: image) { [weak self] error, result in
            DispatchQueue.main.async {
                guard let self = self, self.account == saveIdentifier else { return }
                guard error == nil, let url = result?["avatarUrl"] as? String, !url.isEmpty else {
                    self.finish(error: (error as? EasemobError)?.message ?? error?.localizedDescription ?? "me_avatar_update_failed".localized())
                    return
                }
                guard let manager = ChatClient.shared().userInfoManager else { self.finish(error: "me_avatar_update_failed".localized()); return }
                manager.updateOwnUserInfo(url, with: .avatarURL) { [weak self] _, error in
                    DispatchQueue.main.async {
                        guard let self = self, self.account == saveIdentifier else { return }
                        if let error = error { self.finish(error: error.errorDescription ?? "me_avatar_update_failed".localized()); return }
                        self.commitAvatar(url: url)
                    }
                }
            }
        }
    }

    private func commitAvatar(url: String) {
        let id = ChatUIKitContext.shared?.currentUserId ?? ""
        let existing = (EaseChatProfile.select(where: "id = ?", values: [id]) as? [EaseChatProfile])?.first
        let profile = existing ?? EaseChatProfile()
        profile.id = id
        profile.nickname = ChatUIKitContext.shared?.currentUser?.nickname ?? profile.nickname
        profile.remark = ChatUIKitContext.shared?.currentUser?.remark ?? profile.remark
        profile.avatarURL = url
        profile.modifyTime = Int64(Date().timeIntervalSince1970 * 1000)
        if existing == nil { profile.insert() } else { profile.updateFFDB() }
        ChatUIKitContext.shared?.currentUser = profile
        ChatUIKitContext.shared?.updateChatAndUserTypeCaches(profiles: [profile])
        CallKitManager.shared.currentUserInfo?.avatarURL = url
        CallKitManager.shared.usersCache[id]?.avatarURL = url
        self.isUploading = false
        NotificationCenter.default.post(name: NSNotification.Name(userAvatarUpdated), object: nil)
        self.presenter?.showToast(toast: "me_avatar_updated".localized())
    }

    private func finish(error: String) {
        self.isUploading = false
        self.presenter?.showToast(toast: error)
    }
}


extension PersonalInfoViewController: EaseChatUIKit.ThemeSwitchProtocol {
    func switchTheme(style: EaseChatUIKit.ThemeStyle) {
        self.view.backgroundColor(style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98)
        self.infoList.reloadData()
    }
}


extension UIImage {
    func fixOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        
        var transform: CGAffineTransform = .identity
          
        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            fatalError()
        }
        
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        @unknown default:
            fatalError()
        }
        
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: cgImage!.bitsPerComponent, bytesPerRow: 0, space: cgImage!.colorSpace!, bitmapInfo: cgImage!.bitmapInfo.rawValue)!
        context.concatenate(transform)
        
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage!, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            context.draw(cgImage!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        
        let cgImage: CGImage = context.makeImage()!
        return UIImage(cgImage: cgImage)
    }
}
