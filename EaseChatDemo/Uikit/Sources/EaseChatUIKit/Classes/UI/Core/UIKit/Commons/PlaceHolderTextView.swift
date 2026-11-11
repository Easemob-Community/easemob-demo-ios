//
//  PlaceHolderTextView.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2020/12/16.
//

import Foundation
import UIKit

/**
 A subclass of UITextView that provides a placeholder text when the text view is empty.
 */
@objcMembers public class PlaceHolderTextView: UITextView {
    static let singleLineHeight: CGFloat = 36
    
    public var placeHolder: String = "" {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    public var placeHolderColor: UIColor = UIColor.gray {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override public var font: UIFont?{
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override public var text: String? {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override public var attributedText: NSAttributedString!{
        didSet{
            self.setNeedsDisplay()
        }
    }
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        if self.font == nil {
            self.font = UIFont.theme.bodyLarge
        }
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChanged(noti:)), name: UITextView.textDidChangeNotification, object: self)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc fileprivate func textDidChanged(noti: NSNotification)  {
        self.setNeedsDisplay()
        //MARK: - this is ignore emoji
//        let modes = UITextInputMode.activeInputModes.compactMap {
//            $0.primaryLanguage == "emoji"
//        }
//        if modes.count > 0 {
//            self.text = String(self.text!.removeLast())
//        }
    }
    
    public override func draw(_ rect: CGRect) {
        if self.hasText {
            return
        }
        let padding = self.textContainer.lineFragmentPadding
        var textRect = self.bounds.inset(by: self.textContainerInset)
        textRect = textRect.insetBy(dx: padding, dy: 0)
        (self.placeHolder as NSString).draw(in: textRect, withAttributes: [
            .font: self.font ?? UIFont.theme.bodyLarge,
            .foregroundColor: self.placeHolderColor,
            .paragraphStyle: self.typingAttributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
        ])
    }

    public override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard rect.height > 0 else { return rect }
        let font = self.typingAttributes[.font] as? UIFont ?? self.font ?? UIFont.theme.bodyLarge
        let height = ceil(font.pointSize)
        // A wrapped caret can already be on the next line before the field grows.
        let isFirstLine = rect.minY < self.textContainerInset.top + height
        let textLift = (self.textContainerInset.bottom - self.textContainerInset.top) / 2
        let centerY = self.bounds.height == Self.singleLineHeight && isFirstLine ? self.bounds.midY : rect.midY + textLift
        rect.origin.y = centerY - height / 2
        rect.size.height = height
        return rect
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.cornerRadius(Appearance.chat.inputBarCorner)
        self.setNeedsDisplay()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidChangeNotification, object: self)
    }
    
}

