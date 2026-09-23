import UIKit

/// Audio message `default` height.
public var audioHeight = CGFloat(36)

/// File message `default` height.
public var fileHeight = CGFloat(60)

/// Combine message `default` height.
public var combineHeight = CGFloat(98)

/// Location message `default` height.
public var locationHeight = CGFloat(70)

/// Custom contact card message `default` height.
public var contactCardHeight = CGFloat(90)

/// Alert message `default` height.
public var alertHeight = CGFloat(30)

/// Time divider `default` height.
public var timeDividerHeight = CGFloat(28)

/// The time divider repeats itself only if the interval between two adjacent messages is longer than this value(milliseconds).
public let timeDividerInterval: Int64 = 5*60*1000

/// Extension key of the message that renders a time divider in the message list.
public let timeDividerKey = "ease_chat_uikit_time_divider"

/// Limit width of the message bubble.
public var limitBubbleWidth = CGFloat(ScreenWidth*(3/5.0))

/// Custom message `default` size exclude Alert&Contact.
public var extraCustomSize = CGSize(width: limitBubbleWidth, height: 36)

/// Image bubble limited height.
public let limitImageHeight = CGFloat((300/844)*ScreenHeight)

/// Image bubble limited width.
public let limitImageWidth = CGFloat((225/390)*ScreenWidth)

public let translationKey = "EaseChatUIKit_force_show_translation"

/// Extension key under which the voice-to-text result is persisted on the voice message.
public let voiceToTextKey = "EaseChatUIKit_voice_to_text"

/// Extension key marking a transcribed voice message as collapsed (transcription hidden).
/// Session-only on purpose: collapsing is a local view state, unlike the transcription text itself.
public let voiceToTextHiddenKey = "EaseChatUIKit_voice_to_text_hidden"

public let topicHeight = CGFloat(58)

public let reactionHeight = CGFloat(30)

public let reactionMaxWidth = Appearance.chat.contentStyle.contains(.withAvatar) ? ScreenWidth-48*2:40

public let urlPreviewImageHeight = CGFloat(137)

@objcMembers open class MessageEntity: NSObject {
    
    required public override init() {
        super.init()
    }
    
    public var message: ChatMessage = ChatMessage(conversationID: "", body: ChatTextMessageBody(text: ""), ext: nil)

    /// Whether the entity renders a centered time divider in the message list.
    public var isTimeDivider = false

    /// Text shown by the time divider. Only used when ``isTimeDivider`` is true.
    public var dividerText = ""

    /// Whether the entity is an alert message that only shows tips in the message list, such as a thread tip or the time divider.
    /// It's not a real message, so it can't be selected, forwarded or deleted.
    public var isAlertMessage: Bool {
        if self.isTimeDivider {
            return true
        }
        if let body = self.message.body as? ChatCustomMessageBody,body.event == EaseChatUIKit_alert_message {
            return true
        }
        return false
    }

    public var urlPreview: URLPreviewManager.HTMLContent?
    
    public var showUserName: String {
        if let remark = self.message.user?.remark,!remark.isEmpty {
            return remark
        }
        if let nickname = self.message.user?.nickname,!nickname.isEmpty {
            return nickname
        }
        return self.message.from
    }
    
    public var visibleReactionToIndex = 0
    
    /// Whether combine history message or not.
    public var historyMessage: Bool = false
    
    /// Whether text message contain URL or not.
    public var containURL = false
    
    /// What if text message contain url array first
    public var previewURL = ""
    
    /// URL preview result state.
    public var previewResult = URLPreviewResult.parsing
    
    public var previewFinished: ((MessageEntity) -> Void)?
    
    /// Whether message show translations or not.
    public var showTranslation: Bool {
        set {
            if !newValue {
                if self.message.ext != nil {
                    self.message.ext?.removeValue(forKey: translationKey)
                }
            } else {
                if self.message.ext == nil {
                    self.message.ext = [translationKey:newValue]
                } else {
                    self.message.ext?[translationKey] = newValue
                }
                ChatClient.shared().chatManager?.update(self.message)
            }
        }
        get {
            if self.historyMessage == false {
                return (self.message.ext?[translationKey] as? Bool) ?? false
            }
            return false
        }
    }

    /// Whether a transcribed voice message currently shows its transcription.
    ///
    /// Toggling to `false` only stamps a session-only flag in the message extension (no
    /// `update(message)` round trip, mirroring how ``showTranslation`` removal behaves);
    /// toggling back to `true` simply clears the flag since the transcription text persists
    /// under ``voiceToTextKey``.
    public var showVoiceTranscription: Bool {
        set {
            if newValue {
                self.message.ext?.removeValue(forKey: voiceToTextHiddenKey)
            } else {
                if self.message.ext == nil {
                    self.message.ext = [voiceToTextHiddenKey:true]
                } else {
                    self.message.ext?[voiceToTextHiddenKey] = true
                }
            }
        }
        get {
            return !((self.message.ext?[voiceToTextHiddenKey] as? Bool) ?? false)
        }
    }

    /// /// Message state.
    public var state: ChatMessageStatus = .sending
    
    /// Whether audio message playing or not.
    public var playing = false
    
    public var selected = false
    
    /// Message status image.
    public var stateImage: UIImage? {
        self.getStateImage()
    }
    
    open func getStateImage() -> UIImage? {
        switch self.state {
        case .sending:
            return UIImage(chatNamed: "message_status_spinner")
        case .succeed:
            return UIImage(chatNamed: "message_status_succeed")
        case .failure:
            return UIImage(chatNamed: "message_status_failure")
        case .delivered:
            return UIImage(chatNamed: "message_status_delivery")
        case .read:
            return UIImage(chatNamed: "message_status_read")
        }
    }
    
    /// Reply bubble size in the message.
    public lazy var replySize: CGSize = {
        self.updateReplySize()
    }()
    
