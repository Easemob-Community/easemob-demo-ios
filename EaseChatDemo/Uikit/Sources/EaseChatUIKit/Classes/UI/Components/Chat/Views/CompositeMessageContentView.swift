import UIKit
import AVKit
import MapKit
import QuickLook

public extension ChatMessage {
    /// Each part belongs to the same SDK message and is displayed in wire order.
    var isCompositeMessage: Bool { contentType == .multiBody }

    /// Finds a downloaded image segment, including an SDK file renamed after a collision.
    func cachedCompositeImagePath(at index: Int, originalOnly: Bool = false) -> String? {
        guard isCompositeMessage, bodies[safe: index] is ChatImageMessageBody else { return nil }
        let manager = ChatClient.shared().chatManager
        let stored = manager?.getMessageWithMessageId(messageId)
        let snapshots = [stored, self].compactMap { $0 }.filter { $0.isCompositeMessage }
        let directory = manager?.getMessageAttachmentPath(conversationId)
        return CompositeMessageContentView.cachedAttachment(at: index, in: snapshots, directory: directory,
                                                            originalImageOnly: originalOnly)?.path
    }
}

private extension ChatMessageBody {
    var compositeLabel: String {
        switch self {
        case let body as ChatTextMessageBody:
            return body.text
        case is ChatImageMessageBody:
            return "[Image]".chat.localize
        case is ChatVideoMessageBody:
            return "[Video]".chat.localize
        case is ChatAudioMessageBody:
            return "[Audio]".chat.localize
        case let body as ChatFileMessageBody:
            return body.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "[File]".chat.localize
        case let body as ChatLocationMessageBody:
            let label = [body.buildingName, body.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            return label.isEmpty ? "[Location]".chat.localize : label
        case let body as ChatCustomMessageBody:
            if body.event == EaseChatUIKit_user_card_message {
                return body.customExt?["nickname"] ?? "[Contact]".chat.localize
            }
            return "[Custom message]".chat.localize
        default:
            return "[unknown]".chat.localize
        }
    }
}

final class CompositeMessageContentView: UIView {
    private static let inset: CGFloat = 12
    private static let spacing: CGFloat = 8
    private static let font = UIFont.theme.bodyLarge
    private var message: ChatMessage?
    private var segmentViews: [UIView] = []
    private var segmentTextColor = UIColor.label
    private struct DownloadKey: Hashable {
        let account: String?
        let messageID: String
    }
    private static var activeDownloads = Set<DownloadKey>()
    private struct AudioKey: Equatable {
        let message: DownloadKey
        let index: Int
    }
    private static var playingAudio: AudioKey?
    var allowsOpening = true
    var onSelection: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) { nil }

