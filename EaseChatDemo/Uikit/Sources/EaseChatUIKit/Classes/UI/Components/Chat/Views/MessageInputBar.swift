//
//  MessageInputBar.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/9/4.
//

import UIKit

/// The types of actions that can be triggered by the input bar.
@objc public enum MessageInputBarActionType: UInt {
    case send
    case audio
    case mention
    case attachment
    case textKeyboard
    case emojiKeyboard
    case cancelMention
    case startTyping
}

@objcMembers open class MessageInputBar: UIView {
    
    public var axisYChanged: ((CGFloat) -> Void)?
    
    open override var frame: CGRect {
        didSet {
            if self.frame.origin.y != oldValue.origin.y {
                self.axisYChanged?(self.frame.origin.y)
            }
        }
    }
    
    public var textViewFirstResponder: ((Bool) -> Void)?
    
    
    public private(set) var audioImage = UIImage(chatNamed: "audio")
    
    public private(set) var attachmentImage = UIImage(chatNamed: "attachment")
    
    public private(set) var selectedAttachmentImage = UIImage(chatNamed: "attachmentSelected")
    
    public private(set) var collapsedState = true
    
    var isInputActive: Bool {
        self.inputField.isFirstResponder || self.frame.minY != self.rawFrame.minY || self.frame.height != self.rawFrame.height || !(self.emoji?.isHidden ?? true) || !self.extensionMenus.isHidden
    }
    
