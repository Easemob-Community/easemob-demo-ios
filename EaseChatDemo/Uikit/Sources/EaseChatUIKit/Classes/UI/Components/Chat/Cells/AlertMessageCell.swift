//
//  AlertMessageCell.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/12/4.
//

import UIKit

@objc open class AlertMessageCell: MessageCell {
    
    public private(set) lazy var time: UILabel = {
        UILabel(frame: CGRect(x: 16, y: 16, width: ScreenWidth-32, height: 16)).textAlignment(.center).backgroundColor(.clear).font(UIFont.theme.bodySmall)
    }()
    
    public private(set) lazy var content: UILabel = {
        UILabel(frame: CGRect(x: 16, y: 32, width: ScreenWidth-32, height: 16)).textAlignment(.center).numberOfLines(0).lineBreakMode(.byWordWrapping).backgroundColor(.clear).tag(bubbleTag)
    }()

    internal override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc required public init(towards: BubbleTowards, reuseIdentifier: String) {
        super.init(towards: towards, reuseIdentifier: reuseIdentifier)
        self.status.isHidden = true
        self.nickName.isHidden = true
        self.avatar.isHidden = true
        self.messageDate.isHidden = true
        self.replyContent.isHidden = true
        self.bubbleWithArrow.isHidden = true
        self.bubbleMultiCorners.isHidden = true
        self.topicView.isHidden = true
        self.checkbox.isHidden = true
        self.reactionView.isHidden = true
        self.contentView.addSubViews([self.time,self.content])
        self.addGestureTo(view: self.content, target: self)
        self.switchTheme(style: Theme.style)
    }
    
    open override func clickAction(gesture: UITapGestureRecognizer) {
        if !self.entity.message.alertMessageThreadId.isEmpty {
            self.clickAction?(.cell,self.entity)
        }
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        if self.entity.isTimeDivider {
            self.time.frame = CGRect(x: 16, y: (self.contentView.bounds.height-16)/2, width: ScreenWidth-32, height: 16)
        } else {
            // An alert message only shows its content, and the content sizes itself to fit the text.
            let width = ScreenWidth-32
            let maxHeight = max(self.contentView.bounds.height-16,16)
            let height = min(max(self.content.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height.rounded(.up),16),maxHeight)
            self.content.frame = CGRect(x: 16, y: max((self.contentView.bounds.height-height)/2,8), width: width, height: height)
        }
    }

    open override func refresh(entity: MessageEntity) {
        self.checkbox.isHidden = true
        self.entity = entity
        if entity.isTimeDivider {
            // Time divider only shows the centered time, the time of an alert message itself is no longer needed.
            self.content.isHidden = true
            self.time.isHidden = false
            self.time.text = entity.dividerText
        } else {
            self.content.isHidden = false
            self.time.isHidden = true
            self.content.attributedText = entity.content
        }
        self.setNeedsLayout()
    }
    
    public override func switchTheme(style: ThemeStyle) {
        self.time.textColor = style == .dark ? UIColor.theme.neutralColor6:UIColor.theme.neutralColor7
    }
}


