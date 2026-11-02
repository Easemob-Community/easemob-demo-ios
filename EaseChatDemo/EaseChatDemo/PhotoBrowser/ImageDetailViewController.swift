//
//  ImageDetailViewController.swift
//  EaseChatDemo
//

import UIKit
import EaseChatUIKit
import Photos

/// Full-screen viewer for an image message.
///
/// It displays the large image first and offers a button to switch to the original
/// image (downloading it when it is not cached locally). Long-pressing the image
/// shows the save / forward menu.
final class ImageDetailViewController: UIViewController {

    private var message: ChatMessage
    private let thumbnail: UIImage?

    private var largeImage: UIImage?
    private var originalImage: UIImage?
    private var showingOriginal = false
    private var isDownloadingLargeImage = false
    private var isDownloadingOriginalImage = false

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let originalButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let progressLabel = UILabel()

    private var imageBody: ChatImageMessageBody? {
        message.body as? ChatImageMessageBody
    }

    init(message: ChatMessage, thumbnail: UIImage? = nil) {
        self.message = message
        self.thumbnail = thumbnail
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
        self.modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        self.setupSubviews()
        self.loadInitialImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        scrollView.frame = view.bounds
        if scrollView.zoomScale == 1 {
            contentView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
        imageView.frame = contentView.bounds

        let top = view.safeAreaInsets.top + 8
        closeButton.frame = CGRect(x: 12, y: top, width: 40, height: 40)

        let maxWidth = view.bounds.width - 40
        let fitting = originalButton.sizeThatFits(CGSize(width: maxWidth, height: 44))
        let width = min(max(fitting.width, 100), maxWidth)
        let height = max(fitting.height, 36)
        let bottom = view.safeAreaInsets.bottom + 24
        originalButton.frame = CGRect(x: (view.bounds.width - width) / 2,
                                      y: view.bounds.height - bottom - height,
                                      width: width,
                                      height: height)
        originalButton.layer.cornerRadius = height / 2

        loadingIndicator.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        progressLabel.frame = CGRect(x: view.bounds.midX - 60,
                                     y: loadingIndicator.frame.maxY + 8,
                                     width: 120,
                                     height: 20)
    }

    private func setupSubviews() {
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 3
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        contentView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        contentView.addGestureRecognizer(singleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        contentView.addGestureRecognizer(longPress)

//        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
//        closeButton.tintColor = .white
//        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
//        closeButton.layer.cornerRadius = 20
//        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
//        view.addSubview(closeButton)

        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.background.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        configuration.title = "View Original Image".localized()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            return outgoing
        }
        originalButton.configuration = configuration
        originalButton.clipsToBounds = true
        originalButton.isHidden = true
        originalButton.addTarget(self, action: #selector(originalButtonTapped), for: .touchUpInside)
        view.addSubview(originalButton)

        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        progressLabel.textColor = .white
        progressLabel.font = UIFont.systemFont(ofSize: 13)
        progressLabel.textAlignment = .center
        progressLabel.isHidden = true
        view.addSubview(progressLabel)
    }

    // MARK: - Local files

    /// 大图 file, if it is on disk. 消息里存的是绝对路径，重装后容器 UUID 会变，
    /// 所以先按当前容器重定位再判断。
    private var largeImageFile: String? { existingPath(pathInCurrentContainer(imageBody?.bigImageLocalPath)) }

    /// 原图 file, if it is on disk.
    private var originalImageFile: String? { existingPath(pathInCurrentContainer(imageBody?.localPath)) }

    private func existingPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func image(at path: String?) -> UIImage? {
        guard let path else { return nil }
        return UIImage(contentsOfFile: path)
    }

    // MARK: - Image loading

    /// 有大图就直接展示，没有就下载大图；原图要等用户点按钮才处理。
    private func loadInitialImage() {
        if let image = image(at: largeImageFile) {
            show(image, original: false)
        } else {
            showThumbnail()
            downloadLargeImage()
        }
    }

    private func show(_ image: UIImage, original: Bool) {
        if original {
            originalImage = image
        } else {
            largeImage = image
        }
        showingOriginal = original
        display(image)
        updateOriginalButton()
    }

    private func showThumbnail() {
        if let body = imageBody,
           let path = body.resolvedThumbnailLocalPath,
           FileManager.default.fileExists(atPath: path),
           let image = UIImage(contentsOfFile: path) {
            imageView.image = image
        } else if let thumbnail {
            imageView.image = thumbnail
        }
    }

    /// Downloads the 大图 unless it turned up on disk in the meantime.
    private func downloadLargeImage() {
        guard !isDownloadingLargeImage, imageBody != nil else { return }
        if let image = image(at: largeImageFile) {
            show(image, original: false)
            return
        }
        isDownloadingLargeImage = true
        originalButton.isEnabled = false
        setLoading(true, progress: -1)

        guard prepareDownload() else {
            isDownloadingLargeImage = false
            setLoading(false, progress: -1)
            showToast(toast: "Failed to load image.".localized())
            updateOriginalButton()
            return
        }
        ChatClient.shared().chatManager?.downloadBigImageAttachment(message, progress: { [weak self] progress in
            DispatchQueue.main.async {
                guard let self, self.isDownloadingLargeImage else { return }
                self.setLoading(true, progress: Int(progress))
            }
        }, completion: { [weak self] attachMessage, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isDownloadingLargeImage = false
                self.setLoading(false, progress: -1)

                if let attachMessage {
                    self.message = attachMessage
                }
                if let image = self.image(at: self.largeImageFile) {
                    self.show(image, original: false)
                } else if let image = self.image(at: self.originalImageFile) {
                    self.show(image, original: true)
                } else {
                    // 大图没拿到时退回附件下载，至少保证页面能出图。
                    self.downloadOriginalImage()
                }
            }
        })
    }

    /// Downloads the 原图 unless it is already on disk.
    private func downloadOriginalImage() {
        guard !isDownloadingOriginalImage, imageBody != nil else { return }
        if let image = image(at: originalImageFile) {
            show(image, original: true)
            return
        }

        isDownloadingOriginalImage = true
        originalButton.isEnabled = false
        updateOriginalDownloadProgress(-1)

        guard prepareDownload() else {
            isDownloadingOriginalImage = false
            originalButton.isEnabled = true
            setLoading(false, progress: -1)
            updateOriginalButton()
            showToast(toast: "Failed to load the original image.".localized())
            return
        }

        ChatClient.shared().chatManager?.downloadMessageAttachment(message, progress: { [weak self] progress in
            DispatchQueue.main.async {
                guard let self, self.isDownloadingOriginalImage else { return }
                self.updateOriginalDownloadProgress(Int(progress))
            }
        }, completion: { [weak self] attachMessage, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isDownloadingOriginalImage = false
                self.originalButton.isEnabled = true
                self.setLoading(false, progress: -1)

                if let attachMessage {
                    self.message = attachMessage
                }
                if let image = self.image(at: self.originalImageFile) {
                    self.show(image, original: true)
                } else {
                    self.showToast(toast: "Failed to load the original image.".localized())
                    self.updateOriginalButton()
                }
            }
        })
    }

