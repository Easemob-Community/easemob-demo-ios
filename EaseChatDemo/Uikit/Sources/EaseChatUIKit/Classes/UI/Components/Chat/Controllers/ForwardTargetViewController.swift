//
//  ForwardTargetViewController.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2024/2/19.
//

import UIKit

@objcMembers open class ForwardTargetViewController: UIViewController {
    
    public private(set) var messages = [ChatMessage]()
    
    private var combineForward = true
    private var imageBodyIndex: Int?
    
    private var index = 0
    
    private var searchKeyWord = ""
    
    private var searchMode = false
    
    private lazy var contactService: ContactServiceProtocol = ChatUIKitClient.shared.contactService ?? ContactServiceImplement()
    
    private let groupService: GroupService = ChatUIKitClient.shared.groupService
        
    private var datas = [ChatUserProfileProtocol]() {
        didSet {
            DispatchQueue.main.async {
                if self.datas.count <= 0 {
                    self.targetsList.backgroundView = self.empty
                } else {
                    self.targetsList.backgroundView = nil
                }
            }
        }
    }
    
    private struct Target: Hashable {
        let id: String
        let type: EMChatType
    }

    private var pendingTargets = Set<Target>()
    private var forwardedTargets = Set<Target>()
    
    private var searchResults = [ChatUserProfileProtocol]()
    
    public private(set) lazy var indicator: UIView = {
        UIView(frame: CGRect(x: self.view.frame.width/2.0-18, y: 6, width: 36, height: 5)).cornerRadius(2.5).backgroundColor(UIColor.theme.neutralColor8)
    }()
    
    public private(set)  lazy var toolBar: PageContainerTitleBar = {
        PageContainerTitleBar(frame: CGRect(x: 0, y: self.indicator.frame.maxY + 4, width: self.view.frame.width, height: 44), choices: ["Contact".chat.localize,"Group".chat.localize]) { [weak self] in
            self?.index = $0
            if $0 == 0 {
                self?.targetsList.tableHeaderView = self?.searchController.searchBar
            } else {
                self?.targetsList.tableHeaderView = nil
            }
            self?.fillDatas()
        }
    }()
    
    public private(set) lazy var targetsList: UITableView = {
        UITableView(frame: CGRect(x: 0, y: self.toolBar.frame.maxY, width: self.view.frame.width, height: self.view.frame.height-self.toolBar.frame.maxY-StatusBarHeight), style: .plain).delegate(self).dataSource(self).tableFooterView(UIView()).rowHeight(60).separatorStyle(.none).showsVerticalScrollIndicator(false).tableFooterView(UIView()).backgroundColor(.clear).tableHeaderView(self.searchController.searchBar)
    }()
    
