import UIKit

@objc public enum ContactDisplayStyle: UInt {
    case normal
    case withCheckBox
}

@objc open class ContactCell: UITableViewCell {
    
    public private(set) lazy var checkbox: UIImageView = {
        self.createCheckbox()
    }()
    
    @objc open func createCheckbox() -> UIImageView {
        UIImageView(frame: CGRect(x: 16, y: (self.contentView.frame.height-28)/2.0, width: 28, height: 28)).contentMode(.scaleAspectFit).backgroundColor(.clear)
    }
    
    public private(set) lazy var avatar: ImageView = {
        self.createAvatar()
    }()
    
    @objc open func createAvatar() -> ImageView {
        ImageView(frame: CGRect(x: self.display == .normal ? 16:self.checkbox.frame.maxX+12, y: (self.contentView.frame.height-40)/2.0, width: 40, height: 40)).contentMode(.scaleAspectFill).backgroundColor(.clear).cornerRadius(Appearance.avatarRadius)
    }
    
    public private(set) lazy var nickName: UILabel = {
        self.createNickName()
    }()
    
    @objc open func createNickName() -> UILabel {
        let font = UIFont.theme.titleMedium
        let height = ceil(font.lineHeight)
        return UILabel(frame: CGRect(x: self.avatar.frame.maxX+12, y: self.avatar.frame.midY-height/2, width: self.contentView.frame.width-self.avatar.frame.maxX-12-30, height: height)).font(font).backgroundColor(.clear).textColor(UIColor.theme.neutralColor1)
    }
    
    public private(set) lazy var separatorLine: UIView = {
        self.createSeparatorLine()
    }()
    
    @objc open func createSeparatorLine() -> UIView {
        UIView(frame: CGRect(x: self.nickName.frame.minX, y: self.contentView.frame.height-0.5, width: self.contentView.frame.width-self.nickName.frame.minX, height: 0.5))
    }
    
    public var display = ContactDisplayStyle.normal
    
    @objc public required init(displayStyle: ContactDisplayStyle,identifier: String?) {
        super.init(style: .default, reuseIdentifier: identifier)
        self.display = displayStyle
        if displayStyle == .normal {
            self.contentView.addSubViews([self.avatar,self.nickName,self.separatorLine])
        } else {
            self.contentView.addSubViews([self.checkbox,self.avatar,self.nickName,self.separatorLine])
        }
        self.contentView.backgroundColor = .clear
        self.backgroundColor = .clear
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    
    @objc open func refresh(profile: ChatUserProfileProtocol) {
        self.avatar.cornerRadius(Appearance.avatarRadius)
        var showName = ChatUIKitContext.shared?.userProfile(id: profile.id)?.remark ?? ""
        if showName.isEmpty {
            showName = ChatUIKitContext.shared?.userProfile(id: profile.id)?.nickname ?? ""
        }
        if showName.isEmpty {
            showName = profile.id
        }
        var avatarURL = profile.avatarURL
        if avatarURL.isEmpty {
            avatarURL = ChatUIKitContext.shared?.userProfile(id: profile.id)?.avatarURL ?? ""
        }
        self.avatar.image(with: avatarURL, placeHolder: Appearance.conversation.singlePlaceHolder)
        self.nickName.text = showName
        self.setNeedsLayout()
        if self.display == .withCheckBox {
            self.checkbox.image = UIImage(chatNamed: profile.selected ? "select":"unselect")
        }
        self.checkbox.isHidden = self.display != .withCheckBox
    }
    
    @objc public func refresh(profile: ChatUserProfileProtocol,keyword: String) {
        var showName = ChatUIKitContext.shared?.userProfile(id: profile.id)?.remark ?? ""
        if showName.isEmpty {
            showName = ChatUIKitContext.shared?.userProfile(id: profile.id)?.nickname ?? ""
        }
        if showName.isEmpty {
            showName = profile.id
        }
        var avatarURL = profile.avatarURL
        if avatarURL.isEmpty {
            avatarURL = ChatUIKitContext.shared?.userProfile(id: profile.id)?.avatarURL ?? ""
        }
        self.nickName.attributedText = self.highlightKeywords(keyword: keyword, in: showName)
        self.setNeedsLayout()
        self.avatar.image(with: avatarURL, placeHolder: Appearance.conversation.singlePlaceHolder)
        if self.display == .withCheckBox {
            self.checkbox.image = UIImage(chatNamed: profile.selected ? "select":"unselect")
        }
        self.checkbox.isHidden = self.display != .withCheckBox
    }
    
    @objc public func highlightKeywords(keyword: String, in string: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString {
            AttributedText(string).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1).font(Font.theme.titleMedium)
        }
        if !keyword.isEmpty {
            var range = (string as NSString).range(of: keyword, options: .caseInsensitive)
            while range.location != NSNotFound {
                attributedString.addAttribute(.foregroundColor, value: Theme.style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor, range: range)
                let remainingRange = NSRange(location: range.location + range.length, length: string.count - (range.location + range.length))
                range = (string as NSString).range(of: keyword, options: .caseInsensitive, range: remainingRange)
            }
        }
        return attributedString
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        self.checkbox.frame = CGRect(x: 16, y: (self.contentView.frame.height-28)/2.0, width: 28, height: 28)
        self.avatar.frame = CGRect(x: self.display == .normal ? 16:self.checkbox.frame.maxX+12, y: (self.contentView.frame.height-40)/2.0, width: 40, height: 40)
        let nameX = self.avatar.frame.maxX + 12
        let nameWidth = max(0, self.contentView.bounds.width - nameX - 30)
        let fittingSize = self.nickName.sizeThatFits(CGSize(width: nameWidth, height: .greatestFiniteMagnitude))
        let nameHeight = min(self.contentView.bounds.height, ceil(max(self.nickName.font.lineHeight, fittingSize.height)))
        self.nickName.frame = CGRect(x: nameX, y: self.contentView.bounds.midY - nameHeight / 2, width: nameWidth, height: nameHeight)
        self.separatorLine.frame = CGRect(x: self.nickName.frame.minX, y: self.contentView.frame.height-0.5, width: self.contentView.frame.width-self.nickName.frame.minX, height: 0.5)
    }
    
    internal override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ContactCell: ThemeSwitchProtocol {
    public func switchTheme(style: ThemeStyle) {
        self.nickName.textColor = style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1
        self.separatorLine.backgroundColor = style == .dark ? UIColor.theme.neutralColor2:UIColor.theme.neutralColor9
    }
    
    
}
