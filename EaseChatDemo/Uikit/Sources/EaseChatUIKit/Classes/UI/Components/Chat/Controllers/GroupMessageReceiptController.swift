import UIKit

/// Message read-receipt details, opened from the status mark beside an outgoing group bubble.
public final class GroupMessageReceiptController: UIViewController, UITableViewDataSource, UITableViewDelegate, ThemeSwitchProtocol {
    private let model: GroupMessageReceiptViewModel
    public var readCountChanged: ((Int) -> Void)?
    private var showingUnread = false
    private let navigation = ChatNavigationBar(show: .zero, textAlignment: .left)
    private let senderAvatar = ImageView(frame: .zero)
    private let senderName = UILabel()
    private let sentTime = UILabel()
    private let summary = UITextView()
    private let separator = UIView()
    private let readTab = UIButton(type: .custom)
    private let unreadTab = UIButton(type: .custom)
    private let selectionLine = UIView()
    private let table = UITableView(frame: .zero, style: .plain)
    private let stateLabel = UILabel()
    private let retryButton = UIButton(type: .custom)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let footer = UILabel()

    public convenience init(entity: MessageEntity) {
        self.init(model: GroupMessageReceiptViewModel(entity: entity))
    }

    init(model: GroupMessageReceiptViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        navigation.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: NavigationHeight)
        navigation.title = "group_receipt_details".chat.localize
        navigation.clickClosure = { [weak self] event, _ in
            if event == .back { self?.navigationController?.popViewController(animated: true) }
        }
        senderName.font = UIFont.theme.labelMedium
        sentTime.font = UIFont.theme.bodySmall
        sentTime.textAlignment = .right
        summary.font = UIFont.theme.bodyMedium
        summary.isEditable = false
        summary.isSelectable = true
        summary.backgroundColor = .clear
        summary.textContainerInset = .zero
        summary.textContainer.lineFragmentPadding = 0
        senderAvatar.contentMode = .scaleAspectFill
        senderAvatar.clipsToBounds = true
        let profile = model.entity.message.user
        senderAvatar.image(with: profile?.avatarURL ?? "", placeHolder: Appearance.avatarPlaceHolder)
        senderName.text = model.entity.showUserName
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        sentTime.text = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(model.entity.message.timestamp) / 1000))
        if let text = model.entity.message.body as? ChatTextMessageBody {
            summary.text = text.text
        } else if let file = model.entity.message.body as? ChatFileMessageBody, model.entity.message.body.type == .file {
            summary.text = file.displayName
        } else {
            summary.text = model.entity.message.showContent
        }
        readTab.titleLabel?.font = UIFont.theme.titleMedium
        unreadTab.titleLabel?.font = UIFont.theme.titleMedium
        readTab.addTarget(self, action: #selector(selectRead), for: .touchUpInside)
        unreadTab.addTarget(self, action: #selector(selectUnread), for: .touchUpInside)
        selectionLine.layer.cornerRadius = 2
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 60
        table.dataSource = self
        table.delegate = self
        table.register(GroupReceiptMemberCell.self, forCellReuseIdentifier: "member")
        table.refreshControl = UIRefreshControl()
        table.refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        stateLabel.font = UIFont.theme.bodyMedium
        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        retryButton.titleLabel?.font = UIFont.theme.bodyMedium
        retryButton.setTitle("group_receipt_retry".chat.localize, for: .normal)
        retryButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        footer.font = UIFont.theme.bodySmall
        footer.numberOfLines = 0
        footer.textAlignment = .center
        for item in [navigation, senderAvatar, senderName, sentTime, summary, separator, readTab, unreadTab, selectionLine, table, stateLabel, retryButton, spinner] { view.addSubview(item) }
        model.changed = { [weak self] in self?.refresh() }
        model.readCountChanged = { [weak self] count in self?.readCountChanged?(count) }
        Theme.registerSwitchThemeViews(view: self)
        switchTheme(style: Theme.style)
        model.reload()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let navHeight = view.safeAreaInsets.top + 44
        navigation.frame = CGRect(x: 0, y: 0, width: width, height: navHeight)
        navigation.leftItem.frame = CGRect(x: 8, y: navHeight - 34, width: 24, height: 24)
        navigation.titleLabel.frame = CGRect(x: 32, y: navHeight - 34, width: width - 64, height: 24)
        navigation.separateLine.frame = CGRect(x: 0, y: navHeight - 0.5, width: width, height: 0.5)
        let top = navHeight + 12
        senderAvatar.frame = CGRect(x: 16, y: top, width: 28, height: 28)
        senderAvatar.layer.cornerRadius = 14
        senderName.frame = CGRect(x: 54, y: top, width: max(0, width - 126), height: 20)
        sentTime.frame = CGRect(x: width - 64, y: top, width: 48, height: 20)
        let textHeight = min(160, max(20, summary.sizeThatFits(CGSize(width: width - 70, height: .greatestFiniteMagnitude)).height))
        summary.frame = CGRect(x: 54, y: top + 22, width: width - 70, height: textHeight)
        separator.frame = CGRect(x: 54, y: summary.frame.maxY + 12, width: width - 54, height: 0.5)
        readTab.frame = CGRect(x: 0, y: separator.frame.maxY, width: width / 2, height: 48)
        unreadTab.frame = CGRect(x: width / 2, y: separator.frame.maxY, width: width / 2, height: 48)
        selectionLine.frame = CGRect(x: (showingUnread ? unreadTab : readTab).frame.midX - 14, y: readTab.frame.maxY - 8, width: 28, height: 4)
        table.frame = CGRect(x: 0, y: readTab.frame.maxY, width: width, height: max(0, view.bounds.height - readTab.frame.maxY))
        stateLabel.frame = CGRect(x: 24, y: table.frame.minY + 60, width: width - 48, height: 60)
        if retryButton.superview === view {
            retryButton.frame = CGRect(x: 24, y: stateLabel.frame.maxY, width: width - 48, height: 44)
        }
        spinner.center = CGPoint(x: width / 2, y: table.frame.minY + 36)
        footer.frame = CGRect(x: 0, y: 0, width: width, height: footer.text == nil ? 0 : 60)
    }

    @objc private func selectRead() { showingUnread = false; refresh() }
    @objc private func selectUnread() { showingUnread = true; refresh() }
    @objc private func reload() { model.reload() }

    private var people: [GroupReceiptPerson] { showingUnread ? model.unread : model.readers }

    private func refresh() {
        guard isViewLoaded else { return }
        readTab.setTitle(String(format: "group_receipt_read_count".chat.localize, model.readCount), for: .normal)
        unreadTab.setTitle(model.unreadCount.map { String(format: "group_receipt_unread_count".chat.localize, $0) } ?? "group_receipt_unread".chat.localize, for: .normal)
        readTab.accessibilityTraits = showingUnread ? .button : [.button, .selected]
        unreadTab.accessibilityTraits = showingUnread ? [.button, .selected] : .button
        let loading = showingUnread ? (model.readersLoading || model.membersLoading) : model.readersLoading
        let error = showingUnread ? (model.readersError ?? model.membersError) : model.readersError
        if loading && people.isEmpty { spinner.startAnimating() } else { spinner.stopAnimating() }
        retryButton.isHidden = error == nil || loading
        stateLabel.isHidden = loading || (error == nil && !people.isEmpty)
        stateLabel.text = error != nil ? "group_receipt_load_failed".chat.localize : (showingUnread ? "group_receipt_no_unread_members" : "group_receipt_no_read_members").chat.localize
        // Preserve partial reader pages on failure; put the retry below them instead of over a row.
        if error != nil && !people.isEmpty {
            stateLabel.isHidden = true
            table.tableFooterView = retryButton
            retryButton.frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: 44)
        } else {
            if retryButton.superview !== view { view.addSubview(retryButton) }
            footer.text = showingUnread && model.unreadReady && model.unreadIncomplete ? "group_receipt_partial_roster".chat.localize : nil
            footer.frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: footer.text == nil ? 0 : 60)
            table.tableFooterView = footer.text == nil ? UIView() : footer
        }
        if !loading { table.refreshControl?.endRefreshing() }
        applyColors()
        table.reloadData()
        view.setNeedsLayout()
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { people.count }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "member", for: indexPath) as! GroupReceiptMemberCell
        cell.refresh(people[indexPath.row])
        return cell
    }

    private func applyColors() {
        let dark = Theme.style == .dark
        view.backgroundColor = dark ? UIColor.theme.neutralColor1 : UIColor.theme.neutralColor98
        senderName.textColor = dark ? UIColor.theme.neutralSpecialColor6 : UIColor.theme.neutralSpecialColor5
        sentTime.textColor = dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5
        summary.textColor = dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        separator.backgroundColor = dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor9
        let active = dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        let inactive = dark ? UIColor.theme.neutralColor5 : UIColor.theme.neutralColor6
        readTab.setTitleColor(showingUnread ? inactive : active, for: .normal)
        unreadTab.setTitleColor(showingUnread ? active : inactive, for: .normal)
        selectionLine.backgroundColor = dark ? UIColor.theme.primaryColor6 : UIColor.theme.primaryColor5
        retryButton.setTitleColor(selectionLine.backgroundColor, for: .normal)
        stateLabel.textColor = inactive
        footer.textColor = inactive
    }

    public func switchTheme(style: ThemeStyle) {
        applyColors()
        table.reloadData()
    }
}

private final class GroupReceiptMemberCell: UITableViewCell {
    private let avatar = ImageView(frame: .zero)
    private let name = UILabel()
    private let line = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        name.font = UIFont.theme.bodyLarge
        contentView.addSubViews([avatar, name, line])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = CGRect(x: 16, y: 10, width: 40, height: 40)
        avatar.layer.cornerRadius = 20
        name.frame = CGRect(x: 68, y: 10, width: contentView.bounds.width - 84, height: 40)
        line.frame = CGRect(x: 68, y: contentView.bounds.height - 0.5, width: contentView.bounds.width - 68, height: 0.5)
    }
    func refresh(_ person: GroupReceiptPerson) {
        avatar.image(with: person.avatarURL, placeHolder: Appearance.avatarPlaceHolder)
        name.text = person.name
        name.textColor = Theme.style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        line.backgroundColor = Theme.style == .dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor9
    }
}