    private var style: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.15
        return paragraph
    }
    
    private var typingAttributesText: [NSAttributedString.Key : Any] {
        [.foregroundColor:Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1,.font:UIFont.theme.bodyLarge,.paragraphStyle: self.style]
    }
        
    /// The height of the keyboard.
    public private(set) var keyboardHeight = CGFloat(0)

    /// The raw height of the input bar.
    public private(set)var rawHeight: CGFloat = 0

    /// The raw height of the text input area.
    public private(set) var rawTextHeight: CGFloat = 0

    /// The raw frame of the input bar.
    public private(set) var rawFrame: CGRect = .zero
    
    public private(set) var recordedFrame: CGRect = .zero
    
    /// Action events callback,contain ``MessageInputBarActionType`` and send text when you click send button.
    public var actionClosure: ((MessageInputBarActionType,NSAttributedString?) -> Void)?

    /// A closure to be called when the user toggles the emoji keyboard.
    public var changeEmojiClosure: ((Bool) -> Void)?

    /// A closure to be called when a gif cover is selected in the emoji keyboard,passes the cover image file path.
    public var gifClosure: ((String) -> Void)?
    
    private var hiddenDuration = Double(0.2)
    
    public private(set) lazy var rightView: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: self.frame.width-80, y: self.inputField.frame.maxY-32, width: 30, height: 30)).addTargetFor(self, action: #selector(changeToEmoji), for: .touchUpInside).backgroundColor(.clear)
    }()
    
    public private(set) lazy var audio: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: 12, y: self.inputField.frame.maxY-32, width: 30, height: 30)).backgroundColor(.clear).image(self.audioImage, .normal).addTargetFor(self, action: #selector(audioAction), for: .touchUpInside)
    }()
    
    public private(set) lazy var inputField: PlaceHolderTextView = {
        PlaceHolderTextView(frame: CGRect(x: 50, y: 8, width: self.frame.width-142, height: PlaceHolderTextView.singleLineHeight)).delegate(self).font(UIFont.theme.bodyLarge).backgroundColor(.clear).backgroundColor(UIColor.theme.neutralColor95)
    }()
    
    public private(set) lazy var attachment: UIButton = {
        UIButton(type: .custom).frame(CGRect(x: self.frame.width - 42, y: self.inputField.frame.maxY-32, width: 30, height: 30)).backgroundColor(.clear).addTargetFor(self, action: #selector(attachmentAction), for: .touchUpInside)
    }()
        
    public private(set) lazy var line: UIView = {
        UIView(frame: CGRect(x: 0, y: 0, width: self.frame.width, height: 0.5)).backgroundColor(UIColor.theme.neutralColor9)
    }()
    
    public private(set) var emoji: MessageInputEmojiView?
    
    public private(set) lazy var extensionMenus: MessageInputExtensionView = {
        let menu = MessageInputExtensionView(frame: CGRect(x: 0, y: self.inputField.frame.maxY+15, width: self.frame.width, height: (Appearance.chat.inputExtendActions.count > 4 ? 230:132))).backgroundColor(.clear)
        menu.isHidden = true
        return menu
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    /// MessageInputBar init method
    /// - Parameters:
    ///   - frame: CGRect
    ///   - text: `String` value
    ///   - placeHolder: `String` value
    @objc required public init(frame: CGRect,text: String? = nil,placeHolder: String? = nil) {
        self.rawFrame = frame
        self.recordedFrame = frame
        self.rawHeight = frame.height
        self.rawTextHeight = self.rawHeight-16
        super.init(frame: frame)
        self.addSubViews([self.audio,self.inputField, self.rightView,self.attachment,self.line])
        self.rightView.setImage(UIImage(chatNamed: "emojiKeyboard")?.withTintColor(UIColor.theme.neutralColor3), for: .normal)
        self.rightView.setImage(UIImage(chatNamed: "textKeyboard")?.withTintColor(UIColor.theme.neutralColor3), for: .selected)
        self.attachment.setImage(self.attachmentImage, for: .normal)
        self.attachment.setImage(self.selectedAttachmentImage, for: .selected)
        self.inputField.returnKeyType = .send
        self.inputField.contentInsetAdjustmentBehavior = .never
        self.inputField.cornerRadius(Appearance.chat.inputBarCorner)
        self.inputField.tintColor = UIColor.theme.primaryLightColor
        self.inputField.placeHolderColor = UIColor.theme.neutralColor6
        self.inputField.textColor = UIColor.theme.neutralColor1
        let font = UIFont.theme.bodyLarge
        self.inputField.font = font
        let lineHeight = font.lineHeight * self.style.lineHeightMultiple
        let verticalInset = max(0, (self.inputField.bounds.height - lineHeight) / 2)
        // Center the visible text within the field while preserving the total padding.
        let textLift = min(2, verticalInset)
        self.inputField.textContainerInset = UIEdgeInsets(
            top: verticalInset - textLift,
            left: Appearance.chat.inputBarCorner == .large ? 10 : 6,
            bottom: verticalInset + textLift,
            right: 6
        )
        self.inputField.bounces = false
        self.inputField.isScrollEnabled = false
        self.inputField.layoutManager.allowsNonContiguousLayout = false
        self.inputField.adjustsFontForContentSizeCategory = true
        if text != nil {
            self.inputField.text = text
        }
        self.inputField.typingAttributes = self.typingAttributesText
        self.inputField.placeHolder = placeHolder ?? "Aa"
        if self.inputField.hasText { self.updateHeight() }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIApplication.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIApplication.keyboardWillHideNotification, object: nil)
        
        
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
        
        self.rightView.setHitTestEdgeInsets(UIEdgeInsets(top: -8, left: -10, bottom: -5, right: -5))
        self.attachment.setHitTestEdgeInsets(UIEdgeInsets(top: -8, left: -5, bottom: -5, right: -10))
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        inputField.removeFromSuperview()
        emoji?.removeFromSuperview()
        emoji = nil
        consoleLogInfo("\(self.swiftClassName ?? "") deinit", type: .debug)
    }
    
    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func resetFrame(newFrame: CGRect) {
        self.frame = newFrame
        self.rawFrame = self.frame
        self.recordedFrame = self.frame
        self.rawHeight = self.frame.height
        self.rawTextHeight = self.rawHeight-16
        self.rightView.frame = CGRect(x: self.frame.width-80, y: self.inputField.frame.maxY-32, width: 30, height: 30)
        self.audio.frame = CGRect(x: 12, y: self.inputField.frame.maxY-32, width: 30, height: 30)
        self.inputField.frame = CGRect(x: 50, y: 8, width: self.frame.width-142, height: PlaceHolderTextView.singleLineHeight)
        self.attachment.frame = CGRect(x: self.frame.width - 42, y: self.inputField.frame.maxY-32, width: 30, height: 30)
        self.line.frame = CGRect(x: 0, y: 0, width: self.frame.width, height: 0.5)
        self.emoji?.frame = CGRect(x: 0, y: self.inputField.frame.maxY+8, width: self.frame.width, height: self.keyboardHeight)
        self.extensionMenus.frame = CGRect(x: 0, y: self.inputField.frame.maxY+15, width: self.frame.width, height: (Appearance.chat.inputExtendActions.count > 4 ? 230:132))
    }
    
    func updateContainerFrame(newFrame: CGRect, preserveInputState: Bool) {
        if !preserveInputState {
            self.resetFrame(newFrame: newFrame)
            return
        }
        // Keep the expanded input anchored to the container's bottom when its top moves.
        let widthChanged = newFrame.width != self.rawFrame.width
        let bottomDelta = newFrame.maxY - self.rawFrame.maxY
        self.rawFrame = newFrame
        self.rawHeight = newFrame.height
        self.rawTextHeight = max(self.inputField.frame.height, self.rawHeight-16)
        self.frame = CGRect(x: self.frame.minX, y: self.frame.minY + bottomDelta, width: newFrame.width, height: self.frame.height)
        self.recordedFrame = self.frame
        self.rightView.frame = CGRect(x: self.frame.width-80, y: self.inputField.frame.maxY-32, width: 30, height: 30)
        self.audio.frame = CGRect(x: 12, y: self.inputField.frame.maxY-32, width: 30, height: 30)
        self.inputField.frame = CGRect(x: 50, y: self.inputField.frame.minY, width: self.frame.width-142, height: self.inputField.frame.height)
        self.attachment.frame = CGRect(x: self.frame.width - 42, y: self.inputField.frame.maxY-32, width: 30, height: 30)
        self.line.frame = CGRect(x: 0, y: 0, width: self.frame.width, height: 0.5)
        self.emoji?.frame = CGRect(x: 0, y: self.inputField.frame.maxY+8, width: self.frame.width, height: self.keyboardHeight)
        self.extensionMenus.frame = CGRect(x: 0, y: self.inputField.frame.maxY+15, width: self.frame.width, height: (Appearance.chat.inputExtendActions.count > 4 ? 230:132))
        if widthChanged, self.extensionMenus.isHidden { self.updateHeight() }
    }
   
}

