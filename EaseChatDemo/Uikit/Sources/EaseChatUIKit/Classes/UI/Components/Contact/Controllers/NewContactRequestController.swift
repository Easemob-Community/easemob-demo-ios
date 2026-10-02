//
//  NewRequestViewController.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/24.
//

import UIKit

@objc open class NewContactRequestController: UIViewController {
        
    private let requestStore = FriendRequestStore()
    private var processingUserIds = Set<String>()
    
    public let contactService: ContactServiceImplement = ChatUIKitClient.shared.contactService as? ContactServiceImplement ?? ContactServiceImplement()
    
    public lazy var datas: [NewContactRequest] = {
        self.fillDatas()
    }()
    
    public private(set) lazy var navigation: ChatNavigationBar = {
        self.createNavigation()
    }()
    
    @objc open func createNavigation() -> ChatNavigationBar {
        ChatNavigationBar( showLeftItem: true, textAlignment: .left, hiddenAvatar: true)
    }
    
    public private(set) lazy var requestList: UITableView = {
        UITableView(frame: CGRect(x: 0, y: self.navigation.frame.maxY, width: self.view.frame.width, height: self.view.frame.height), style: .plain).tableFooterView(UIView()).delegate(self).dataSource(self).rowHeight(Appearance.contact.rowHeight).backgroundColor(.clear).separatorStyle(.none)
    }()
    
    public private(set) lazy var empty: EmptyStateView = {
        EmptyStateView(frame: CGRect(x: 0, y: 0, width: self.requestList.frame.width, height: self.requestList.frame.height),emptyImage: UIImage(chatNamed: "empty"), onRetry: {
            
        }).backgroundColor(.clear)
    }()
    