    /// Bubble size of the message.
    public lazy var bubbleSize: CGSize = {
        self.updateBubbleSize()
    }()
    
    /// Height for row.
    public lazy var height: CGFloat = {
        self.cellHeight()
    }()
    
    /// Text of the time divider that shown in front of ``message``.
    /// Today shows `HH:mm`, yesterday shows `昨天 HH:mm`, earlier shows `M月d日 HH:mm`.
    open func timeDividerText() -> String {
        let messageDate = Date(timeIntervalSince1970: TimeInterval(self.message.timestamp/1000))
        let time = messageDate.chat.dateString("HH:mm")
        switch messageDate.chat.compareDays() {
        case 0:
            return time
        case -1:
            return "Yesterday".chat.localize+" "+time
        default:
            return messageDate.chat.dateString("M月d日")+" "+time
        }
    }

    /// Whether the nickname row is actually displayed(group + receive only).
    open func showNickName() -> Bool {
        Appearance.chat.contentStyle.contains(.withNickName) && self.message.direction == .receive && self.message.chatType == .groupChat
    }

    open func cellHeight() -> CGFloat {
        if self.isTimeDivider {
            return timeDividerHeight
        }
        let nickBlock: CGFloat = self.showNickName() ? 18:0
        let replyBlock: CGFloat = (Appearance.chat.contentStyle.contains(.withReply) && self.replySize.height > 0) ? self.replySize.height+2:0
        let bottomBlock: CGFloat = Appearance.chat.contentStyle.contains(.withDateAndTime) ? 34:18
        let contentHeight = nickBlock+replyBlock+self.bubbleSize.height+bottomBlock+self.topicContentHeight()+self.reactionContentHeight()+self.bottomAccessoryHeight
        if message.body.type != .custom {
            return contentHeight
        } else {
            if let body = self.message.body as? ChatCustomMessageBody,body.event == EaseChatUIKit_user_card_message {
                return contentHeight
            }
            return self.bubbleSize.height
        }
    }
    
    open func reactionMenuWidth() -> CGFloat {
        if self.message.messageId.isEmpty {
            return 0
        }
        if !Appearance.chat.contentStyle.contains(.withMessageReaction) {
            return 0
        }
        if let reactions = self.message.reactionList {
            if reactions.count > 0 {
                var width = CGFloat(0)
                for (index,reaction) in reactions.enumerated() {
                    let newWidth = width + CGFloat(reaction.reactionWidth+(index > 0 ? 4:0))
                    if newWidth < reactionMaxWidth - 30 {
                        width = newWidth
                        self.visibleReactionToIndex = index
                    } else {
                        self.visibleReactionToIndex = index
                        return width
                    }
                }
                return width
            }
            return 0
        }
        return 0
    }
    
    open func topicContentHeight() -> CGFloat {
        if self.message.messageId.isEmpty {
            return 0
        }
        let realHeight = self.message.chatThread != nil ? topicHeight:CGFloat(0)
        let topic_height = Appearance.chat.contentStyle.contains(.withMessageThread) ? realHeight:0
        return topic_height
    }
    
    open func reactionContentHeight() -> CGFloat {
        if self.message.messageId.isEmpty {
            return 0
        }
        let realHeight = (self.message.reactionList?.count ?? 0) > 0 ? reactionHeight:CGFloat(0)
        let reaction_height = (Appearance.chat.contentStyle.contains(.withMessageReaction) ? realHeight:CGFloat(0))
        return reaction_height
    }
    
    /// Text message show content.
    public private(set) lazy var content: NSAttributedString? = {
        self.convertTextAttribute()
    }()
    
    public lazy var topicContent: NSAttributedString? = {
        self.convertTopicContent()
    }()
    
    /// Text message show translation
    public private(set) lazy var translation: NSAttributedString? = {
        if Appearance.chat.enableTranslation {
            return self.convertTextTranslationAttribute()
        } else {
            return nil
        }
    }()

    /// Voice message transcribed text, read from the extension where ``MessageListViewModel/voiceToText(message:)``
    /// persists it, falling back to the SDK's ``ChatAudioMessageBody/text`` for the current session.
    public private(set) lazy var voiceTranscription: NSAttributedString? = {
        self.convertVoiceTranscription()
    }()
    
    /// Reply title in bubble on current message.
    public private(set) lazy var replyTitle: NSAttributedString? = {
        self.convertReplyTitle()
    }()
    
    
    