extension MessageInputBar: UITextViewDelegate {
    
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        self.hideAttachmentMenu()
        self.emoji?.isHidden = true
        if text == "\n" {
            self.sendMessage()
            return false
        }
        if text.contains("@") {
            self.actionClosure?(.mention, textView.attributedText)
        } else if text.isEmpty, textView.hasText, let attributedText = textView.attributedText {
            var deletedMention = false
            attributedText.enumerateAttribute(NSAttributedString.Key("mentionInfo"), in: NSRange(location: 0, length: attributedText.length)) { value, blockRange, stop in
                guard let user = value as? ChatUserProfileProtocol, NSMaxRange(range) == NSMaxRange(blockRange) else { return }
                let result = NSMutableAttributedString(attributedString: attributedText)
                result.deleteCharacters(in: blockRange)
                textView.attributedText = result
                textView.selectedRange = NSRange(location: blockRange.location, length: 0)
                self.actionClosure?(.cancelMention, NSAttributedString(string: user.nickname.isEmpty ? user.id : user.nickname))
                deletedMention = true
                stop.pointee = true
            }
            if deletedMention { self.updateHeight() }
            return !deletedMention
        }
        if textView.markedTextRange == nil {
            textView.typingAttributes = self.typingAttributesText
        }
        return true
    }
    
    public func textViewDidChangeSelection(_ textView: UITextView) {
        if textView.selectedRange.length > 0 {
            self.rightView.isSelected = false
        }
        textView.attributedText.enumerateAttributes(in: NSMakeRange(0, textView.attributedText.length), options: []) { (attributes, range, stop) in
            if attributes[NSAttributedString.Key(rawValue: "mentionInfo")] is ChatUserProfileProtocol {
                let min = textView.selectedRange.location
                let max = textView.selectedRange.location + textView.selectedRange.length
                if min > range.location && min <= range.location + range.length {
                    let location = range.location + range.length
                    var length = 0
                    
                    if textView.selectedRange.location + textView.selectedRange.length > location {
                        length = textView.selectedRange.location + textView.selectedRange.length - location
                    }
                    
                    textView.selectedRange = NSMakeRange(location, length)
                    stop.pointee = true
                } else if max > range.location && max <= range.location + range.length {
                    let location = min
                    let length = textView.selectedRange.length - (max - range.location - range.length)
                    textView.selectedRange = NSMakeRange(location, length)
                    stop.pointee = true
                }
            }
        }
    }
    
    public func textViewDidBeginEditing(_ textView: UITextView) {
        self.rightView.isSelected = false
        if !textView.hasText {
            textView.typingAttributes = self.typingAttributesText
        }
    }
    
    public func textViewDidChange(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.typingAttributes = self.typingAttributesText
        }
        self.updateHeight()
        self.actionClosure?(.startTyping,nil)
    }
    
    public func textViewDidEndEditing(_ textView: UITextView) {
        if let emojiView = self.emoji {
            self.textViewFirstResponder?(!emojiView.isHidden)
        }
    }
    
    func updateHeight() {
        let width = self.inputField.bounds.width
        guard width > 0 else { return }
        let singleLineHeight = PlaceHolderTextView.singleLineHeight
        let maximumHeight = max(singleLineHeight, Appearance.chat.maxInputHeight)
        let fittingHeight = self.inputField.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        // TextKit can round the single-line measurement up despite the matching insets.
        let requiredHeight = self.inputField.hasText && fittingHeight > singleLineHeight + 2 ? ceil(fittingHeight) : singleLineHeight
        let textHeight = min(requiredHeight, maximumHeight)
        let shouldScroll = requiredHeight > maximumHeight
        let editorBottom = self.frame.minY + self.inputField.frame.maxY + 8
        let emojiHeight = self.rightView.isSelected ? self.keyboardHeight : 0

        self.rawTextHeight = textHeight
        self.rawHeight = textHeight + 16
        self.inputField.frame.size.height = textHeight
        if self.inputField.isScrollEnabled != shouldScroll {
            self.inputField.isScrollEnabled = shouldScroll
        }
        self.frame = CGRect(x: self.frame.minX, y: editorBottom - self.rawHeight, width: self.frame.width, height: self.rawHeight + emojiHeight)
        self.audio.frame.origin.y = self.inputField.frame.maxY - 32
        self.rightView.frame.origin.y = self.inputField.frame.maxY - 32
        self.attachment.frame.origin.y = self.inputField.frame.maxY - 32
        self.emoji?.frame.origin.y = self.inputField.frame.maxY + 8
        self.inputField.setNeedsLayout()

        if shouldScroll, self.inputField.selectedRange.location != NSNotFound {
            self.inputField.scrollRangeToVisible(NSRange(location: NSMaxRange(self.inputField.selectedRange), length: 0))
        } else if !shouldScroll, self.inputField.contentOffset != .zero {
            self.inputField.setContentOffset(.zero, animated: false)
        }
        self.recordedFrame = self.frame
    }
    
    /**
     This function is called when the user taps on the send button in the chat input bar. It hides the input bar, deselects the right view, and sends the message if the input field is not empty. It also resets the input field and the frame of the input bar to their original values.
     */
    @objc func sendMessage() {
        if self.rightView.isSelected {
            self.showEmojiKeyboard()
        }
        if self.attachment.isSelected || !self.extensionMenus.isHidden {
            self.hiddenInputBar()
        }
        if !self.inputField.attributedText.toString().isEmpty {
            let attributedText = NSAttributedString(attributedString: self.inputField.attributedText)
            self.actionClosure?(.send,attributedText)
        }
        self.inputField.text = ""
        self.inputField.attributedText = NSAttributedString(string: "")
        self.inputField.typingAttributes = self.typingAttributesText
        self.updateHeight()
    }
    
    
    @objc func attachmentAction() {
        switch Appearance.chat.messageAttachmentMenuStyle {
        case .followInput:
            self.processAttachmentView(selected: !self.attachment.isSelected)
        default:
            self.actionClosure?(.attachment,nil)
            break
        }

    }
    
    @objc func processAttachmentView(selected: Bool) {
        if selected {
            self.attachment.isSelected = true
            self.rightView.isSelected = false
            self.extensionMenus.isHidden = false
            self.emoji?.isHidden = true
            self.inputField.resignFirstResponder()
            self.keyboardHeight = Appearance.chat.inputExtendActions.count > 4 ? 230 : 132
            self.showExtensionMenus()
        } else {
            self.hiddenInputBar()
            self.inputField.becomeFirstResponder()
        }
    }

    private func hideAttachmentMenu() {
        self.attachment.isSelected = false
        self.extensionMenus.isHidden = true
        self.extensionMenus.isUserInteractionEnabled = false
    }

    @objc func audioAction() {
        self.inputField.isScrollEnabled = false
        self.hiddenInput()
        self.actionClosure?(.audio,nil)
    }
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {

        for view in subviews {
            if view.isKind(of: type(of: view)),view.frame.contains(point) {
                if view is MessageInputEmojiView, view.isHidden {
                    if !self.extensionMenus.isHidden {
                        let childPoint = self.convert(point, to: self.extensionMenus)
                        let childView = self.extensionMenus.hitTest(childPoint, with: event)
                        return childView
                    }
                }
                if view is MessageInputExtensionView , view.isHidden  {
                    if !(self.emoji?.isHidden ?? true) {
                        let childPoint = self.convert(point, to: self.emoji)
                        let childView = self.emoji?.hitTest(childPoint, with: event)
                        return childView
                    }
                }
                let childPoint = self.convert(point, to: view)
                let childView = view.hitTest(childPoint, with: event)
                return childView
            }
        }
        if self.collapsedState {
            self.hiddenInput()
        }
        return super.hitTest(point, with: event)
    }

    @objc func changeToEmoji() {
        self.hideAttachmentMenu()
        self.rightView.isSelected = !self.rightView.isSelected
        self.actionClosure?(self.rightView.isSelected ? .emojiKeyboard:.textKeyboard,nil)
        if self.rightView.isSelected {
            if !self.inputField.isFirstResponder {
                self.keyboardHeight = 256+BottomBarHeight
            }
            self.rightView.isSelected = true
            self.inputField.resignFirstResponder()
            self.showEmojiKeyboard()
        } else {
            if !self.rightView.isSelected {
                self.inputField.becomeFirstResponder()
            }
        }
        self.textViewFirstResponder?(true)
    }
    
    public func endSuperScroll() {
        if let list = self.superview?.viewWithTag(111) as? UITableView {
            let indexPath = IndexPath(row: list.numberOfRows(inSection: 0) - 1, section: 0)
            if indexPath.row >= 0 {
                list.scrollToRow(at: indexPath, at: .none, animated: false)
            }
        }
    }
    
    @objc private func keyboardWillShow(notification: Notification) {
        self.endSuperScroll()
        if !self.inputField.isFirstResponder {
            return
        }
        self.collapsedState = false
        self.emoji?.isHidden = true
        self.hideAttachmentMenu()
        guard let frame = notification.chat.keyboardEndFrame else { return }
        guard let duration = notification.chat.keyboardAnimationDuration else { return }
        self.keyboardHeight = frame.height
        if frame.height < 216 {
            return
        }
        self.switchTheme(style: Theme.style)
        print("rawFrame:\(self.rawFrame) frame:\(self.frame) keyboardHeight:\(frame.height)")
        UIView.animate(withDuration: duration) {
            if (self.inputField.text?.isEmpty ?? false),self.inputField.isFirstResponder {
                self.frame = CGRect(x: 0, y: self.rawFrame.minY - frame.height + BottomBarHeight, width: self.rawFrame.width, height: self.rawFrame.height)
            } else {
                self.frame = CGRect(x: 0, y: self.rawFrame.maxY - self.keyboardHeight - self.inputField.frame.height - 16 + BottomBarHeight, width: self.frame.width, height: self.inputField.frame.height + 16)
            }
        }
        self.textViewFirstResponder?(true)
    }
    
    @objc private func keyboardWillHide(notification: Notification) {
        // Showing attachments intentionally dismisses the keyboard beneath the menu.
        guard !self.collapsedState, !self.attachment.isSelected || self.extensionMenus.isHidden else { return }
        if self.rightView.isSelected {
            guard let _ = notification.chat.keyboardEndFrame else { return }
            guard let duration = notification.chat.keyboardAnimationDuration else { return }
            self.hiddenDuration = duration
            self.showEmojiKeyboard()
            self.textViewFirstResponder?(true)
        } else {
            self.hiddenInput()
        }
    }
    
    @objc open func showEmojiKeyboard() {
        self.emoji?.isUserInteractionEnabled = true
        self.endSuperScroll()
        self.collapsedState = false
        if self.rightView.isSelected {
            self.keyboardHeight = 256+BottomBarHeight
            let editorHeight = self.inputField.frame.height + 16
            let height = editorHeight + self.keyboardHeight
            self.frame = CGRect(x: 0, y: self.rawFrame.maxY + BottomBarHeight - height, width: self.frame.width, height: height)
            if self.emoji == nil{
                let emoji = MessageInputEmojiView(frame: CGRect(x: 0, y: editorHeight, width: self.frame.width, height: self.keyboardHeight)).tag(124).backgroundColor(.clear)
                self.emoji = emoji
                self.addSubview(emoji)
            } else {
                self.emoji?.frame = CGRect(x: 0, y: self.inputField.frame.maxY+8, width: self.frame.width, height: self.keyboardHeight)
            }
            self.emoji?.sendClosure = { [weak self] in
                self?.sendMessage()
            }
            self.emoji?.emojiClosure = { [weak self] in
                guard let self = self else { return }
                self.emoji?.deleteEmoji.isEnabled = true
                self.emoji?.deleteEmoji.isUserInteractionEnabled = true
                self.inputField.attributedText = self.convertText(text: self.inputField.attributedText, key: $0)
                self.updateHeight()
            }
            self.emoji?.deleteClosure = { [weak self] in
                if self?.inputField.text?.count ?? 0 > 0 {
                    self?.inputField.deleteBackward()
                    self?.emoji?.deleteEmoji.isEnabled = true
                    self?.emoji?.deleteEmoji.isUserInteractionEnabled = true
                } else {
                    self?.emoji?.deleteEmoji.isEnabled = false
                    self?.emoji?.deleteEmoji.isUserInteractionEnabled = false
                }
                self?.updateHeight()
            }
            self.emoji?.gifClosure = { [weak self] in
                self?.gifClosure?($0)
            }
            self.updateHeight()
        } else {
            self.frame = CGRect(x: 0, y: self.frame.origin.y, width: self.frame.width, height: self.rawFrame.height)
        }
        
        UIView.animate(withDuration: self.hiddenDuration) {
            self.emoji?.isHidden = !self.rightView.isSelected
        }
        self.switchTheme(style: Theme.style)
    }
    
    @objc open func showExtensionMenus() {
        self.collapsedState = false
        self.extensionMenus.isUserInteractionEnabled = true
        self.endSuperScroll()
        if !self.subviews.contains(self.extensionMenus) {
            self.addSubview(self.extensionMenus)
        }
        self.switchTheme(style: Theme.style)
        self.extensionMenus.isHidden = false
        UIView.animate(withDuration: self.hiddenDuration) {
            self.frame = self.rawFrame
            if self.attachment.isSelected {
                self.extensionMenus.frame = CGRect(x: 0, y: self.inputField.frame.maxY+15-(NavigationHeight > 64 ? 0:10), width: self.frame.width, height: (Appearance.chat.inputExtendActions.count > 4 ? 230:132)+(NavigationHeight > 64 ? 0:10))
                self.frame = CGRect(x: 0, y: self.frame.minY-self.extensionMenus.frame.height-BottomBarHeight-(NavigationHeight > 64 ? 0:10), width: self.frame.width, height: self.extensionMenus.frame.height + self.inputField.frame.height + BottomBarHeight)
            } else {
                self.extensionMenus.isHidden = true
            }
        }
        self.textViewFirstResponder?(true)
    }
    
    @objc public func hiddenInputBar() {
        let height = max(self.rawFrame.height, self.inputField.frame.height + 16)
        let collapsedFrame = CGRect(x: self.rawFrame.minX, y: self.rawFrame.maxY - height, width: self.rawFrame.width, height: height)
        if self.collapsedState, self.frame == collapsedFrame, !self.inputField.isFirstResponder,
           self.extensionMenus.isHidden, !self.attachment.isSelected, self.emoji?.isHidden != false, !self.rightView.isSelected {
            return
        }
        self.collapsedState = true
        self.hideAttachmentMenu()
        self.rightView.isSelected = false
        self.emoji?.isHidden = true
        self.inputField.resignFirstResponder()
        UIView.animate(withDuration: self.hiddenDuration) {
            self.frame = collapsedFrame
        }
        self.recordedFrame = collapsedFrame
        self.textViewFirstResponder?(false)
    }
    
    /// Raise input bar
    @objc public func show() {
        self.inputField.becomeFirstResponder()
    }
    
    /// Hidden input bar
    @objc public func hiddenInput() {
        self.hiddenInputBar()
    }

    /**
     Converts the given attributed string to include an emoji image attachment with the specified key.

     - Parameters:
        - text: The attributed string to convert.
        - key: The key of the emoji image to use.

     - Returns: The converted attributed string with the emoji image attachment.
     */
    func convertText(text: NSAttributedString?, key: String) -> NSAttributedString {
        let attribute = NSMutableAttributedString(attributedString: text!)
        attribute.addAttributes([.foregroundColor:Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1,.font:UIFont.theme.bodyLarge], range: NSMakeRange(0, attribute.length))
        let attachment = NSTextAttachment()
        attachment.image = ChatEmojiConvertor.shared.emojiMap.isEmpty ? UIImage(chatNamed: key):ChatEmojiConvertor.shared.emojiMap[key]
        attachment.bounds = CGRect(x: 0, y: -3.5, width: 18, height: 18)
        let imageText = NSMutableAttributedString(attachment: attachment)
        if #available(iOS 11.0, *) {
            if self.inputField.selectedRange.location != NSNotFound,self.inputField.selectedRange.length != NSNotFound {
                imageText.addAttributes([.accessibilityTextCustom: key,.foregroundColor:Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1,.font:UIFont.theme.bodyLarge], range: NSMakeRange(0, imageText.length))
                attribute.replaceCharacters(in: self.inputField.selectedRange, with: imageText)
                
            } else {
                imageText.addAttributes([.accessibilityTextCustom: key,.foregroundColor:Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1,.font:UIFont.theme.bodyLarge], range: NSMakeRange(0, imageText.length))
                attribute.append(imageText)
            }
        } else {
            assert(false,"failed add accessibility custom text!")
        }
        return attribute
    }
    
    public func dismissKeyboard() {
        self.inputField.resignFirstResponder()
    }
}

