import UIKit

final class CompositeMessageCell: MessageCell {
    private let segments = CompositeMessageContentView(frame: .zero)
    @objc var content: UIView { segments }

    required init(towards: BubbleTowards, reuseIdentifier: String) {
        super.init(towards: towards, reuseIdentifier: reuseIdentifier)
        let bubble = Appearance.chat.bubbleStyle == .withArrow ? bubbleWithArrow.bubble : bubbleMultiCorners
        bubble.addSubview(segments)
        segments.onSelection = { [weak self] in
            guard let self else { return }
            self.clickAction?(.bubble, self.entity)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func refresh(entity: MessageEntity) {
        super.refresh(entity: entity)
        segments.allowsOpening = !editMode
        segments.frame = CGRect(origin: .zero, size: entity.bubbleSize)
        segments.bind(entity.message)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        segments.bind(nil)
    }

    override func switchTheme(style: ThemeStyle) {
        super.switchTheme(style: style)
        segments.updateColors()
    }
}