    public private(set) lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        searchController.hidesNavigationBarDuringPresentation = true
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.automaticallyShowsSearchResultsController = true
        searchController.showsSearchResultsController = true
        searchController.automaticallyShowsScopeBar = false
        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.delegate = self
        return searchController
    }()
    
    public private(set) lazy var empty: EmptyStateView = {
        EmptyStateView(frame: self.targetsList.bounds,emptyImage: UIImage(chatNamed: "empty"), onRetry: { [weak self] in

        }).backgroundColor(.clear)
    }()
    
    public var dismissClosure: ((Bool) -> Void)?
    
    public required init(messages: [ChatMessage],combine: Bool = true) {
        self.messages = messages
        self.combineForward = combine
        super.init(nibName: nil, bundle: nil)
    }

    public convenience init(message: ChatMessage, imageBodyIndex: Int) {
        self.init(messages: [message], combine: false)
        self.imageBodyIndex = imageBodyIndex
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.contactService.unregisterEmergencyListener(listener: self)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.dismissClosure?(!self.forwardedTargets.isEmpty)
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.view.cornerRadius(.medium, [.topLeft,.topRight], .clear, 0)
        self.view.addSubViews([self.indicator,self.toolBar,self.targetsList])
        // Do any additional setup after loading the view.
        self.targetsList.keyboardDismissMode = .onDrag
        self.contactService.registerEmergencyListener(listener: self)
        self.fillDatas()
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    
    open func fillDatas() {
        if self.index == 0 {
            self.fetchContacts()
        } else {
            self.fetchGroups()
        }
    }
   
    open func fetchContacts() {
        if let contacts = ChatClient.shared().contactManager?.getAllContacts() {
            self.datas.removeAll()
            self.datas = contacts.map { self.profile(from: $0) }
            self.targetsList.reloadData()
        }
    }
    
    private func profile(from contact: Contact) -> ChatUserProfileProtocol {
        let profile = ChatUserProfile()
        profile.id = contact.userId
        profile.nickname = contact.userInfo?.nickname ?? ChatUIKitContext.shared?.userProfile(id: contact.userId)?.nickname ?? ""
        profile.remark = contact.remark ?? ""
        profile.avatarURL = contact.userInfo?.avatarUrl ?? ChatUIKitContext.shared?.userProfile(id: contact.userId)?.avatarURL ?? ""
        return profile
    }
    
    open func fetchGroups() {
        // SDK 5.0 removed the server fetch API. Joined groups are synced by the SDK after login,
        // so read them all from the local database via the group service.
        let groups = self.groupService.loadLocalJoinedGroups()
        self.datas = groups.compactMap { ChatUIKitContext.shared?.groupProfile(group: $0) }
        self.targetsList.reloadData()
    }
}

extension ForwardTargetViewController: ContactEmergencyListener {
    public func onResult(error: ChatError?, type: ContactEmergencyType, operatorId: String) {
        guard type == .fetchContacts,self.index == 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.fetchContacts()
        }
    }
}

extension ForwardTargetViewController: ThemeSwitchProtocol {
    public func switchTheme(style: ThemeStyle) {
        self.searchController.searchBar.backgroundColor(style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98)
        self.searchController.searchBar.barStyle = style == .dark ? .black:.default
        self.searchController.searchBar.searchTextField.textColor = style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1
        self.view.backgroundColor(style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98)
        self.targetsList.reloadData()
    }
    
    
}

extension ForwardTargetViewController: UITableViewDelegate,UITableViewDataSource {
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.searchMode {
            return self.searchResults.count
        } else {
            return self.datas.count
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "ForwardTargetCell") as? ForwardTargetCell
        if cell == nil {
            cell = ForwardTargetCell(style: .default, reuseIdentifier: "ForwardTargetCell")
        }
        cell?.selectionStyle = .none
        if let info = (self.searchMode ? self.searchResults : self.datas)[safe: indexPath.row] {
            let target = Target(id: info.id, type: self.index == 0 ? .chat : .groupChat)
            let state: ForwardTargetState = self.forwardedTargets.contains(target) ? .forwarded : .normal
            cell?.refresh(info: info, keyword: self.searchMode ? self.searchKeyWord : "", forward: state)
        }
        
