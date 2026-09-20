//
//  ChatEmojiView.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/8/30.
//

import UIKit

@objcMembers open class MessageInputEmojiView: UIView {
        
    public var deleteClosure: (() -> Void)?
    
    public var sendClosure: (() -> Void)?

    public var emojiClosure: ((String) -> Void)?

    /// Called when a gif cover is tapped,passes the local file path of the corresponding `N.gif` in `EaseChatResource.bundle`.
    public var gifClosure: ((String) -> Void)?

    /// Gif cover image names contained in `EaseChatResource.bundle`.
    public let gifNames: [String] = (1...13).map { "gif_cover_\($0)" }

    /// Captions displayed under each gif cover,aligned with `gifNames`.Empty string means no caption.
    public let gifCaptions: [String] = ["亮个相吧","辛苦啦","Bug终结者","你说神嘛","报错了","真棒","厉害","笑死","成功啦","真棒棒","好的收到","上线成功","谢谢老板"]

    private var gifPageSelected = false

    public lazy var flowLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: (self.frame.width - 20 - 60) / 7.0, height: (self.frame.width - 20 - 60) / 7.0)
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        return layout
    }()

    public lazy var emojiList: UICollectionView = {
        UICollectionView(frame: CGRect(x: 0, y: 10, width: self.frame.width, height: self.frame.height - 10 - BottomBarHeight), collectionViewLayout: self.flowLayout).registerCell(ChatEmojiCell.self, forCellReuseIdentifier: "ChatEmojiCell").dataSource(self).delegate(self).backgroundColor(.clear)
    }()

    public private(set) lazy var emojiTab: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: 10, y: 8, width: 32, height: 32)).image(UIImage(chatNamed: "😀"), .normal).addTargetFor(self, action: #selector(switchTab(_:)), for: .touchUpInside).cornerRadius(.small).backgroundColor(.clear)
    }()

    public private(set) lazy var gifTab: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: 50, y: 8, width: 32, height: 32)).image(UIImage(chatNamed: "gif_cover_1"), .normal).addTargetFor(self, action: #selector(switchTab(_:)), for: .touchUpInside).cornerRadius(.small).backgroundColor(.clear)
    }()

    public lazy var gifFlowLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 64, height: 80)
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = max(0, floor((self.frame.width - 20 - 64 * 4) / 3.0))
        return layout
    }()

    public lazy var gifList: UICollectionView = {
        let collection = UICollectionView(frame: CGRect(x: 0, y: 44, width: self.frame.width, height: self.frame.height - 44 - BottomBarHeight), collectionViewLayout: self.gifFlowLayout).registerCell(ChatGifCell.self, forCellReuseIdentifier: "ChatGifCell").dataSource(self).delegate(self).backgroundColor(.clear)
        collection.isHidden = true
        return collection
    }()

    public lazy var separaLine: UIView = {
        UIView(frame: CGRect(x: 0, y: 10, width: ScreenWidth, height: 1)).backgroundColor(.clear)
    }()

    public lazy var deleteEmoji: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: self.frame.width - 112, y: self.frame.height - 56, width: 44, height: 44)).addTargetFor(self, action: #selector(deleteAction), for: .touchUpInside).isEnabled(true).cornerRadius(.large).backgroundColor(.clear)
    }()
    
    public lazy var sendEmoji: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: self.frame.width - 56, y: self.frame.height - 56, width: 44, height: 44)).addTargetFor(self, action: #selector(sendAction), for: .touchUpInside).isEnabled(true).cornerRadius(.large).backgroundColor(.clear).image(UIImage(chatNamed: "airplane"), .normal)
    }()
    
    lazy var gradient: GradientEmojiView = {
        GradientEmojiView(frame: CGRect(x: 0, y: self.frame.height-BottomBarHeight-31, width: self.frame.width, height: 32)).image(UIImage(chatNamed: "gradient_light"))
    }()

    @objc required override public init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubViews([self.emojiTab,self.gifTab,self.emojiList,self.gifList,self.gradient,self.deleteEmoji, self.sendEmoji,self.separaLine])
        self.refreshTabState()
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
    }
    
    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for view in subviews.reversed() {
            if view.isHidden || !view.frame.contains(point) {
                continue
            }
            if view.isKind(of: GradientEmojiView.self) {
                let childPoint = self.convert(point, to: self.emojiList)
                if let childView = self.emojiList.hitTest(childPoint, with: event) {
                    return childView
                }
            } else {
                let childPoint = self.convert(point, to: view)
                if let childView = view.hitTest(childPoint, with: event) {
                    return childView
                }
            }
        }
        return super.hitTest(point, with: event)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        self.gradient.frame = CGRect(x: 0, y: self.frame.height-BottomBarHeight-31, width: self.frame.width, height: 31)
        self.deleteEmoji.frame = CGRect(x: self.frame.width - 112, y: self.frame.height - 56 - BottomBarHeight, width: 44, height: 44)
        self.sendEmoji.frame = CGRect(x: self.frame.width - 56, y: self.frame.height - 56 - BottomBarHeight, width: 44, height: 44)
        self.deleteEmoji.cornerRadius(Appearance.avatarRadius)
        self.sendEmoji.cornerRadius(Appearance.avatarRadius)
        self.separaLine.frame = CGRect(x: 0, y: 10, width: self.frame.width, height: 1)
        self.emojiTab.frame = CGRect(x: 10, y: 8, width: 32, height: 32)
        self.gifTab.frame = CGRect(x: 50, y: 8, width: 32, height: 32)
        self.emojiList.frame = CGRect(x: 0, y: 44, width: self.frame.width, height: self.frame.height - 44 - BottomBarHeight)
        self.gifList.frame = self.emojiList.frame
        self.gifFlowLayout.itemSize = CGSize(width: 64, height: 80)
        self.gifFlowLayout.minimumInteritemSpacing = max(0, floor((self.frame.width - 20 - 64 * 4) / 3.0))
    }

    @objc func switchTab(_ sender: UIButton) {
        self.gifPageSelected = sender == self.gifTab
        self.refreshTabState()
        self.emojiList.isHidden = self.gifPageSelected
        self.gifList.isHidden = !self.gifPageSelected
        self.deleteEmoji.isHidden = self.gifPageSelected
        self.sendEmoji.isHidden = self.gifPageSelected
        self.gradient.isHidden = self.gifPageSelected
    }

    private func refreshTabState() {
        let selectedBackground = Theme.style == .dark ? UIColor.theme.neutralColor3:UIColor.theme.neutralColor95
        self.emojiTab.backgroundColor = self.gifPageSelected ? .clear:selectedBackground
        self.gifTab.backgroundColor = self.gifPageSelected ? selectedBackground:.clear
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func deleteAction() {
        self.deleteClosure?()
    }
    
    @objc func sendAction() {
        self.sendClosure?()
    }
}

