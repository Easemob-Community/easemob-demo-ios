//
//  PrivacyPolicyViewController.swift
//  EaseChatDemo
//

import UIKit
import EaseChatUIKit

final class PrivacyPolicyViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, ThemeSwitchProtocol {
    @UserDefault("EaseChatDemoUserPhone", defaultValue: "") private var phone
    private let items = ["me_terms_of_service", "me_third_party_sharing", "Personal Information Collected"]
    private lazy var navigation = ChatNavigationBar(showLeftItem: true, textAlignment: .left, hiddenAvatar: true)
    private lazy var list: UITableView = {
        let list = UITableView(frame: .zero, style: .plain)
        list.delegate = self
        list.dataSource = self
        list.rowHeight = 54
        list.separatorStyle = .none
        list.backgroundColor = .clear
        list.tableFooterView = UIView()
        list.contentInsetAdjustmentBehavior = .never
        list.register(MeMenuCell.self, forCellReuseIdentifier: "Policy")
        return list
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubViews([self.navigation, self.list])
        self.navigation.title = "me_privacy_title".localized()
        self.navigation.separateLine.isHidden = true
        self.navigation.clickClosure = { [weak self] type, _ in
            if type == .back { self?.navigationController?.popViewController(animated: true) }
        }
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.list.frame = CGRect(x: 0, y: self.navigation.frame.maxY, width: self.view.bounds.width, height: self.view.bounds.height - self.navigation.frame.maxY)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Policy", for: indexPath) as! MeMenuCell
        cell.configure(title: self.items[indexPath.row].localized())
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller: CommonWebViewController
        switch indexPath.row {
        case 0:
            controller = CommonWebViewController(urlString: "https://www.easemob.com/demo/agreement", navigationTitle: self.items[0].localized())
        case 1:
            controller = CommonWebViewController(urlString: "https://www.easemob.com/demo/third-party-sharing", navigationTitle: self.items[1].localized())
        case 2:
            let id = ChatUIKitContext.shared?.currentUserId ?? ""
            controller = CommonWebViewController(urlString: Bundle.main.path(forResource: "person-info", ofType: "html") ?? "https://www.easemob.com/demo/personal-info-collection", navigationTitle: self.items[2].localized(), localInfo: ["username": ChatUIKitContext.shared?.currentUser?.nickname ?? id, "avatar": ChatUIKitContext.shared?.currentUser?.avatarURL ?? "", "phone": self.phone, "device": UIDevice.current.model])
        default: return
        }
        controller.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(controller, animated: true)
    }

    func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1 : UIColor.theme.neutralColor98
        self.list.reloadData()
    }
}