        cell?.actionClosure = { [weak self] in
            if let forwardIndexPath = tableView.indexPath(for: $0) {
                self?.forwardMessages(indexPath: forwardIndexPath)
            }
        }
        return cell ?? UITableViewCell()
    }
    
    @objc open func forwardMessages(indexPath: IndexPath) {
        guard let original = self.messages.first,
              let profile = (self.searchMode ? self.searchResults : self.datas)[safe: indexPath.row] else { return }
        let target = Target(id: profile.id, type: self.index == 0 ? .chat : .groupChat)
        guard !self.pendingTargets.contains(target), !self.forwardedTargets.contains(target) else { return }

        let message: ChatMessage
        if self.combineForward {
            let body = ChatCombineMessageBody(title: "Chat History".chat.localize, summary: self.forwardSummary(), compatibleText: "[Chat History]", messageIdList: self.messages.filter({ChatClient.shared().chatManager?.getMessageWithMessageId($0.messageId)?.status == .succeed}).map({ $0.messageId }))
            message = ChatMessage(conversationID: target.id, body: body, ext: nil)
        } else if let imageBodyIndex {
            let directory = ChatClient.shared().chatManager?.getMessageAttachmentPath(target.id)
            guard let image = original.bodies[safe: imageBodyIndex] as? ChatImageMessageBody,
                  let body = self.copyForwardAttachment(image, attachmentPath: directory) else {
                self.showToast(toast: "Failed to forward message".chat.localize)
                return
            }
            message = ChatMessage(conversationID: target.id, body: body, ext: nil)
        } else if original.isCompositeMessage {
            guard let composite = self.compositeForward(from: original, to: target.id) else {
                self.showToast(toast: "Unable to forward composite message".chat.localize)
                return
            }
            message = composite
        } else {
            message = ChatMessage(conversationID: target.id, body: original.body, ext: nil)
        }

        message.chatType = target.type
        message.isNeedReadReceipt = true
        self.pendingTargets.insert(target)
        ChatServiceImplement(to: target.id).send(message: message, completion: { [weak self] error, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingTargets.remove(target)
                if error == nil {
                    self.forwardedTargets.insert(target)
                    self.targetsList.reloadData()
                } else {
                    self.showToast(toast: error?.errorDescription ?? "Failed to forward message".chat.localize)
                    consoleLogInfo("ForwardTargetViewController forwardMessages error:\(error?.errorDescription ?? "")", type: .error)
                }
            }
        })
    }

    private func compositeForward(from original: ChatMessage, to conversationID: String) -> ChatMessage? {
        let attachmentPath = ChatClient.shared().chatManager?.getMessageAttachmentPath(conversationID)
        let originalBodies = original.bodies
        let bodies = originalBodies.compactMap { self.copyForwardBody($0, attachmentPath: attachmentPath) }
        guard bodies.count == originalBodies.count, bodies.count > 1 else { return nil }

        var ext = original.ext
        ext?.removeValue(forKey: groupReceiptRecipientCountKey)
        return ChatMessage(conversationID: conversationID, bodies: bodies, ext: ext)
    }

    private func copyForwardBody(_ body: ChatMessageBody, attachmentPath: String?) -> ChatMessageBody? {
        switch body {
        case let text as ChatTextMessageBody:
            return ChatTextMessageBody(text: text.text)
        case let location as ChatLocationMessageBody:
            return ChatLocationMessageBody(latitude: location.latitude, longitude: location.longitude,
                                           address: location.address, buildingName: location.buildingName)
        case let custom as ChatCustomMessageBody:
            return ChatCustomMessageBody(event: custom.event, customExt: custom.customExt)
        case let file as ChatFileMessageBody:
            return self.copyForwardAttachment(file, attachmentPath: attachmentPath)
        default:
            return nil
        }
    }

    private func copyForwardAttachment(_ source: ChatFileMessageBody, attachmentPath: String?) -> ChatFileMessageBody? {
        guard let attachmentPath, !attachmentPath.isEmpty else { return nil }

        let image = source as? ChatImageMessageBody
        let originalURL = self.forwardableURL(source.remotePath)
        let largeImageURL = self.forwardableURL(image?.bigImageRemotePath)
        let thumbnailURL = self.forwardableURL(image?.thumbnailRemotePath)
        guard let remotePath = originalURL ?? largeImageURL ?? thumbnailURL else { return nil }
        let usesThumbnail = originalURL == nil && largeImageURL == nil

        // Give the new message its own download destinations and keep the original message's cached files separate.
        let destination = URL(fileURLWithPath: attachmentPath, isDirectory: true).appendingPathComponent(UUID().uuidString)
        let name = source.displayName ?? ""
        let fileExtension = (name as NSString).pathExtension
        let localPath = fileExtension.isEmpty ? destination.path : destination.appendingPathExtension(fileExtension).path
        let thumbnailPath = destination.appendingPathExtension("thumbnail").path

        let attachment: ChatFileMessageBody
        switch source {
        case let image as ChatImageMessageBody:
            let copy = ChatImageMessageBody(localPath: localPath, displayName: name)
            copy.size = usesThumbnail ? image.thumbnailSize : image.size
            copy.isGif = image.isGif
            copy.isOriginalImage = usesThumbnail || image.isOriginalImage
            copy.thumbnailLocalPath = thumbnailPath
            copy.thumbnailRemotePath = image.thumbnailRemotePath
            // A separately uploaded thumbnail can have a different share secret from the original image.
            copy.thumbnailSecretKey = image.thumbnailSecretKey
            copy.thumbnailSize = image.thumbnailSize
            copy.thumbnailFileLength = image.thumbnailFileLength
            attachment = copy
        case let video as ChatVideoMessageBody:
            let copy = ChatVideoMessageBody(localPath: localPath, displayName: name)
            copy.duration = video.duration
            copy.thumbnailLocalPath = thumbnailPath
            copy.thumbnailRemotePath = video.thumbnailRemotePath
            copy.thumbnailSecretKey = video.thumbnailSecretKey
            copy.thumbnailSize = video.thumbnailSize
            attachment = copy
        case let voice as ChatAudioMessageBody:
            let copy = ChatAudioMessageBody(localPath: localPath, displayName: name)
            copy.duration = voice.duration
            attachment = copy
        default:
            guard source.type == .file else { return nil }
            attachment = ChatFileMessageBody(localPath: localPath, displayName: name)
        }
        attachment.remotePath = remotePath
        if usesThumbnail, let image {
            attachment.secretKey = image.thumbnailSecretKey
            attachment.fileLength = image.thumbnailFileLength
        } else {
            attachment.secretKey = source.secretKey
            attachment.fileLength = source.fileLength
        }
        return attachment
    }

    private func forwardableURL(_ value: String?) -> String? {
        guard let value, let url = URLComponents(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return value
    }
    
    @objc open func forwardSummary() -> String {
        var summary = ""
        for (index,message) in self.messages.enumerated() {
            if index <= 3 {
                let nickname = message.user?.nickname ?? message.from
                if index == 0 {
                    summary += (nickname+":"+message.showType+"\n")
                } else {
                    if index <= 3 {
                        summary += (nickname+":"+message.showType+"\n")
                    }
                }
            } else {
                break
            }
        }
        return summary
    }
    
}