extension MessageInputEmojiView: UICollectionViewDelegate, UICollectionViewDataSource {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView == self.gifList ? self.gifNames.count:ChatEmojiConvertor.shared.emojis.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == self.gifList {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ChatGifCell", for: indexPath) as? ChatGifCell
            cell?.icon.image = UIImage(chatNamed: self.gifNames[indexPath.row])
            let caption = indexPath.row < self.gifCaptions.count ? self.gifCaptions[indexPath.row]:""
            cell?.caption.text = caption
            cell?.caption.isHidden = caption.isEmpty
            return cell ?? ChatGifCell()
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ChatEmojiCell", for: indexPath) as? ChatEmojiCell
        cell?.icon.image = ChatEmojiConvertor.shared.emojiMap.isEmpty ? UIImage(chatNamed: ChatEmojiConvertor.shared.emojis[indexPath.row]):ChatEmojiConvertor.shared.emojiMap[ChatEmojiConvertor.shared.emojis[indexPath.row]]
        return cell ?? ChatEmojiCell()
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if collectionView == self.gifList {
            if let path = Bundle.chatBundle.path(forResource: "\(indexPath.row+1)", ofType: "gif") {
                self.gifClosure?(path)
            }
        } else {
            self.emojiClosure?(ChatEmojiConvertor.shared.emojis[indexPath.row])
        }
    }
}

extension MessageInputEmojiView: ThemeSwitchProtocol {
    public func switchTheme(style: ThemeStyle) {
        let image = UIImage(chatNamed: "arrow_left_thick")
        
        self.deleteEmoji.setImage(style == .dark ? image?.withTintColor(UIColor.theme.neutralColor98):image?.withTintColor(UIColor.theme.neutralColor3), for: .normal)
        self.deleteEmoji.backgroundColor = style == .dark ? UIColor.theme.neutralColor2:UIColor.theme.neutralColor95
        self.sendEmoji.backgroundColor = style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor
        self.gradient.image = UIImage(chatNamed: style == .dark ? "gradient_dark":"gradient_light")
        self.refreshTabState()
    }
}

open class ChatEmojiCell: UICollectionViewCell {
    lazy var icon: UIImageView = {
        UIImageView(frame: CGRect(x: 7, y: 7, width: self.contentView.frame.width - 14, height: self.contentView.frame.height - 14)).contentMode(.scaleAspectFit).backgroundColor(.clear)
    }()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.backgroundColor = .clear
        self.backgroundColor = .clear
        self.contentView.addSubview(self.icon)
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.icon.frame = CGRect(x: 7, y: 7, width: contentView.frame.width - 14, height: contentView.frame.height - 14)
    }
}

open class ChatGifCell: UICollectionViewCell {
    lazy var icon: UIImageView = {
        UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64)).contentMode(.scaleAspectFit).backgroundColor(.clear)
    }()

    lazy var caption: UILabel = {
        let label = UILabel(frame: CGRect(x: 0, y: 64, width: 64, height: 16))
        label.font = UIFont.systemFont(ofSize: 12)
        label.textAlignment = .center
        label.textColor = Theme.style == .dark ? UIColor.theme.neutralColor8:UIColor.theme.neutralColor3
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.backgroundColor = .clear
        self.backgroundColor = .clear
        self.contentView.addSubview(self.icon)
        self.contentView.addSubview(self.caption)
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.icon.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        self.caption.frame = CGRect(x: 0, y: 64, width: 64, height: 16)
    }
}


