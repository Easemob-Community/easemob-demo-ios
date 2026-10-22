//
//  MeMenuCell.swift
//  EaseChatDemo
//

import UIKit
import EaseChatUIKit

final class MeMenuCell: UITableViewCell, ThemeSwitchProtocol {
    private let title = UILabel()
    private let detail = UILabel()
    private let indicator = UIImageView()
    private let separatorLine = UIView()
    private var isLink = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
        self.title.font = UIFont.theme.bodyLarge
        self.detail.font = UIFont.theme.bodyMedium
        self.detail.textAlignment = .right
        self.indicator.contentMode = .scaleAspectFit
        self.indicator.image = UIImage(named: "chevron_right", in: .chatBundle, with: nil)?.withRenderingMode(.alwaysTemplate)
        self.contentView.addSubViews([self.title, self.detail, self.indicator, self.separatorLine])
        self.isAccessibilityElement = true
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String = "", navigable: Bool = true, link: Bool = false, selectable: Bool = true) {
        self.title.text = title
        self.detail.text = detail
        self.indicator.isHidden = !navigable
        self.isLink = link
        self.selectionStyle = selectable ? .default : .none
        self.accessibilityLabel = title
        self.accessibilityValue = detail
        self.accessibilityTraits = link ? .link : (selectable ? .button : .staticText)
        self.switchTheme(style: Theme.style)
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.contentView.bounds.width
        let height = self.contentView.bounds.height
        let right = self.indicator.isHidden ? CGFloat(16) : CGFloat(40)
        let detailWidth = min(width * 0.64, self.detail.sizeThatFits(CGSize(width: width, height: 22)).width)
        self.title.frame = CGRect(x: 16, y: (height - 24) / 2, width: max(0, width - 16 - right - (detailWidth > 0 ? detailWidth + 12 : 0)), height: 24)
        self.detail.frame = CGRect(x: width - right - detailWidth, y: (height - 22) / 2, width: detailWidth, height: 22)
        self.indicator.frame = CGRect(x: width - 32, y: (height - 16) / 2, width: 16, height: 16)
        self.separatorLine.frame = CGRect(x: 16, y: height - 0.5, width: width - 16, height: 0.5)
    }

    func switchTheme(style: ThemeStyle) {
        self.title.textColor = style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1
        self.detail.textColor = self.isLink ? (style == .dark ? UIColor.theme.primaryDarkColor : UIColor.theme.primaryLightColor) : (style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor5)
        self.indicator.tintColor = style == .dark ? UIColor.theme.neutralColor6 : UIColor.theme.neutralColor3
        self.separatorLine.backgroundColor = style == .dark ? UIColor.theme.neutralColor2 : UIColor.theme.neutralColor9
    }
}