    open func convertReplyTitle() -> NSAttributedString? {
        if let quoteMessage = self.message.quoteMessage {
            var showUserName = ""
            if showUserName.isEmpty {
                showUserName = quoteMessage.user?.remark ?? ""
            }
            if showUserName.isEmpty {
                showUserName = quoteMessage.user?.nickname ?? ""
            }
            if showUserName.isEmpty {
                showUserName = quoteMessage.from
            }
            return NSAttributedString {
                AttributedText(showUserName).font(Font.theme.labelSmall).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralSpecialColor6:UIColor.theme.neutralSpecialColor5)
            }
        } else {
            if self.message.quoteMessageId.isEmpty {
                return nil
            } else {
                return NSAttributedString {
                    AttributedText("message doesn't exist".chat.localize).font(Font.theme.labelSmall).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralSpecialColor6:UIColor.theme.neutralSpecialColor5)
                }
            }
        }
    }
    
    public private(set) lazy var replyContent: NSAttributedString? = {
        self.convertToReply()
    }()
            
    /// Calculate bubble size.
    /// - Returns: ``CGSize`` of bubble.
    open func updateBubbleSize() -> CGSize {
        switch self.message.body.type {
        case .text: return self.textBubbleSize()
        case .image: return self.thumbnailSize(video: false)
        case .voice: return self.audioSize()
        case .video: return self.thumbnailSize(video: true)
        case .file:  return CGSize(width: limitBubbleWidth, height: fileHeight)
        case .location: return self.message.contentSize
        case .combine:
            if let body = self.message.body as? ChatCombineMessageBody {
                if self.historyMessage {
                    return CGSize(width: ScreenWidth-68, height: 20)
                } else {
                    var summaryHeight = body.summary?.chat.sizeWithText(font: UIFont.theme.bodySmall, size: CGSize(width: limitBubbleWidth-24, height: combineHeight-14)).height ?? 0
                    if summaryHeight < 16 {
                        summaryHeight = 16
                    }
                    return CGSize(width: limitBubbleWidth, height: summaryHeight+(self.message.direction == .receive ? 30:20))
                }
            }
            return .zero
        case .custom: return self.customSize()
        default:
            return CGSize(width: limitBubbleWidth, height: 30)
        }
    }
    
    open func textSize() -> CGSize {
        let label = UILabel().numberOfLines(0).lineBreakMode(.byWordWrapping)
        let textAttribute = self.convertTextAttribute()
        label.attributedText = textAttribute
        let size = label.sizeThatFits(CGSize(width: self.historyMessage ? ScreenWidth-68:limitBubbleWidth-24, height: 9999))
        var width = size.width+(self.historyMessage ? 68:24)
        let textHeight = size.height
        if textAttribute?.string.count ?? 0 <= 1,self.message.body.type == .text {
            width += 8
        }
        return CGSize(width: width, height: textHeight)
    }
    
    open func textBubbleSize() -> CGSize {
        let textSize = self.textSize()
        var width = textSize.width
        let textHeight = textSize.height

        let translateSize = Appearance.chat.enableTranslation ? self.translationSize():.zero
        if width < translateSize.width {
            width = translateSize.width+16
        }
        var height = 6.5+textHeight+(self.message.edited ? 20:6)+(self.showTranslation ? translateSize.height+28:0)
        if self.message.edited {
            width += 44
        }
        if Appearance.chat.bubbleStyle == .withArrow,self.historyMessage == false,self.message.body.type != .text {
            width += 5
        }
        if Appearance.chat.enableURLPreview {
            let increase = self.urlPreviewHeight()
            height += increase
            if increase >= 38 {
                width = limitBubbleWidth
            }
        }
        if height < 36.5 {
            height = 36.5
        }
        return CGSize(width: width, height: height)
    }
    
    @objc open func urlPreviewHeight() -> CGFloat {
        var increase:CGFloat = 0
        if self.containURL,!self.historyMessage,self.previewResult != .failure,!self.previewURL.isEmpty {
            if self.urlPreview != nil {
                increase += 4
                if let url = self.urlPreview?.imageURL,!url.isEmpty {
                    increase += urlPreviewImageHeight
                }
                if let title = self.urlPreview?.title ,!title.isEmpty {
                    if let title = self.urlPreview?.titleAttribute  {
                        let titleHeight = UILabel().numberOfLines(2).font(UIFont.theme.headlineSmall).attributedText(title).sizeThatFits(CGSize(width: limitBubbleWidth-24, height: 50)).height
                        increase += (titleHeight+16)
                    }
                }
                if let description = self.urlPreview?.descriptionHTML, !description.isEmpty {
                    if let description = self.urlPreview?.descriptionHTML {
                        let descriptionHeight = UILabel().numberOfLines(3).font(UIFont.theme.bodySmall).text(description).sizeThatFits(CGSize(width: limitBubbleWidth-24, height: 9999)).height
                        increase += (descriptionHeight+8)
                    }
                }
            } else {
                increase = 38
            }
        }
        return increase
    }
    
    open func previewStart() {
        if self.previewURL.isEmpty,self.previewResult == .parsing,self.urlPreview != nil {
            return
        }
        URLPreviewManager.preview(from: self.previewURL) { [weak self] (error, content) in
            guard let `self` = self else { return }
            if error == nil {
                if let content = content {
                    content.towards = self.message.direction == .send ? .right:.left
                    self.urlPreview = content
                    self.previewResult = .success
                    var storage = content.toDictionary()
                    storage["url"] = self.previewURL
                    storage["status"] = "1"
                    self.message.ext?["ease_chat_uikit_text_url_preview"] = storage
                    URLPreviewManager.caches[self.previewURL] = content
                }
            } else {
                self.previewResult = .failure
                self.message.ext?["ease_chat_uikit_text_url_preview"] = ["status":"0","url":self.previewURL]
                if let error = error as? NSError {
                    consoleLogInfo("URLPreviewManager preview \(self.previewURL) error:\(error.localizedDescription)", type: .error)
                }
            }
            
            ChatClient.shared().chatManager?.update(self.message)
            
            DispatchQueue.main.async {
                self.bubbleSize = self.updateBubbleSize()
                self.height = self.cellHeight()
                self.previewFinished?(self)
            }

        }
    }
    
    open func translationSize() -> CGSize {
        if self.showTranslation {
            let label = UILabel().numberOfLines(0)
            label.attributedText = self.convertTextTranslationAttribute()
            let size = label.sizeThatFits(CGSize(width: limitBubbleWidth-24, height: 9999))
            let width = size.width+24
            return CGSize(width: width < 86 ? 86:width, height: size.height+10)
        } else {
            return .zero
        }
    }
    
    open func thumbnailSize(video: Bool) -> CGSize {
        if let body = self.message.body as? ChatImageMessageBody,body.isGif {
            /// Built-in gifs sent from the emoji panel are named `N.gif`(aligned with `N.gif` in `EaseChatResource.bundle`),display them at a fixed size of 150*150.
            let resourceName = body.displayName.components(separatedBy: ".").first ?? ""
            if Int(resourceName) != nil,Bundle.chatBundle.path(forResource: resourceName, ofType: "gif") != nil {
                return CGSize(width: 150, height: 150)
            }
        }
        let defaultSize = CGSize(width: 135, height: 135)
        var size = CGSize.zero
        if let body = self.message.body as? ChatImageMessageBody {
            size = body.size
        }
        if let body = self.message.body as? ChatVideoMessageBody {
            size = body.thumbnailSize
        }
        if size == .zero {
            if let body = self.message.body as? ChatImageMessageBody {
                if size == .zero {
                    if let path = body.thumbnailLocalPath,FileManager.default.fileExists(atPath: path) {
                        size = UIImage(contentsOfFile: path)?.size ?? .zero
                    } else {
                        if let localPath = body.localPath,FileManager.default.fileExists(atPath: localPath) {
                            size = UIImage(contentsOfFile: localPath)?.size ?? .zero
                        }
                    }
                }
            }
            if let body = self.message.body as? ChatVideoMessageBody {
                size = body.thumbnailSize
            }
            
            
            if size == .zero {
                size = defaultSize
            }
        }
        let scale = size.width/size.height
        switch scale {
        case 0...0.1:
            return CGSize(width: limitImageHeight/10.0, height: limitImageHeight)
        case 0.1...0.75:
            return CGSize(width: limitImageHeight*(size.width/size.height), height: limitImageHeight)
        case 0.7501...10:
            return CGSize(width: limitImageWidth, height: limitImageWidth*(size.height/size.width))
        case 10...:
            return CGSize(width: limitImageWidth, height: limitImageWidth/10.0)
        default:
            return .zero
        }
    }
    
    open func audioSize() -> CGSize {
        var size = CGSize.zero
        switch Int((self.message.body as? ChatAudioMessageBody)?.duration ?? 1) {
        case 0...9:
            size = CGSize(width: 75, height: audioHeight)
        case 10...19:
            size = CGSize(width: 100, height: audioHeight)
        case 20...29:
            size = CGSize(width: 125, height: audioHeight)
        case 30...39:
            size = CGSize(width: 150, height: audioHeight)
        case 40...49:
            size = CGSize(width: 175, height: audioHeight)
        case 50...Appearance.chat.audioDuration:
            size = CGSize(width: limitBubbleWidth, height: audioHeight)
        default:
            size = .zero
        }
        return size
    }
    
    open func customSize() -> CGSize {
        if let body = self.message.body as? ChatCustomMessageBody {
            switch body.event {
            case EaseChatUIKit_user_card_message:
                return CGSize(width: self.historyMessage ? ScreenWidth-32:limitBubbleWidth, height: contactCardHeight)
            case EaseChatUIKit_alert_message:
                let label = UILabel().numberOfLines(0).lineBreakMode(.byWordWrapping)
                label.attributedText = self.convertTextAttribute()
                let size = label.sizeThatFits(CGSize(width: ScreenWidth-32, height: 9999))
                // The alert message only shows its content now, 16pt padding on the top and bottom is enough.
                return CGSize(width: ScreenWidth-32, height: size.height+32)
            default:
                return self.message.contentSize
            }
        } else {
            return .zero
        }
    }
    
    /// Converts the message text into an attributed string, including the user's nickname, message text, and emojis.
    open func convertTextAttribute() -> NSAttributedString? {
        if self.message.messageId.isEmpty {
            return nil
        }
        var text = NSMutableAttributedString()
        if self.message.messageId.isEmpty {
            return NSMutableAttributedString {
                AttributedText("No Messages".chat.localize).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor7).font(UIFont.theme.labelSmall).lineHeight(multiple: 1.15, minimum: 18)
            }
        }
        var textColor = self.message.direction == .send ? Appearance.chat.sendTextColor:Appearance.chat.receiveTextColor
        if self.historyMessage {
            textColor = Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1
        }
        if self.message.body.type != .text, self.message.body.type != .custom {
            text.append(NSAttributedString {
                AttributedText(self.message.showType+self.message.showContent).foregroundColor(textColor).font(self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge).lineHeight(multiple: 1.15, minimum: self.historyMessage ? 18:16).lineBreakMode(.byWordWrapping)
            })
            return text
        }
        if self.historyMessage,self.message.body.type == .custom {
            text.append(NSAttributedString {
                AttributedText(self.message.showType+self.message.showContent).foregroundColor(textColor).font(self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge).lineBreakMode(.byWordWrapping).lineHeight(multiple: 1.15, minimum: self.historyMessage ? 18:16)
            })
            return text
        }
        if self.message.body.type == .custom,let body = self.message.body as? ChatCustomMessageBody {
            switch body.event {
            case EaseChatUIKit_alert_message:
                if let something = self.message.ext?["something"] as? String {
                    if let threadName = self.message.ext?["threadName"] as? String {
                        let range = something.chat.rangeOfString(threadName)
                        text.append(NSAttributedString {
                            AttributedText(something).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor7).font(UIFont.theme.bodySmall).lineHeight(multiple: 1.15, minimum: 14).alignment(.center)
                        })
                        text.addAttribute(NSAttributedString.Key.foregroundColor, value: Theme.style == .dark ? Color.theme.primaryDarkColor:Color.theme.primaryLightColor, range: range)
                    } else {
                        let user = self.message.user
                        var nickname = user?.remark ?? ""
                        if nickname.isEmpty {
                            nickname = user?.nickname ?? ""
                            if nickname.isEmpty {
                                nickname = self.message.from
                            }
                        }
                        text.append(NSMutableAttributedString {
                            AttributedText(nickname).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor7).font(UIFont.theme.labelSmall).lineHeight(multiple: 1.15, minimum: 14).alignment(.center)
                        })
                        text.append(NSAttributedString {
                            AttributedText(" "+something).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor7).font(UIFont.theme.bodySmall).lineHeight(multiple: 1.15, minimum: 14).alignment(.center)
                        })
                    }
                    
                }
                
            default:
                text.append(NSAttributedString {
                    AttributedText(self.message.showType+self.message.showContent).foregroundColor(textColor).font(self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge).lineHeight(multiple: 1.15, minimum: self.historyMessage ? 16:18).lineBreakMode(.byWordWrapping)
                })
                break
            }
            
        } else {
            var result = self.message.showType
            
            for (key,value) in ChatEmojiConvertor.shared.oldEmojis {
                result = result.replacingOccurrences(of: key, with: value)
            }
            if self.message.mention.isEmpty {
                text.append(NSMutableAttributedString {
                    AttributedText(result).foregroundColor(textColor).font(self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge).lineHeight(multiple: 1.15, minimum: self.historyMessage ? 16:18).lineBreakMode(.byWordWrapping)
                })
            } else {
                if self.message.mention == ChatUIKitContext.shared?.currentUserId ?? "" {
                    let mentionUser = ChatUIKitContext.shared?.userCache?[ChatUIKitContext.shared?.currentUserId ?? ""]
                    var nickname = mentionUser?.remark ?? ""
                    if nickname.isEmpty {
                        nickname = mentionUser?.nickname ?? ""
                        if nickname.isEmpty {
                            nickname = ChatUIKitContext.shared?.currentUserId ?? ""
                        }
                    }
                    let content = result
                    
                    let mentionRange = content.lowercased().chat.rangeOfString(nickname)
                    let range = NSMakeRange(mentionRange.location-1, mentionRange.length+1)
                    let mentionAttribute = NSMutableAttributedString {
                        AttributedText(content).foregroundColor(textColor).font(self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge).lineHeight(multiple: 1.15, minimum: self.historyMessage ? 16:18).lineBreakMode(Appearance.chat.targetLanguage == .Chinese ? .byCharWrapping:.byWordWrapping)
                    }
                    if mentionRange.location != NSNotFound,mentionRange.length != NSNotFound {
                        mentionAttribute.addAttribute(.foregroundColor, value: (Theme.style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor), range: range)
                    }
                    text.append(mentionAttribute)
                } else {
                    let content = result
                    
                    let mentionRange = content.lowercased().chat.rangeOfString(self.message.mention.lowercased())
                    let range = NSMakeRange(mentionRange.location-1, mentionRange.length+1)
                    let mentionAttribute = NSMutableAttributedString {
                        AttributedText(content).foregroundColor(textColor).font(self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge).lineHeight(multiple: 1.15, minimum: self.historyMessage ? 16:18).lineBreakMode(.byWordWrapping)
                    }
                    if mentionRange.location != NSNotFound,mentionRange.length != NSNotFound {
                        mentionAttribute.addAttribute(.foregroundColor, value: (Theme.style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor), range: range)
                    }
                    text.append(mentionAttribute)
                }
                
            }
            let string = text.string as NSString
            for symbol in ChatEmojiConvertor.shared.emojis {
                if string.range(of: symbol).location != NSNotFound {
                    let ranges = text.string.chat.rangesOfString(symbol)
                    text = ChatEmojiConvertor.shared.convertEmoji(input: text, ranges: ranges, symbol: symbol,imageBounds: CGRect(x: 0, y: -4, width: 18, height: 18))
                    text.addAttribute(.font, value: self.historyMessage ? UIFont.theme.bodyMedium:UIFont.theme.bodyLarge, range: NSMakeRange(0, text.length))
                    text.addAttribute(.foregroundColor, value: textColor, range: NSMakeRange(0, text.length))
                }
            }
            if !Appearance.chat.enableURLPreview {
                return text
            }
            // 创建 NSDataDetector 实例以检测文本中的链接
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue ) else {
                return text
            }


            // 检测文本中的链接
            let matches = detector.matches(in: text.string, options: [], range: NSRange(location: 0, length: text.string.count))
            if matches.count == 1 {
                self.containURL = true
            } else {
                self.containURL = false
                self.previewURL = ""
                self.urlPreview = nil
                self.previewResult = .failure
                return text
            }
            if let result = matches.first, result.range.length > 0,result.range.location != NSNotFound,let linkURL = result.url {
                self.previewURL = linkURL.absoluteString
                let receiveLinkColor = Theme.style == .dark ? UIColor.theme.primaryDarkColor:UIColor.theme.primaryLightColor
                let sendLinkColor = Appearance.chat.sendTextColor
                let color = self.message.direction == .send ? sendLinkColor:receiveLinkColor
                text.addAttributes([.link:linkURL,.underlineStyle:NSUnderlineStyle.single.rawValue,.underlineColor:color,.foregroundColor:color], range: result.range)
            }
        }

        return text
    }
    
    open func convertTopicContent() -> NSAttributedString? {
        if self.message.messageId.isEmpty {
            return nil
        }
        var text = NSMutableAttributedString()
        guard let topicMessage = self.message.chatThread?.lastMessage else {
            text.append(NSAttributedString {
                AttributedText("No Messages".chat.localize).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor6:UIColor.theme.neutralColor5).font(UIFont.theme.labelSmall)
            })
            return text
        }
        var nickname = topicMessage.user?.remark ?? ""
        if nickname.isEmpty {
            nickname = topicMessage.user?.nickname ?? ""
        }
        if nickname.isEmpty {
            nickname = topicMessage.from
        }
        if topicMessage.body.type != .text {
            text.append(NSAttributedString {
                AttributedText(nickname+":"+topicMessage.showType).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor6:UIColor.theme.neutralColor5).font(UIFont.theme.labelSmall)
            })
            return text
        } else {
            var result = nickname+":"+topicMessage.showType
            for (key,value) in ChatEmojiConvertor.shared.oldEmojis {
                result = result.replacingOccurrences(of: key, with: value)
            }
            text.append(NSAttributedString {
                AttributedText(result).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor6:UIColor.theme.neutralColor5).font(UIFont.theme.labelSmall)
            })
            let string = text.string as NSString
            for symbol in ChatEmojiConvertor.shared.emojis {
                if string.range(of: symbol).location != NSNotFound {
                    let ranges = text.string.chat.rangesOfString(symbol)
                    text = ChatEmojiConvertor.shared.convertEmoji(input: text, ranges: ranges, symbol: symbol,imageBounds: CGRect(x: 0, y: -2, width: 14, height: 14))
                    text.addAttribute(.font, value: UIFont.theme.labelSmall, range: NSMakeRange(0, text.length))
                    text.addAttribute(.foregroundColor, value: Theme.style == .dark ? UIColor.theme.neutralColor6:UIColor.theme.neutralColor5, range: NSMakeRange(0, text.length))
                }
            }
        }
        return text
    
    }
    
    open func convertTextTranslationAttribute() -> NSAttributedString? {
        if self.message.messageId.isEmpty {
            return nil
        }
        var text = NSMutableAttributedString()
        if self.message.body.type != .text {
            text.append(NSAttributedString {
                AttributedText(self.message.showType).foregroundColor(self.message.direction == .send ? Appearance.chat.sendTranslationColor:Appearance.chat.receiveTranslationColor).font(UIFont.theme.bodyLarge).lineBreakMode(.byWordWrapping)
            })
            return text
        } else {
            var result = self.message.translation ?? self.message.showType
            for (key,value) in ChatEmojiConvertor.shared.oldEmojis {
                result = result.replacingOccurrences(of: key, with: value)
            }
            text.append(NSAttributedString {
                AttributedText(result).foregroundColor(self.message.direction == .send ? Appearance.chat.sendTranslationColor:Appearance.chat.receiveTranslationColor).font(UIFont.theme.bodyLarge).lineBreakMode(.byWordWrapping)
            })
            let string = text.string as NSString
            for symbol in ChatEmojiConvertor.shared.emojis {
                if string.range(of: symbol).location != NSNotFound {
                    let ranges = text.string.chat.rangesOfString(symbol)
                    text = ChatEmojiConvertor.shared.convertEmoji(input: text, ranges: ranges, symbol: symbol, imageBounds: CGRect(x: 0, y: -4, width: 18, height: 18))
                    let range = NSMakeRange(0, text.length)
                    text.addAttribute(.font, value: UIFont.theme.bodyLarge, range: range)
                    text.addAttribute(.foregroundColor, value: self.message.direction == .send ? Appearance.chat.sendTranslationColor:Appearance.chat.receiveTranslationColor, range: range)
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineBreakMode = .byWordWrapping
//                    paragraphStyle.lineHeightMultiple = 1.15
                    text.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
                }
            }
            return text
        }
    }

    /// Builds the attributed transcription for a voice message, or nil if it hasn't been transcribed yet or is collapsed.
    open func convertVoiceTranscription() -> NSAttributedString? {
        guard self.message.body.type == .voice else { return nil }
        guard self.showVoiceTranscription else { return nil }
        var transcribed = self.message.ext?[voiceToTextKey] as? String
        if transcribed == nil {
            transcribed = (self.message.body as? ChatAudioMessageBody)?.text
        }
        guard let transcribed = transcribed,!transcribed.isEmpty else { return nil }
        return NSAttributedString {
            AttributedText(transcribed).foregroundColor(self.message.direction == .send ? Appearance.chat.sendTranslationColor:Appearance.chat.receiveTranslationColor).font(UIFont.theme.bodySmall).lineBreakMode(.byWordWrapping)
        }
    }

    /// Extra height reserved below the bubble for auxiliary content. ``AudioMessageCell`` renders the
    /// voice-to-text card in this space,and ``MessageCell`` subtracts the same amount from its
    /// bottom-anchored layout so the bubble lifts instead of overlapping the card.
    public var bottomAccessoryHeight: CGFloat {
        if self.historyMessage || self.message.body.type != .voice {
            return 0
        }
        let transcriptionSize = self.voiceTranscriptionSize()
        return transcriptionSize.height > 0 ? transcriptionSize.height+24:0
    }

    /// The laid-out size of ``voiceTranscription`` at the bubble's available width.
    open func voiceTranscriptionSize() -> CGSize {
        guard let transcription = self.voiceTranscription else { return .zero }
        let label = UILabel().numberOfLines(0).lineBreakMode(.byWordWrapping)
        label.attributedText = transcription
        return label.sizeThatFits(CGSize(width: limitBubbleWidth-24, height: 9999))
    }

    open func updateReplySize() -> CGSize {
        if let attributeContent = self.convertToReply() {
            if let attributeTitle = self.replyTitle,attributeContent.length > 0,attributeContent.string != "message doesn't exist".chat.localize {
                let labelTitle = UILabel().numberOfLines(1).lineBreakMode(.byWordWrapping)
                let labelContent = UILabel().numberOfLines(2).lineBreakMode(.byWordWrapping)
                labelTitle.attributedText = attributeTitle
                labelContent.attributedText = attributeContent
                let titleSize = labelTitle.sizeThatFits(CGSize(width: limitBubbleWidth, height: 16))
                let contentSize = labelContent.sizeThatFits(CGSize(width: limitBubbleWidth, height: 36))
                if self.message.quoteMessage!.body.type == .image || self.message.quoteMessage!.body.type == .video {
                    return CGSize(width: (titleSize.width > contentSize.width ? titleSize.width:contentSize.width)+78, height: 36+16)
                } else {
                    return CGSize(width: (titleSize.width > contentSize.width ? titleSize.width:contentSize.width)+24, height: contentSize.height+34)
                }
            } else {
                let labelContent = UILabel().numberOfLines(2).lineBreakMode(.byWordWrapping)
                labelContent.attributedText = attributeContent
                let contentSize = labelContent.sizeThatFits(CGSize(width: limitBubbleWidth, height: 36))
                return CGSize(width: contentSize.width+10, height: contentSize.height+10)
            }
        }
        return .zero
    }
        
    open func convertToReply() -> NSAttributedString? {
        if self.message.quoteMessageId.isEmpty {
            return nil
        }
        if let quoteMessage = self.message.quoteMessage {
            if let msgSender = self.message.quoteMessage?.from,!msgSender.isEmpty  {
//                let showName = quoteMessage.user?.nickName ?? msgSender
                let reply = NSMutableAttributedString()
                if let icon = quoteMessage.replyIcon?.withTintColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5) {
                    reply.append(NSAttributedString {
                        ImageAttachment(icon, bounds: CGRect(x: 0, y: -4, width: 18, height: 18))
                    })
                }
                switch quoteMessage.body.type {
                case .text:
                    reply.append(NSAttributedString {
                        AttributedText(quoteMessage.showType).font(Font.theme.labelMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                    })
                case .image,.video,.combine,.location:
                    reply.append(NSAttributedString {
                        AttributedText(quoteMessage.showType).font(Font.theme.labelMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                    })
                case .file,.voice:
                    reply.append(NSAttributedString {
                        AttributedText(quoteMessage.showType).font(Font.theme.labelMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                        AttributedText(quoteMessage.showContent).font(Font.theme.bodyMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                    })
                case .custom:
                    if let body = quoteMessage.body as? ChatCustomMessageBody,body.event == EaseChatUIKit_user_card_message {
                        reply.append(NSAttributedString {
                            AttributedText(quoteMessage.showType).font(Font.theme.labelMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                            AttributedText(quoteMessage.showContent).font(Font.theme.bodyMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                        })
                    } else {
                        reply.append(NSAttributedString {
                            AttributedText("message doesn't exist".chat.localize).font(Font.theme.bodyMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                        })
                    }
                default:
                    reply.append(NSAttributedString {
                        AttributedText("message doesn't exist".chat.localize).font(Font.theme.bodyMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                    })
                }
                return reply
            } else {
                return NSAttributedString {
                    AttributedText("message doesn't exist".chat.localize).font(Font.theme.bodyMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5).lineBreakMode(.byWordWrapping)
                }
            }
        } else {
            if self.message.hasQuote {
                return NSAttributedString {
                    AttributedText("message doesn't exist".chat.localize).font(Font.theme.bodyMedium).foregroundColor(Theme.style == .dark ? Color.theme.neutralColor6:Color.theme.neutralColor5)
                }
            } else {
                return nil
            }
        }
    }
}

@objcMembers open class PinnedMessageEntity: NSObject {
    
    required public override init() {
        super.init()
    }
    
    public var message: ChatMessage = ChatMessage(conversationID: "", body: ChatTextMessageBody(text: ""), ext: nil)
    
    public var showUserName: String {
        if let remark = self.message.user?.remark,!remark.isEmpty {
            return remark
        }
        if let nickname = self.message.user?.nickname,!nickname.isEmpty {
            return nickname
        }
        return self.message.from
    }
    
    public var selected = false
    
    public lazy var pinInfo: NSAttributedString? = {
        if let pinInfo = self.message.pinnedInfo {
            var showName = ChatUIKitContext.shared?.chatCache?[pinInfo.operatorId]?.nickname ?? ""
            if showName.isEmpty {
                showName = ChatUIKitContext.shared?.userCache?[pinInfo.operatorId]?.remark ?? ""
            }
            if showName.isEmpty {
                showName = ChatUIKitContext.shared?.userCache?[pinInfo.operatorId]?.nickname ?? ""
            }
            if showName.isEmpty {
                showName = pinInfo.operatorId
            }
            return NSAttributedString {
                AttributedText(showName).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1).font(Font.theme.labelSmall)
                AttributedText(" "+"pinned"+" ").foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1).font(Font.theme.bodySmall)
                AttributedText(self.showUserName).foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1).font(Font.theme.labelSmall)
                AttributedText(" "+"message").foregroundColor(Theme.style == .dark ? UIColor.theme.neutralColor98:UIColor.theme.neutralColor1).font(Font.theme.bodySmall)
            }
        } else {
            return nil
        }
    }()
}


extension ChatMessage {
    
    /// ``ChatUserProfileProtocol``
    @objc public var user: ChatUserProfileProtocol? {
        
        if let senderInfo = senderInfo {
            let user = ChatUserProfile()
            user.id = from
            user.avatarURL = senderInfo.avatarUrl ?? ""
            user.nickname = senderInfo.nickname ?? ""
            user.remark = senderInfo.remark ?? ""
            return user
        }
        let cacheUser = ChatUIKitContext.shared?.userCache?[self.from]
        if cacheUser != nil,let remark = cacheUser?.remark,!remark.isEmpty {
            ChatUIKitContext.shared?.chatCache?[self.from]?.remark = remark
        }
        let chatUser = ChatUIKitContext.shared?.chatCache?[self.from]
        if chatUser?.nickname.isEmpty ?? true {
            chatUser?.nickname = cacheUser?.nickname ?? ""
        }
        if from == ChatClient.shared().currentUsername ?? "",let currentUser = ChatUIKitContext.shared?.currentUser {
            return currentUser
        }
        if chatUser == nil,cacheUser != nil {
            return cacheUser
        }
        return chatUser
    }
    
    /// Whether message edited or not.
    @objc public var edited: Bool {
        if self.body.type != .text {
            return false
        } else {
            if let body = self.body as? ChatTextMessageBody {
                if body.operatorCount > 0,body.operationTime > 0 {
                    return true
                } else {
                    return false
                }
            }
            return false
        }
    }
    
    /// Message display date on conversation list cell.
    @objc open var showDate: String {
        let messageDate = Date(timeIntervalSince1970: TimeInterval(self.timestamp/1000))
        if messageDate.chat.compareDays() < 0 {
            return messageDate.chat.dateString(Appearance.conversation.dateFormatOtherDay)
        } else {
            return messageDate.chat.dateString(Appearance.conversation.dateFormatToday)
        }
    }
    
    /// Message display date on chat cell.
    @objc open var showDetailDate: String {
        let messageDate = Date(timeIntervalSince1970: TimeInterval(self.timestamp/1000))
        if messageDate.chat.compareDays() < 0 {
            return messageDate.chat.dateString(Appearance.chat.dateFormatOtherDay)
        } else {
            return messageDate.chat.dateString(Appearance.chat.dateFormatToday)
        }
    }
    
    /// Message show type on the conversation list.
    @objc open var showType: String {
        var text = "[unknown]".chat.localize
        switch self.body.type {
        case .text: text = (self.body as? ChatTextMessageBody)?.text ?? ""
        case .image: text = "[Image]".chat.localize
        case .voice: text = "[Audio]".chat.localize
        case .video: text = "[Video]".chat.localize
        case .file: text = "[File]".chat.localize
        case .location: text = "[Location]".chat.localize
        case .combine: text = "[\("Chat History".chat.localize)]"
        case .cmd: text = "[Transparent]".chat.localize
        case .custom:
            if let body = self.body as? ChatCustomMessageBody {
                if body.event == EaseChatUIKit_user_card_message {
                    text = "[Contact]".chat.localize
                }
                if body.event == EaseChatUIKit_alert_message {
                    text = ((self.ext?["something"] as? String) ?? "")
                }
            }
        default: break
        }
        return text.chat.localize
    }
    
    @objc open var replyIcon: UIImage? {
        switch self.body.type {
        case .image:
            return UIImage(chatNamed: "reply_image")
        case .voice:
            return UIImage(chatNamed: "reply_audio")
        case .video:
            return UIImage(chatNamed: "reply_video")
        case .file:
            return UIImage(chatNamed: "reply_file")
        case .combine:
            return UIImage(chatNamed: "reply_history")
        case .location:
            return UIImage(chatNamed: "reply_location")
        case .custom:
            if let body = self.body as? ChatCustomMessageBody {
                if body.event == EaseChatUIKit_user_card_message {
                    return UIImage(chatNamed: "reply_contact")
                }
            }
            return nil
        default:
            return nil
        }
    }
    
    /// Message show content.
    @objc open var showContent: String {
        var text = ""
        switch self.body.type {
        case .text: text = (self.body as? ChatTextMessageBody)?.text ?? ""
        case .voice: text = "\((self.body as? ChatAudioMessageBody)?.duration ?? 0)″"
        case .file: text = "\((self.body as? ChatFileMessageBody)?.displayName ?? "")"
        case .location: text = self.showType
        case .custom:
            if let body = self.body as? ChatCustomMessageBody {
                if body.event == EaseChatUIKit_user_card_message {
                    let userId = body.customExt["uid"] ?? ""
                    text = body.customExt["nickname"] ?? userId
                }
                if body.event == EaseChatUIKit_alert_message {
                    text = (self.ext?["something"] as? String) ?? ""
                }
            }
        default: break
        }
        return text
    }
    
    /// Text message if you were mentioned,the property isn't empty.
    @objc public var mention: String {
        if self.body.type == .text && self.direction == .receive,let conversation = ChatClient.shared().chatManager?.getConversation(self.conversationId, type: .groupChat, createIfNotExist: false) {
            if conversation.type == .groupChat {
                if let ext = self.ext, let atList = ext["em_at_list"] {
                    if let atListString = atList as? String {
                        if atListString.lowercased() == "All".lowercased() {
                            return "All"
                        }
                    } else if let atListArray = atList as? [String] {
                        if ChatClient.shared().currentUsername?.count ?? 0 > 0 && atListArray.contains((ChatClient.shared().currentUsername ?? "").lowercased()) {
                            return (ChatUIKitContext.shared?.currentUser?.id ?? self.from).lowercased()
                        }
                    }
                }
            }
        }
        return ""
    }
    
    /// When you send a text message. Quote the message.
    @objc public var quoteMessage: ChatMessage? {
        guard let quoteInfo = self.ext?["msgQuote"] as? Dictionary<String,Any> else { return nil }
        guard let quoteMessageId = quoteInfo["msgID"] as? String else {
            return nil
        }
        return ChatClient.shared().chatManager?.getMessageWithMessageId(quoteMessageId)
    }
    
    /// When you send a text message. Quote the message.
    @objc public var hasQuote: Bool {
        return !self.quoteMessageId.isEmpty
    }
    
    /// When you send a text message. Quote the message.
    @objc public var quoteMessageId: String {
        if self.messageId.isEmpty {
            return ""
        }
        guard let quoteInfo = self.ext?["msgQuote"] as? Dictionary<String,Any>,let messageId = quoteInfo["msgID"] as? String else { return "" }
        return messageId
    }
    
    @objc open var contentSize: CGSize {
        switch self.body.type {
        case .custom:
            return extraCustomSize
        case .location:
            return CGSize(width: limitBubbleWidth, height: locationHeight)
        default:
            return CGSize(width: limitBubbleWidth, height: 30)
        }
    }
    
    /// Translation of the text message.
    @objc public var translation: String? {
        (self.body as? ChatTextMessageBody)?.translations?.first?.value
    }
    
    @objc public var alertMessageThreadId: String {
        self.ext?["threadId"] as? String ?? ""
    }

    /// Whether the message is a local time divider injected by ``MessageListView``, instead of a real one.
    @objc public var isTimeDividerMessage: Bool {
        self.ext?[timeDividerKey] as? Bool ?? false
    }
    
}