    /// Progress goes to the button when it is on screen, otherwise to the centred indicator
    /// (first load runs before `updateOriginalButton()` has shown the button).
    private func updateOriginalDownloadProgress(_ progress: Int) {
        if originalButton.isHidden {
            setLoading(true, progress: progress)
        } else if progress < 0 {
            setOriginalButtonTitle("Loading...".chat.localize)
        } else {
            setOriginalButtonTitle("\("Loading...".chat.localize) \(progress)%")
        }
    }

    /// Downloads are written straight to the paths the message records, so move paths left
    /// behind by a previous installation into the current container and create their folders.
    private func prepareDownload() -> Bool {
        guard let body = imageBody else { return false }
        body.localPath = pathInCurrentContainer(body.localPath)
        body.bigImageLocalPath = pathInCurrentContainer(body.bigImageLocalPath)

        for path in [body.localPath, body.bigImageLocalPath] {
            guard let path, !path.isEmpty else { continue }
            let directory = (path as NSString).deletingLastPathComponent
            guard directory.hasPrefix(NSHomeDirectory()) else {
                consoleLogInfo("Attachment path is outside the current app container: \(path)", type: .error)
                return false
            }
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        return true
    }

    /// A reinstall relocates the app to a new data container, leaving cached paths pointing at
    /// a folder that no longer exists.
    private func pathInCurrentContainer(_ path: String?) -> String? {
        guard let path, !path.isEmpty,
              let marker = path.range(of: "/Containers/Data/Application/", options: .backwards) else { return path }
        let components = path[marker.upperBound...].split(separator: "/")
        guard components.count >= 3 else { return path }
        // Drop the old container's UUID and keep `Library/...` under the current home.
        return components.dropFirst().reduce(NSHomeDirectory()) {
            ($0 as NSString).appendingPathComponent(String($1))
        }
    }


    private func display(_ image: UIImage) {
        UIView.transition(with: imageView, duration: 0.2, options: .transitionCrossDissolve) {
            self.imageView.image = image
        }
        scrollView.setZoomScale(1, animated: false)
        if !scrollView.bounds.isEmpty {
            contentView.frame = scrollView.bounds
            imageView.frame = contentView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
        centerScrollContent()
    }

    // MARK: - Original image button

    private func updateOriginalButton() {

        originalButton.isHidden = false
        originalButton.isEnabled = !isDownloadingOriginalImage
        setOriginalButtonTitle(showingOriginal ? "Show Large Image".localized() : "View Original Image".localized())
    }

    private func setOriginalButtonTitle(_ title: String) {
        guard var configuration = originalButton.configuration else {
            originalButton.setTitle(title, for: .normal)
            return
        }
        configuration.title = title
        originalButton.configuration = configuration
        view.setNeedsLayout()
    }

    @objc private func originalButtonTapped() {
        if showingOriginal {
            showLargeImage()
        } else {
            showOriginalImage()
        }
    }

    /// Each version is downloaded only when it is not on disk; nothing else is fetched.
    private func showLargeImage() {
        if let image = largeImage ?? image(at: largeImageFile) {
            show(image, original: false)
        } else {
            downloadLargeImage()
        }
    }

    private func showOriginalImage() {
        if let image = originalImage ?? image(at: originalImageFile) {
            show(image, original: true)
        } else {
            downloadOriginalImage()
        }
    }

    // MARK: - Loading indicator

    private func setLoading(_ loading: Bool, progress: Int) {
        if loading {
            loadingIndicator.startAnimating()
            progressLabel.text = progress >= 0 ? "\(progress)%" : ""
            progressLabel.isHidden = progress < 0
        } else {
            loadingIndicator.stopAnimating()
            progressLabel.isHidden = true
            progressLabel.text = nil
        }
    }

    // MARK: - Gestures

    private func centerScrollContent() {
        let horizontal = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let vertical = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func handleSingleTap() {
        dismiss(animated: true)
    }

    @objc private func handleDoubleTap() {
        let scale = scrollView.zoomScale > 1 ? 1 : 2.5
        scrollView.setZoomScale(scale, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, bestAvailableImage() != nil else { return }
        DialogManager.shared.showActions(actions: [
            ActionSheetItem(title: "Save Image".localized(), type: .normal, tag: "SaveImage", image: UIImage(named: "photo", in: .chatBundle, with: nil)),
            ActionSheetItem(title: "barrage_long_press_menu_forward".chat.localize, type: .normal, tag: "Forward", image: UIImage(named: "message_action_forward", in: .chatBundle, with: nil))
        ]) { [weak self] item in
            guard let self else { return }
            switch item.tag {
            case "SaveImage":
                self.saveImageToAlbum()
            case "Forward":
                self.forwardMessage()
            default:
                break
            }
        }
    }

    // MARK: - Save & forward

    private func bestAvailableImage() -> UIImage? {
        originalImage ?? largeImage ?? image(at: originalImageFile) ?? image(at: largeImageFile)
            ?? imageView.image ?? thumbnail
    }

    private func saveImageToAlbum() {
        guard let image = bestAvailableImage() else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            writeToAlbum(image)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        self?.writeToAlbum(image)
                    } else {
                        self?.showToast(toast: "Failed to save image.".localized())
                    }
                }
            }
        default:
            showToast(toast: "Failed to save image.".localized())
        }
    }

    private func writeToAlbum(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.showToast(toast: success ? "Successful to save image.".localized() : "Failed to save image.".localized())
            }
        }
    }

    private func forwardMessage() {
        let controller = ForwardTargetViewController(messages: [message], combine: false)
        present(controller, animated: true)
    }
}

extension ImageDetailViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerScrollContent()
    }
}