extension ForwardTargetViewController: UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {
    
    public func updateSearchResults(for searchController: UISearchController) {
        searchController.searchResultsController?.view.isHidden = false
        self.searchKeyWord = searchController.searchBar.text?.lowercased() ?? ""
        if let searchText = searchController.searchBar.text?.lowercased() {
            self.searchResults = self.datas.filter({ user in
                let showName = user.nickname.isEmpty ? user.id:user.nickname
                return (showName.lowercased() as NSString).range(of: searchText).location != NSNotFound && (showName.lowercased() as NSString).range(of: searchText).length >= 0
            })
        }
        self.targetsList.reloadData()
    }
    
    public func willPresentSearchController(_ searchController: UISearchController) {
        self.searchController = searchController
    }
    
    public func didPresentSearchController(_ searchController: UISearchController) {
        
    }
    
    public func willDismissSearchController(_ searchController: UISearchController) {
        
    }
    
    public func didDismissSearchController(_ searchController: UISearchController) {
        
    }
    
    public func presentSearchController(_ searchController: UISearchController) {
        self.searchMode = true
        UIView.animate(withDuration: 0.25) {
            self.indicator.alpha = 0
            self.toolBar.alpha = 0
            self.targetsList.frame = CGRect(x: 0, y: 10, width: self.view.frame.width, height: self.view.frame.height-10)
        }
        self.targetsList.reloadData()
    }
    
    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.searchMode = false
        self.searchResults.removeAll()
        UIView.animate(withDuration: 0.25) {
            self.indicator.alpha = 1
            self.toolBar.alpha = 1
            self.toolBar.frame =  CGRect(x: 0, y: self.indicator.frame.maxY + 4, width: self.view.frame.width, height: 44)
            self.targetsList.frame = CGRect(x: 0, y: self.toolBar.frame.maxY, width: self.view.frame.width, height: self.view.frame.height-self.toolBar.frame.maxY-StatusBarHeight)
        }
        self.targetsList.reloadData()
    }
    
    
}