    open override func viewDidLoad() {
        super.viewDidLoad()
        self.navigation.title = "New Request".chat.localize
        self.datas.sort { $0.time > $1.time }
        self.view.addSubViews([self.navigation,self.requestList])
        // Do any additional setup after loading the view.
        //Back button click of the navigation
        self.navigation.clickClosure = { [weak self] in
            self?.navigationClick(type: $0, indexPath: $1)
        }
        if self.datas.count <= 0 {
            self.requestList.backgroundView = self.empty
        } else {
            self.requestList.backgroundView = nil
        }
        self.requestProfiles()
        NotificationCenter.default.addObserver(self, selector: #selector(requestHistoryDidChange(_:)), name: FriendRequestStore.didChange, object: nil)
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func requestHistoryDidChange(_ notification: Notification) {
        guard notification.object as? String == self.requestStore.ownerIdentifier else { return }
        self.reloadRequests()
        self.requestProfiles()
    }

    private func reloadRequests() {
        self.datas = self.fillDatas().sorted { $0.time > $1.time }
        self.requestList.backgroundView = self.datas.isEmpty ? self.empty : nil
        self.requestList.reloadData()
    }
    
    @objc open func requestProfiles() {
        var userIds = [String]()
        for user in self.datas {
            if !user.nickname.isEmpty && !user.avatarURL.isEmpty {
                continue
            }
            userIds.append(user.userId)
        }
        userIds = Array(Set(userIds))
        guard !userIds.isEmpty else { return }
        if ChatUIKitContext.shared?.userProfileProvider != nil {
            Task(priority: .background) { [weak self] in
                let profiles = await ChatUIKitContext.shared?.userProfileProvider?.fetchProfiles(profileIds: userIds) ?? []
                self?.refreshProfiles(profiles: profiles, unknownInfoMaps: [:])
            }
        } else {
            if ChatUIKitContext.shared?.userProfileProviderOC != nil {
                ChatUIKitContext.shared?.userProfileProviderOC?.fetchProfiles(profileIds: userIds, completion: { [weak self] profiles in
                    self?.refreshProfiles(profiles: profiles, unknownInfoMaps: [:])
                })
            }
        }
    }
    
    @objc open func navigationClick(type: ChatNavigationBarClickEvent,indexPath: IndexPath?) {
        switch type {
        case .back: self.pop()
        default: break
        }
    }
    
    @objc open func pop() {
        if self.navigationController != nil {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true)
        }
    }
    
    @objc open func fillDatas() -> [NewContactRequest] {
        self.requestStore.requests.map {
            let request = NewContactRequest()
            request.userId = ($0["userId"] as? String) ?? ""
            request.time = ($0["timestamp"] as? TimeInterval) ?? 0
            request.status = FriendRequestStore.status(of: $0)
            request.isProcessing = self.processingUserIds.contains(request.userId)
            request.avatarURL = ChatUIKitContext.shared?.userCache?[request.userId]?.avatarURL ?? ""
            request.nickname = ChatUIKitContext.shared?.userCache?[request.userId]?.nickname ?? ""
            return request
        }
    }
    
}

extension NewContactRequestController: UITableViewDelegate,UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.datas.count 
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        self.cellForRowAt(indexPath: indexPath)
    }
    
    @objc open func cellForRowAt(indexPath: IndexPath) -> UITableViewCell {
        var cell = self.requestList.dequeueReusableCell(withIdentifier: "NewContactRequestCell") as? NewContactRequestCell
        if cell == nil {
            cell = NewContactRequestCell(style: .default, reuseIdentifier: "NewContactRequestCell")
        }
        if let request = self.datas[safe: indexPath.row] {
            cell?.refresh(request: request)
        }
        cell?.agreeClosure = { [weak self] in
            self?.agreeFriendRequest(userId: $0)
        }
        cell?.backgroundColor = .clear
        cell?.contentView.backgroundColor = .clear
        cell?.selectionStyle = .none
        return cell ?? NewContactRequestCell()
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        var unknownInfoIds = [String]()
        var unknownInfoMaps = [String:IndexPath]()
        if let visiblePaths = self.requestList.indexPathsForVisibleRows {
            for indexPath in visiblePaths {
                if let nickName = self.datas[safe: indexPath.row]?.nickname,nickName.isEmpty {
                    unknownInfoIds.append(self.self.datas[safe: indexPath.row]?.userId ?? "")
                    unknownInfoMaps[self.datas[safe: indexPath.row]?.userId ?? ""] = indexPath
                }
                if let avatarURL = self.datas[safe: indexPath.row]?.avatarURL,avatarURL.isEmpty {
                    unknownInfoIds.append(self.self.datas[safe: indexPath.row]?.userId ?? "")
                    unknownInfoMaps[self.datas[safe: indexPath.row]?.userId ?? ""] = indexPath
                }
            }
        }
        
        if ChatUIKitContext.shared?.userProfileProvider != nil {
            Task(priority: .background) {
                let profiles = await ChatUIKitContext.shared?.userProfileProvider?.fetchProfiles(profileIds: unknownInfoIds) ?? []
                self.refreshProfiles(profiles: profiles, unknownInfoMaps: unknownInfoMaps)
            }
        } else {
            ChatUIKitContext.shared?.userProfileProviderOC?.fetchProfiles(profileIds: unknownInfoIds, completion: { [weak self] profiles in
                self?.refreshProfiles(profiles: profiles, unknownInfoMaps: unknownInfoMaps)
            })
        }
    }
    
    @objc open func refreshProfiles(profiles: [ChatUserProfileProtocol],unknownInfoMaps: [String:IndexPath]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // A user can have both historical and pending requests. Refresh all
            // matching rows by ID, since new requests may have shifted indices.
            for profile in profiles {
                for request in self.datas where request.userId == profile.id {
                    request.nickname = profile.nickname
                    request.avatarURL = profile.avatarURL
                }
            }
            self.requestList.reloadData()
        }
    }
    
    /**
     Agrees to a friend request from a user.

     - Parameters:
         - userId: The ID of the user who sent the friend request.

     This method sends a request to the contact service to agree to the friend request from the specified user. If the request is successful, the user is added as a new friend and a chat conversation is created. The conversation includes a custom message with a greeting.

     - Note: This method assumes that the `contactService` property is already initialized.

     - Parameter userId: The ID of the user who sent the friend request.
     */
    @objc open func agreeFriendRequest(userId: String) {
        guard self.requestStore.ownerIdentifier == saveIdentifier,
              !self.processingUserIds.contains(userId),
              self.datas.contains(where: { $0.userId == userId && $0.status == .pending }) else { return }
        self.processingUserIds.insert(userId)
        for request in self.datas where request.userId == userId {
            request.isProcessing = true
        }
        self.requestList.reloadData()
        self.contactService.agreeFriendRequest(from: userId) { [weak self] error, userId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.processingUserIds.remove(userId)
                self.reloadRequests()
                guard self.requestStore.ownerIdentifier == saveIdentifier else { return }
                if let error = error {
                    consoleLogInfo("agreeFriendRequest error: \(error.errorDescription ?? "")", type: .error)
                    self.showToast(toast: error.errorDescription ?? "")
                    return
                }
                let conversation = ChatClient.shared().chatManager?.getConversation(userId, type: .chat, createIfNotExist: true)
                let ext = ["something":("You have added".chat.localize+" "+userId+" "+"to say hello".chat.localize)]
                let message = ChatMessage(conversationID: userId, body: ChatCustomMessageBody(event: EaseChatUIKit_alert_message, customExt: nil), ext: ext)
                conversation?.insert(message, error: nil)
                
                self.requestFriendInfo(userId: userId)
                self.requestProfiles()
            }
        }
    }
    
    @objc open func requestFriendInfo(userId: String) {
        ChatClient.shared().userInfoManager?.fetchUserInfo(byId: [userId], type: [0,1],completion: { infoMap, error in
            if error != nil {
                consoleLogInfo("requestFriendInfo error:\(error?.errorDescription ?? "")", type: .error)
            }
        })
    }
}


extension NewContactRequestController: ThemeSwitchProtocol {
    open func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
    }
}
