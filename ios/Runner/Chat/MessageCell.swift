import UIKit

/// 말풍선 메시지 셀 공통 틀: [프로필] [닉네임 / (메타) 말풍선 (메타)]
///
/// 뷰 트리는 init 에서 한 번만 만든다. configure 에서는 제약 조건 묶음(내 메시지/상대 메시지)을
/// 바꿔 끼우고 값만 갱신한다. (실서비스 버전은 configure 마다 subviews 를 전부 지우고 새로 만들었다)
///
/// 테이블이 y축으로 뒤집혀 있으므로 contentView 도 같은 변환을 걸어 다시 바로 세운다.
class MessageCell: UITableViewCell {
  var onTapBubble: (() -> Void)?
  var onTapRetry: (() -> Void)?
  var onTapAvatar: (() -> Void)?

  /// 하위 클래스가 내용을 채우는 말풍선 영역.
  let bubble = UIView()

  private let avatarView = UIImageView()
  private let nicknameLabel = UILabel()
  private let metaStack = UIStackView()
  private let sendingIndicator = UIActivityIndicatorView(style: .medium)
  private let retryButton = UIButton(type: .system)
  private let readLabel = UILabel()
  private let timeLabel = UILabel()

  private var mineConstraints: [NSLayoutConstraint] = []
  private var peerConstraints: [NSLayoutConstraint] = []
  private var bubbleTopToNickname: NSLayoutConstraint!
  private var bubbleTopToContent: NSLayoutConstraint!
  private var avatarTop: NSLayoutConstraint!
  private var avatarBottom: NSLayoutConstraint!

  private static let avatarSize: CGFloat = 36
  private static let sidePadding: CGFloat = 12

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
    buildLayout()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ item: ChatRenderItem, theme: ChatTheme) {
    let mine = item.isMine
    let showAvatar = item.showAvatar && !mine

    NSLayoutConstraint.deactivate(mine ? peerConstraints : mineConstraints)
    NSLayoutConstraint.activate(mine ? mineConstraints : peerConstraints)

    let top: CGFloat = item.groupStart ? 10 : 2
    avatarTop.constant = top
    bubbleTopToContent.constant = top
    // 끄는 쪽을 먼저 비활성화해야 잠깐이라도 두 제약이 동시에 걸리지 않는다.
    if showAvatar {
      bubbleTopToContent.isActive = false
      bubbleTopToNickname.isActive = true
    } else {
      bubbleTopToNickname.isActive = false
      bubbleTopToContent.isActive = true
    }
    avatarBottom.isActive = showAvatar

    avatarView.isHidden = !showAvatar
    nicknameLabel.isHidden = !showAvatar
    nicknameLabel.text = theme.peerNickname
    if showAvatar {
      ImageLoader.shared.load(theme.peerAvatarUrl, into: avatarView)
    }

    let sent = item.status == .sent
    if item.status == .sending { sendingIndicator.startAnimating() } else { sendingIndicator.stopAnimating() }
    sendingIndicator.isHidden = item.status != .sending
    retryButton.isHidden = item.status != .failed
    readLabel.text = theme.readLabel
    readLabel.textColor = theme.mineBubble
    readLabel.isHidden = !(sent && item.read)
    timeLabel.text = item.timeLabel
    timeLabel.isHidden = !(sent && item.timeLabel != nil)
    metaStack.alignment = mine ? .trailing : .leading
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    onTapBubble = nil
    onTapRetry = nil
    onTapAvatar = nil
  }

  // MARK: - Layout

  private func buildLayout() {
    avatarView.contentMode = .scaleAspectFill
    avatarView.clipsToBounds = true
    avatarView.layer.cornerRadius = Self.avatarSize / 2
    avatarView.backgroundColor = UIColor(white: 0.9, alpha: 1)
    avatarView.isUserInteractionEnabled = true
    avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))

    nicknameLabel.font = .systemFont(ofSize: 12)
    nicknameLabel.textColor = UIColor(white: 0.2, alpha: 1)

    bubble.layer.cornerRadius = 14
    bubble.clipsToBounds = true
    bubble.isUserInteractionEnabled = true
    bubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bubbleTapped)))

    readLabel.font = .systemFont(ofSize: 11)
    timeLabel.font = .systemFont(ofSize: 10)
    timeLabel.textColor = UIColor(white: 0.55, alpha: 1)
    retryButton.setImage(UIImage(systemName: "exclamationmark.circle.fill"), for: .normal)
    retryButton.tintColor = .systemRed
    retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
    sendingIndicator.hidesWhenStopped = false

    metaStack.axis = .vertical
    metaStack.spacing = 2
    for view in [sendingIndicator, retryButton, readLabel, timeLabel] as [UIView] {
      metaStack.addArrangedSubview(view)
    }
    timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    readLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    for view in [avatarView, nicknameLabel, bubble, metaStack] as [UIView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(view)
    }

    let side = Self.sidePadding
    avatarTop = avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
    bubbleTopToNickname = bubble.topAnchor.constraint(equalTo: nicknameLabel.bottomAnchor, constant: 4)
    bubbleTopToContent = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2)

    // 셀 높이를 말풍선이 결정한다. 마지막 제약은 우선순위를 조금 낮춰 초기 측정(높이 44) 시
    // 제약 충돌 로그가 나지 않게 한다.
    let bubbleBottom = bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2)
    bubbleBottom.priority = .init(999)

    NSLayoutConstraint.activate([
      avatarTop,
      avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: side),
      avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
      avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSize),

      nicknameLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
      nicknameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8),

      bubbleTopToContent,
      bubbleBottom,
      bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.68),

      metaStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
    ])
    // 프로필이 보이는 셀만 프로필 높이만큼은 확보한다.
    avatarBottom = contentView.bottomAnchor.constraint(greaterThanOrEqualTo: avatarView.bottomAnchor, constant: 2)

    peerConstraints = [
      bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: side + Self.avatarSize + 8),
      metaStack.leadingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 6),
    ]
    mineConstraints = [
      bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -side),
      metaStack.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6),
    ]
    NSLayoutConstraint.activate(peerConstraints)
  }

  @objc private func bubbleTapped() { onTapBubble?() }
  @objc private func retryTapped() { onTapRetry?() }
  @objc private func avatarTapped() { onTapAvatar?() }
}

