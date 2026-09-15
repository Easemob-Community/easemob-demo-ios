//
//  AudioMessageView.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/12/9.
//

import UIKit

@objc open class AudioMessageView: UIView {
    
    public private(set) var towards = BubbleTowards.left

    public private(set) lazy var content: UILabel = {
        UILabel(frame: CGRect(x: self.towards == .left ? 12+20:self.frame.width-12-20-12, y: 5, width: self.frame.width-24, height: self.frame.height-10)).backgroundColor(.clear).numberOfLines(1).font(UIFont.theme.bodyLarge).backgroundColor(.clear)
    }()
    
    public private(set) lazy var audioIcon: UIImageView = {
        UIImageView(frame: CGRect(x: self.towards == .left ? 12:self.frame.width-12-20, y: 5, width: self.frame.height - 10, height: self.frame.height - 10)).backgroundColor(.clear).contentMode(.scaleAspectFit)
    }()

    /// The voice-to-text result, laid out under the duration label when a transcription exists.
    public private(set) lazy var transcription: UILabel = {
        UILabel(frame: .zero).backgroundColor(.clear).numberOfLines(0).lineBreakMode(.byWordWrapping)
    }()

    @objc required public init(frame: CGRect,towards: BubbleTowards) {
        super.init(frame: frame)
        self.towards = towards
        self.addSubViews([self.content,self.audioIcon,self.transcription])
        self.audioIcon.animationDuration = 1.0
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc public func refresh(entity: MessageEntity) {
        self.towards = entity.message.direction == .receive ? .left:.right
        self.content.frame = CGRect(x: self.towards == .left ? 12+20+8:12, y: 5, width: self.frame.width-32-20, height: self.frame.height-10)
        self.audioIcon.frame = CGRect(x: self.towards == .left ? 12:self.frame.width-12-20, y: self.frame.height/2.0-10, width: 20, height: 20)
        self.switchTheme(style: Theme.style)
        var textColor = UIColor.white
        if entity.message.direction == .send {
            textColor = Theme.style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
        } else {
            textColor = Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1
        }
        self.content.textColor = textColor
        self.content.textAlignment = entity.message.direction == .receive ? .right:.left
        self.content.text = entity.message.showContent
        // Once the bubble grows to hold the transcription, pin the duration row to the top and lay the text out beneath it.
        if let transcription = entity.voiceTranscription {
            self.content.frame = CGRect(x: self.towards == .left ? 12+20+8:12, y: 8, width: self.frame.width-32-20, height: 20)
            self.audioIcon.frame = CGRect(x: self.towards == .left ? 12:self.frame.width-12-20, y: 8, width: 20, height: 20)
            self.transcription.attributedText = transcription
            self.transcription.textAlignment = .left
            let textSize = self.transcription.sizeThatFits(CGSize(width: self.frame.width-24, height: 9999))
            self.transcription.frame = CGRect(x: 12, y: self.content.frame.maxY+8, width: self.frame.width-24, height: textSize.height)
            self.transcription.isHidden = false
        } else {
            self.transcription.isHidden = true
        }
        if entity.playing {
            self.audioIcon.startAnimating()
        } else {
            self.audioIcon.stopAnimating()
        }
    }
}

extension AudioMessageView: ThemeSwitchProtocol {
    public func switchTheme(style: ThemeStyle) {
        if self.towards == .left {
            self.audioIcon.image = UIImage(chatNamed: "audio_message_icon_show_left")?.withTintColor(style == .dark ? UIColor.theme.neutralSpecialColor6:UIColor.theme.neutralSpecialColor5)
            self.audioIcon.animationImages = Appearance.chat.receiveAudioAnimationImages
        } else {
            self.audioIcon.image = UIImage(chatNamed: "audio_message_icon_show_right")?.withTintColor(style == .dark ? UIColor.theme.neutralSpecialColor6:UIColor.theme.neutralColor98)
            self.audioIcon.animationImages = Appearance.chat.sendAudioAnimationImages
        }
    }
}
