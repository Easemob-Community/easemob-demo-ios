//
//  FraudAlertView.swift
//  EaseChatDemo
//

import UIKit
import EaseChatUIKit

final class FraudAlertView: UIView {
    private let warningColor = UIColor(red: 0.92, green: 0.31, blue: 0, alpha: 1)
    private let titleLabel = UILabel()
    private let container = UIView()
    private let fraudIcon = UIImageView()
    private let close = UIButton(type: .custom)
    let fraudContent = LinkRecognizeTextView(frame: .zero)
    var closeClosure: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.container.backgroundColor = UIColor(red: 1, green: 232.0 / 255, blue: 179.0 / 255, alpha: 1)
        self.container.layer.cornerRadius = 8
        self.addSubview(self.container)
        [self.fraudIcon, self.titleLabel, self.fraudContent, self.close].forEach(self.container.addSubview)

        self.fraudIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
        self.fraudIcon.tintColor = self.warningColor
        self.fraudIcon.contentMode = .scaleAspectFit
        self.titleLabel.text = "fraud_alert_title".localized()
        self.titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        self.titleLabel.textColor = UIColor(red: 23.0 / 255, green: 26.0 / 255, blue: 28.0 / 255, alpha: 1)
        self.titleLabel.numberOfLines = 0
        self.titleLabel.accessibilityTraits = .header

        self.fraudContent.backgroundColor = .clear
        self.fraudContent.isEditable = false
        self.fraudContent.isScrollEnabled = false
        self.fraudContent.contentInset = .zero
        self.fraudContent.textContainerInset = .zero
        self.fraudContent.textContainer.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: self.titleLabel.textColor!,
            .paragraphStyle: paragraph
        ]
        let content = NSMutableAttributedString(string: "fraud_alert".localized() + " ", attributes: attributes)
        var reportAttributes = attributes
        reportAttributes[.foregroundColor] = self.warningColor
        reportAttributes[.font] = UIFont.systemFont(ofSize: 12, weight: .medium)
        content.append(NSAttributedString(string: "Click report".localized(), attributes: reportAttributes))
        self.fraudContent.attributedText = content

        self.close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)), for: .normal)
        self.close.tintColor = UIColor(red: 70.0 / 255, green: 80.0 / 255, blue: 87.0 / 255, alpha: 1)
        self.close.accessibilityLabel = "fraud_alert_close".localized()
        self.close.addTarget(self, action: #selector(closeAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let cardWidth = max(1, size.width - 26)
        let titleHeight = ceil(self.titleLabel.sizeThatFits(CGSize(width: max(1, cardWidth - 80), height: .greatestFiniteMagnitude)).height)
        let bodyHeight = ceil(self.fraudContent.sizeThatFits(CGSize(width: max(1, cardWidth - 50), height: .greatestFiniteMagnitude)).height)
        return CGSize(width: size.width, height: 8 + 12 + titleHeight + 4 + bodyHeight + 12 + 8)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.container.frame = CGRect(x: 13, y: 8, width: max(0, self.bounds.width - 26), height: max(0, self.bounds.height - 16))
        let width = self.container.bounds.width
        let titleHeight = ceil(self.titleLabel.sizeThatFits(CGSize(width: max(1, width - 80), height: .greatestFiniteMagnitude)).height)
        self.titleLabel.frame = CGRect(x: 36, y: 12, width: max(0, width - 80), height: titleHeight)
        self.fraudIcon.frame = CGRect(x: 14, y: 13, width: 13, height: 13)
        self.close.frame = CGRect(x: width - 40, y: 0, width: 40, height: 40)
        self.fraudContent.frame = CGRect(x: 36, y: self.titleLabel.frame.maxY + 4, width: max(0, width - 50), height: max(0, self.container.bounds.height - self.titleLabel.frame.maxY - 16))
    }

    @objc private func closeAction() {
        self.isHidden = true
        self.closeClosure?()
    }
}