// MARK: - Content cells

final class TextMessageCell: MessageCell {
  static let reuseId = "TextMessageCell"
  private let label = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    bubble.addSubview(label)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
      label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func configure(_ item: ChatRenderItem, theme: ChatTheme) {
    super.configure(item, theme: theme)
    let color = item.isMine ? theme.mineBubble : theme.peerBubble
    bubble.backgroundColor = color
    label.textColor = color.readableTextColor
    label.font = .systemFont(ofSize: theme.fontSize)
    label.text = item.text
  }
}

final class ImageMessageCell: MessageCell {
  static let reuseId = "ImageMessageCell"
  private static let width: CGFloat = 200

  private let photoView = UIImageView()
  private let lockDim = UIView()
  private let lockLabel = UILabel()
  private var ratioConstraint: NSLayoutConstraint?
  private var currentRatio: CGFloat = 0

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    bubble.backgroundColor = UIColor(white: 0.9, alpha: 1)
    photoView.contentMode = .scaleAspectFill
    photoView.clipsToBounds = true
    lockDim.backgroundColor = UIColor.black.withAlphaComponent(0.6)
    lockLabel.textColor = .white
    lockLabel.font = .boldSystemFont(ofSize: 13)
    lockLabel.textAlignment = .center
    lockLabel.numberOfLines = 2