    static func size(for message: ChatMessage) -> CGSize {
        let width = limitBubbleWidth
        let innerWidth = max(1, width - 2 * inset)
        let bodies = message.bodies
        let height = bodies.reduce(2 * inset) { $0 + segmentHeight($1, width: innerWidth) }
            + CGFloat(max(0, bodies.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    private static func segmentHeight(_ body: ChatMessageBody, width: CGFloat) -> CGFloat {
        if body is ChatAudioMessageBody { return audioHeight }
        if body.type == .file { return fileHeight }
        if body is ChatImageMessageBody || body is ChatVideoMessageBody {
            let size = (body as? ChatImageMessageBody)?.size ?? .zero
            let ratio = size.width > 0 && size.height > 0 ? size.height / size.width : 0.62
            return ceil(min(width * 1.25, max(72, width * ratio)))
        }
        let label = makeLabel(body)
        return max(body is ChatTextMessageBody ? 20 : 36,
                   ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }

    private static func makeLabel(_ body: ChatMessageBody) -> UILabel {
        let label = UILabel()
        label.font = font
        label.numberOfLines = body is ChatTextMessageBody ? 0 : 3
        label.lineBreakMode = body is ChatTextMessageBody ? .byWordWrapping : .byTruncatingTail
        label.text = body.compositeLabel
        return label
    }

    func bind(_ message: ChatMessage?, history: Bool = false) {
        self.message = message
        for view in segmentViews {
            (view as? ImageView)?.cancelPendingImageLoad()
            view.removeFromSuperview()
        }
        segmentViews = message.map { message in
            message.bodies.map { makeSegment($0, direction: message.direction) }
        } ?? []
        segmentViews.forEach { addSubview($0) }
        updateColors(history: history)
        setNeedsLayout()
    }

    func updateColors(history: Bool = false) {
        segmentTextColor = history ? (Theme.style == .dark ? UIColor.theme.neutralColor98 : UIColor.theme.neutralColor1)
            : (message?.direction == .send ? Appearance.chat.sendTextColor : Appearance.chat.receiveTextColor)
        for case let label as UILabel in segmentViews { label.textColor = segmentTextColor }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let message else { return }
        let width = max(1, bounds.width - 2 * Self.inset)
        var y = Self.inset
        for (index, (body, view)) in zip(message.bodies, segmentViews).enumerated() {
            let height = Self.segmentHeight(body, width: width)
            if let audio = body as? ChatAudioMessageBody, let audioView = view as? AudioMessageView {
                let preferredWidth = MessageEntity.audioSize(duration: Int(audio.duration)).width
                let audioWidth = min(width, max(75, preferredWidth))
                let x = Self.inset + (message.direction == .send ? width - audioWidth : 0)
                audioView.frame = CGRect(x: x, y: y, width: audioWidth, height: height)
                audioView.refresh(durationText: "\(audio.duration)″", direction: message.direction,
                                  playing: Self.playingAudio == Self.audioKey(for: message, index: index))
            } else {
                view.frame = CGRect(x: Self.inset, y: y, width: width, height: height)
                if let file = body as? ChatFileMessageBody, let fileView = view as? FileMessageView {
                    fileView.refresh(name: file.compositeLabel, length: file.fileLength, direction: message.direction)
                    if message.direction == .receive {
                        fileView.content.textColor = segmentTextColor
                    }
                }
            }
            y += height + Self.spacing
        }
    }

    private func makeSegment(_ body: ChatMessageBody, direction: EMMessageDirection) -> UIView {
        if let image = body as? ChatImageMessageBody {
            let remote = [image.thumbnailRemotePath, image.remotePath].compactMap { $0 }.first { !$0.isEmpty }
            let view = thumbnail(paths: [image.resolvedThumbnailLocalPath, image.resolvedLocalPath], remote: remote,
                                 placeholder: Appearance.chat.imagePlaceHolder)
            view.accessibilityLabel = body.compositeLabel
            return view
        }
        let towards: BubbleTowards = direction == .receive ? .left : .right
        if let audio = body as? ChatAudioMessageBody {
            let view = AudioMessageView(frame: .zero, towards: towards)
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityLabel = "\(body.compositeLabel) \(audio.duration)″"
            return view
        }
        if body.type == .file {
            let view = FileMessageView(frame: .zero, towards: towards)
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityLabel = body.compositeLabel
            return view
        }
        if let video = body as? ChatVideoMessageBody {
            let view = thumbnail(paths: [video.thumbnailLocalPath], remote: video.thumbnailRemotePath,
                                 placeholder: Appearance.chat.videoPlaceHolder)
            let play = UIImageView(image: UIImage(chatNamed: "video_message_play"))
            play.translatesAutoresizingMaskIntoConstraints = false
            play.contentMode = .scaleAspectFit
            view.addSubview(play)
            NSLayoutConstraint.activate([
                play.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                play.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                play.widthAnchor.constraint(equalToConstant: 40),
                play.heightAnchor.constraint(equalToConstant: 40)
            ])
            view.accessibilityLabel = body.compositeLabel
            return view
        }
        let label = Self.makeLabel(body)
        if body is ChatFileMessageBody || body is ChatLocationMessageBody {
            label.accessibilityTraits.insert(.button)
        }
        return label
    }

    private func thumbnail(paths: [String?], remote: String?, placeholder: UIImage?) -> ImageView {
        let view = ImageView(frame: .zero)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 6
        view.isAccessibilityElement = true
        view.accessibilityTraits = [.image, .button]
        if let image = paths.lazy.compactMap({ $0.flatMap(UIImage.init(contentsOfFile:)) }).first {
            view.image = image
        } else {
            view.image(with: remote ?? "", placeHolder: placeholder)
        }
        return view
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard allowsOpening else { onSelection?(); return }
        guard let message,
              let index = segmentViews.firstIndex(where: { $0.frame.contains(gesture.location(in: self)) }),
              let body = message.bodies[safe: index] else { return }
        if let location = body as? ChatLocationMessageBody {
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = location.buildingName ?? location.address
            item.openInMaps()
        } else if let image = body as? ChatImageMessageBody, !image.isGif,
                  ComponentViewsActionHooker.shared.chat.compositeImageClicked?(message, index, (segmentViews[index] as? UIImageView)?.image) == true {
            return
        } else if body is ChatFileMessageBody {
            openAttachment(at: index, in: message)
        }
    }

    private func openAttachment(at index: Int, in message: ChatMessage) {
        if Self.playingAudio == Self.audioKey(for: message, index: index) {
            AudioTools.shared.stopPlaying()
            return
        }
        if let attachment = Self.cachedAttachment(at: index, in: [message]) {
            preview(attachment.body, path: attachment.path, at: index, in: message)
            return
        }
        let client = ChatClient.shared()
        guard let manager = client.chatManager,
              let presenter = UIViewController.currentController else { return }
        let messageID = message.messageId
        let latest = manager.getMessageWithMessageId(messageID).flatMap { $0.isCompositeMessage ? $0 : nil }
        let attachmentDirectory = manager.getMessageAttachmentPath(message.conversationId)
        if let attachment = Self.cachedAttachment(at: index, in: [latest, message].compactMap { $0 },
                                                  directory: attachmentDirectory) {
            preview(attachment.body, path: attachment.path, at: index, in: message)
            return
        }

        let downloadKey = DownloadKey(account: client.currentUsername, messageID: messageID)
        guard Self.activeDownloads.insert(downloadKey).inserted else { return }
        let request = latest ?? message
        do {
            for case let attachment as ChatFileMessageBody in request.bodies where Self.localPath(attachment) == nil {
                try MessageAttachmentFiles.prepareDownload(for: attachment)
            }
        } catch {
            Self.activeDownloads.remove(downloadKey)
            consoleLogInfo("Composite attachment download preparation failed for message \(messageID): \(error.localizedDescription)", type: .error)
            presenter.showToast(toast: "Unable to open attachment".chat.localize)
            return
        }
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.center = CGPoint(x: segmentViews[index].bounds.midX, y: segmentViews[index].bounds.midY)
        segmentViews[index].addSubview(indicator)
        indicator.startAnimating()
        // The SDK downloads attachments for the entire message in one request.
        manager.downloadMessageAttachment(request, progress: nil) { [weak self, weak presenter] updated, error in
            DispatchQueue.main.async {
                Self.activeDownloads.remove(downloadKey)
                indicator.removeFromSuperview()
                guard client.currentUsername == downloadKey.account, let self, self.message?.messageId == messageID,
                      self.window != nil, presenter === UIViewController.currentController else { return }
                let stored = manager.getMessageWithMessageId(messageID)
                let snapshots = [stored, updated, self.message, request].compactMap { $0 }
                if let attachment = Self.cachedAttachment(at: index, in: snapshots, directory: attachmentDirectory) {
                    self.preview(attachment.body, path: attachment.path, at: index, in: message)
                } else {
                    let reason = error?.errorDescription ?? "download finished without a readable local file"
                    consoleLogInfo("Composite attachment open failed for message \(messageID), body \(index): \(reason)", type: .error)
                    presenter?.showToast(toast: "Unable to open attachment".chat.localize)
                }
            }
        }
    }

    private static func localPath(_ body: ChatFileMessageBody, originalImageOnly: Bool = false) -> String? {
        let image = body as? ChatImageMessageBody
        let original = body.localPath
        let large = image?.bigImageLocalPath
        let paths: [String?]
        if originalImageOnly, let image {
            paths = image.isOriginalImage || original != large ? [original] : []
        } else {
            paths = [original, large]
        }
        for path in paths {
            guard let path = MessageAttachmentFiles.existingPathInCurrentContainer(path),
                  !path.isEmpty, MessageAttachmentFiles.isReadableFile(at: path) else { continue }
            return path
        }
        return nil
    }

    fileprivate static func cachedAttachment(at index: Int, in snapshots: [ChatMessage], directory: String? = nil,
                                             originalImageOnly: Bool = false) -> (body: ChatFileMessageBody, path: String)? {
        let bodies = snapshots.compactMap { $0.bodies[safe: index] as? ChatFileMessageBody }
        for body in bodies {
            if let path = localPath(body, originalImageOnly: originalImageOnly) { return (body, path) }
        }
        guard let directory, let body = bodies.first else { return nil }
        let remotePaths = [body.remotePath, (body as? ChatImageMessageBody)?.bigImageRemotePath]
        for remotePath in remotePaths {
            if let path = MessageAttachmentFiles.compositeDownloadPath(in: directory, bodyIndex: index,
                                                                      remotePath: remotePath, displayName: body.displayName) {
                return (body, path)
            }
        }
        return nil
    }

    private static func audioKey(for message: ChatMessage, index: Int) -> AudioKey {
        AudioKey(message: DownloadKey(account: ChatClient.shared().currentUsername, messageID: message.messageId), index: index)
    }

    private func preview(_ body: ChatFileMessageBody, path: String, at index: Int, in message: ChatMessage) {
        let url = URL(fileURLWithPath: path)
        if body is ChatAudioMessageBody {
            let playerURL: URL
            if !AudioTools.canPlay(url: url) {
                guard let data = try? Data(contentsOf: url),
                      let wave = convertAMRNBToWave(data: data) ?? convertAMRWBToWave(data: data) else {
                    UIViewController.currentController?.showToast(toast: "Unable to open attachment".chat.localize)
                    return
                }
                let converted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
                do {
                    try wave.write(to: converted, options: .atomic)
                } catch {
                    UIViewController.currentController?.showToast(toast: "Unable to open attachment".chat.localize)
                    return
                }
                playerURL = converted
            } else {
                playerURL = url
            }
            let key = Self.audioKey(for: message, index: index)
            let played = AudioTools.shared.playFile(at: playerURL.path) { [weak self] _ in
                if playerURL != url { try? FileManager.default.removeItem(at: playerURL) }
                if Self.playingAudio == key { Self.playingAudio = nil }
                self?.setNeedsLayout()
            }
            if played {
                Self.playingAudio = key
                setNeedsLayout()
            } else {
                if playerURL != url { try? FileManager.default.removeItem(at: playerURL) }
                UIViewController.currentController?.showToast(toast: "Unable to open attachment".chat.localize)
            }
        } else if body is ChatVideoMessageBody {
            AudioTools.shared.stopPlaying()
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: url)
            UIViewController.currentController?.present(controller, animated: true) { controller.player?.play() }
        } else if QLPreviewController.canPreview(url as NSURL) {
            ControllerStack.toDestination(vc: CompositeAttachmentPreview(url: url))
        } else {
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            UIViewController.currentController?.present(picker, animated: true)
        }
    }
}

private final class CompositeAttachmentPreview: QLPreviewController, QLPreviewControllerDataSource {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }

    required init?(coder: NSCoder) { nil }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
}
