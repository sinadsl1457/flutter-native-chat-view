import UIKit

/// Dart `ChatRenderItem.toWire()` 와 1:1.
/// 묶음/시간/읽음 판단은 Dart 에서 끝난 값이다. 여기서는 그리기만 한다.
struct ChatRenderItem {
  enum Kind: String {
    case text, image, gift, notice, date
  }

  enum Status: String {
    case sending, sent, failed
  }

  let key: String
  let kind: Kind
  let isMine: Bool
  let groupStart: Bool
  let showAvatar: Bool
  let timeLabel: String?
  let status: Status
  let read: Bool
  let text: String?
  let imageUrl: String?
  let aspectRatio: Double?
  let locked: Bool
  let price: Int?
  let giftName: String?
  let giftAmount: Int?

  init?(wire: Any?) {
    guard let map = wire as? [String: Any],
          let key = map["key"] as? String,
          let kindRaw = map["kind"] as? String,
          let kind = Kind(rawValue: kindRaw)
    else { return nil }

    self.key = key
    self.kind = kind
    isMine = map["isMine"] as? Bool ?? false
    groupStart = map["groupStart"] as? Bool ?? false
    showAvatar = map["showAvatar"] as? Bool ?? false
    timeLabel = map["timeLabel"] as? String
    status = (map["status"] as? String).flatMap(Status.init(rawValue:)) ?? .sent
    read = map["read"] as? Bool ?? false
    text = map["text"] as? String
    imageUrl = map["imageUrl"] as? String
    aspectRatio = (map["aspectRatio"] as? NSNumber)?.doubleValue
    locked = map["locked"] as? Bool ?? false
    price = (map["price"] as? NSNumber)?.intValue
    giftName = map["giftName"] as? String
    giftAmount = (map["giftAmount"] as? NSNumber)?.intValue
  }

  static func list(fromWire raw: Any?) -> [ChatRenderItem] {
    (raw as? [Any] ?? []).compactMap(ChatRenderItem.init(wire:))
  }
}

/// Dart `NativeChatViewConfig.toWire()`
struct ChatTheme {
  let peerNickname: String
  let peerAvatarUrl: String?
  let fontSize: CGFloat
  let mineBubble: UIColor
  let peerBubble: UIColor
  let background: UIColor
  let readLabel: String
  let failedLabel: String

  init(wire: Any?) {
    let map = wire as? [String: Any] ?? [:]
    peerNickname = map["peerNickname"] as? String ?? ""
    peerAvatarUrl = map["peerAvatarUrl"] as? String
    fontSize = CGFloat((map["fontSize"] as? NSNumber)?.doubleValue ?? 15)
    mineBubble = UIColor(argb: map["mineBubbleColor"], fallback: 0xFFE6_007E)
    peerBubble = UIColor(argb: map["peerBubbleColor"], fallback: 0xFFFF_FFFF)
    background = UIColor(argb: map["backgroundColor"], fallback: 0xFFF1_F1F3)
    readLabel = map["readLabel"] as? String ?? "읽음"
    failedLabel = map["failedLabel"] as? String ?? "전송 실패"
  }
}

extension UIColor {
  /// Flutter `Color.toARGB32()` 값.
  convenience init(argb raw: Any?, fallback: UInt32) {
    let value = (raw as? NSNumber).map { UInt32(truncatingIfNeeded: $0.int64Value) } ?? fallback
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: CGFloat((value >> 24) & 0xFF) / 255
    )
  }

  /// 배경 밝기에 따라 읽기 좋은 글자색. 테마 색이 Flutter 에서 오기 때문에 고정할 수 없다.
  var readableTextColor: UIColor {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return luminance < 0.5 ? .white : UIColor(red: 0x1F / 255, green: 0x29 / 255, blue: 0x37 / 255, alpha: 1)
  }
}

extension Int {
  /// 1234 → "1,234P"
  var pointLabel: String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return (formatter.string(from: NSNumber(value: self)) ?? "\(self)") + "P"
  }
}
