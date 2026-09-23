//
//  AudioMessageCell.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/12/5.
//

import UIKit

@objc open class AudioMessageCell: MessageCell {
    
    public private(set) lazy var content: UIView = {
        self.createContent()
    }()
    
    @objc open func createContent() -> UIView {
        AudioMessageView(frame: .zero, towards: self.towards).backgroundColor(.clear).tag(bubbleTag)
    }
    
    public private(set) lazy var redDot: UIView = {
        UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8)).cornerRadius(4)
    }()

    /// The rounded card laid out under the voice bubble that holds the transcribed text.
    public private(set) lazy var transcriptionContainer: UIView = {
        let container = UIView(frame: .zero).cornerRadius(10)
        container.isHidden = true
        return container
    }()

    public private(set) lazy var transcription: UILabel = {
        UILabel(frame: .zero).backgroundColor(.clear).numberOfLines(0).lineBreakMode(.byWordWrapping)
    }()

    @objc required public init(towards: BubbleTowards,reuseIdentifier: String) {
        super.init(towards: towards, reuseIdentifier: reuseIdentifier)
        if Appearance.chat.bubbleStyle == .withArrow {
            self.bubbleWithArrow.bubble.addSubview(self.content)
        } else {
            self.bubbleMultiCorners.addSubview(self.content)
        }
        self.addGestureTo(view: self.content, target: self)
        self.contentView.addSubview(self.redDot)
        self.transcriptionContainer.addSubview(self.transcription)
        self.contentView.addSubview(self.transcriptionContainer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func refresh(entity: MessageEntity) {
        super.refresh(entity: entity)
        let frame = Appearance.chat.bubbleStyle == .withArrow ? self.bubbleWithArrow.frame:self.bubbleMultiCorners.frame
        self.content.frame = CGRect(x: 0, y: 0, width: frame.width-(Appearance.chat.bubbleStyle == .withArrow ? 5:0), height: frame.height)
        if entity.message.direction == .receive {
            self.redDot.frame = CGRect(x: frame.maxX+8, y: frame.maxY - (frame.height/2.0) - 4, width: 8, height: 8)
            self.redDot.isHidden = entity.message.isListened
        } else {
            self.redDot.isHidden = true
        }
        if let transcription = entity.voiceTranscription {
            let textSize = entity.voiceTranscriptionSize()
            let cardWidth = min(textSize.width+24,limitBubbleWidth)
            let cardHeight = textSize.height+16
            let cardX = entity.message.direction == .receive ? frame.minX:frame.maxX-cardWidth
            self.transcription.attributedText = transcription
            self.transcription.frame = CGRect(x: 12, y: 8, width: textSize.width, height: textSize.height)
            self.transcriptionContainer.frame = CGRect(x: cardX, y: frame.maxY+8, width: cardWidth, height: cardHeight)
            self.transcriptionContainer.isHidden = false
        } else {
            self.transcriptionContainer.isHidden = true
        }
        (self.content as? AudioMessageView)?.refresh(entity: entity)
    }

    open override func switchTheme(style: ThemeStyle) {
        super.switchTheme(style: style)
        self.redDot.backgroundColor = style == .dark ? UIColor.theme.errorColor6:UIColor.theme.errorColor5
        self.transcriptionContainer.backgroundColor = style == .dark ? UIColor.theme.neutralColor2:UIColor.theme.neutralColor9
    }
}