extension MessageInputBar: ThemeSwitchProtocol {
    
    public func switchTheme(style: ThemeStyle) {
        self.rightView.setImage(UIImage(chatNamed: "emojiKeyboard")?.withTintColor(style == .dark ? UIColor.theme.neutralColor95:UIColor.theme.neutralColor3, renderingMode: .automatic), for: .normal)
        self.rightView.setImage(UIImage(chatNamed: "textKeyboard")?.withTintColor(style == .dark ? UIColor.theme.neutralColor95:UIColor.theme.neutralColor3, renderingMode: .automatic), for: .selected)
        if style == .light {
            self.selectedAttachmentImage = self.selectedAttachmentImage?.withTintColor(UIColor.theme.neutralColor3)
            self.attachmentImage = self.attachmentImage?.withTintColor(UIColor.theme.neutralColor3)
            self.audioImage = self.audioImage?.withTintColor(UIColor.theme.neutralColor3)
        }
        self.attachment.setImage(self.attachmentImage, for: .normal)
        self.attachment.setImage(self.selectedAttachmentImage, for: .selected)
        self.audio.setImage(self.audioImage, for: .normal)
        self.viewWithTag(124)?.backgroundColor(style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98)
        self.inputField.backgroundColor(style == .dark ? UIColor.theme.neutralColor2:UIColor.theme.neutralColor95)
        self.inputField.tintColor = style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor
        self.inputField.placeHolderColor = style == .dark ? UIColor.theme.neutralColor4:UIColor.theme.neutralColor6
        self.inputField.textColor = style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1
        self.emoji?.backgroundColor(style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98)
        self.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
        self.line.backgroundColor = style == .dark ? UIColor.theme.neutralColor2:UIColor.theme.neutralColor9
    }
    
}

public extension NSAttributedString {
    /**
     Converts the attributed string to a plain string by replacing any custom accessibility text with its corresponding value.

     - Returns: A plain string representation of the attributed string.
     */
    func toString() -> String {
        let result = NSMutableAttributedString(attributedString: self)
        var replaceList: [(NSRange, String)] = []
        result.enumerateAttribute(.accessibilityTextCustom, in: NSRange(location: 0, length: result.length), using: { value, range, _ in
            if let value = value as? String {
                for i in range.location..<range.location + range.length {
                    replaceList.append((NSRange(location: i, length: 1), value))
                }
            }
        })
        for i in replaceList.reversed() {
            result.replaceCharacters(in: i.0, with: i.1)
        }
        return result.string
    }
}