    for view in [photoView, lockDim, lockLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      bubble.addSubview(view)
    }
    NSLayoutConstraint.activate([
      bubble.widthAnchor.constraint(equalToConstant: Self.width),
      photoView.topAnchor.constraint(equalTo: bubble.topAnchor),
      photoView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
      photoView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
      photoView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
      lockDim.topAnchor.constraint(equalTo: bubble.topAnchor),
      lockDim.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
      lockDim.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
      lockDim.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
      lockLabel.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
      lockLabel.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func configure(_ item: ChatRenderItem, theme: ChatTheme) {
    super.configure(item, theme: theme)

    // 비율에 맞춘 높이를 configure 시점에 확정한다. 이미지 로딩 후에 높이가 바뀌면 셀 높이가 변해 스크롤이 튄다.
    let ratio = CGFloat(min(max(item.aspectRatio ?? 1, 0.6), 1.8))
    if ratio != currentRatio {
      ratioConstraint?.isActive = false
      ratioConstraint = bubble.heightAnchor.constraint(equalToConstant: Self.width / ratio)
      ratioConstraint?.isActive = true
      currentRatio = ratio
    }

    lockDim.isHidden = !item.locked
    lockLabel.isHidden = !item.locked
    lockLabel.attributedText = Self.lockText(price: item.price)

    // 잠긴 사진은 아주 작게 받아서 늘려 그린다 → 흐릿한 미리보기.
    // 실서비스라면 서버가 처음부터 미리보기용 URL 만 내려줘야 한다 (README 참고).
    ImageLoader.shared.load(item.imageUrl, into: photoView, thumbnailWidth: item.locked ? 24 : nil)
  }
}

extension ImageMessageCell {
  /// 자물쇠 아이콘 + 가격 (두 줄)
  static func lockText(price: Int?) -> NSAttributedString {
    let text = NSMutableAttributedString()
    if let icon = UIImage(systemName: "lock.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
      text.append(NSAttributedString(attachment: NSTextAttachment(image: icon)))
      text.append(NSAttributedString(string: "\n"))
    }
    text.append(NSAttributedString(string: price?.pointLabel ?? ""))
    return text
  }
}

final class GiftMessageCell: MessageCell {
  static let reuseId = "GiftMessageCell"

  private let giftImage = UIImageView()
  private let nameLabel = UILabel()
  private let amountLabel = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    giftImage.contentMode = .scaleAspectFill
    giftImage.clipsToBounds = true
    giftImage.layer.cornerRadius = 8
    nameLabel.font = .boldSystemFont(ofSize: 14)
    amountLabel.font = .systemFont(ofSize: 12)

    let stack = UIStackView(arrangedSubviews: [giftImage, nameLabel, amountLabel])
    stack.axis = .vertical
    stack.spacing = 4
    stack.setCustomSpacing(8, after: giftImage)
    stack.translatesAutoresizingMaskIntoConstraints = false
    bubble.addSubview(stack)
    NSLayoutConstraint.activate([
      bubble.widthAnchor.constraint(equalToConstant: 180),
      giftImage.heightAnchor.constraint(equalToConstant: 100),
      stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
      stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func configure(_ item: ChatRenderItem, theme: ChatTheme) {
    super.configure(item, theme: theme)
    let color = item.isMine ? theme.mineBubble : theme.peerBubble
    bubble.backgroundColor = color
    nameLabel.textColor = color.readableTextColor
    amountLabel.textColor = color.readableTextColor.withAlphaComponent(0.7)
    nameLabel.text = item.giftName
    amountLabel.text = item.giftAmount?.pointLabel
    ImageLoader.shared.load(item.imageUrl, into: giftImage)
  }
}

/// 날짜 구분선 / 공지.
final class CenterLabelCell: UITableViewCell {
  static let reuseId = "CenterLabelCell"
  private let pill = UIView()
  private let label = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.transform = CGAffineTransform(scaleX: 1, y: -1)

    pill.backgroundColor = UIColor.black.withAlphaComponent(0.08)
    pill.layer.cornerRadius = 12
    label.font = .systemFont(ofSize: 12)
    label.numberOfLines = 0
    label.textAlignment = .center

    pill.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(pill)
    pill.addSubview(label)

    let bottom = pill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
    bottom.priority = .init(999)
    NSLayoutConstraint.activate([
      pill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
      bottom,
      pill.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      pill.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -48),
      label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
      label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
      label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ item: ChatRenderItem) {
    label.text = item.text
    label.textColor = item.kind == .notice ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.5, alpha: 1)
  }
}
