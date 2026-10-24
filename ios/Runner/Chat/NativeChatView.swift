import Flutter
import UIKit

/// Flutter 화면 안에 끼워 넣는 네이티브 채팅 목록 (PlatformView).
///
/// ## 뒤집힌 테이블
/// 테이블과 각 셀의 contentView 에 y축 반전(scaleY -1)을 걸어 row 0(최신)을 화면 맨 아래에 그린다.
/// - 이전 메시지는 배열 끝(= 콘텐츠 끝 = 화면 위)에 붙는다. 보고 있는 셀 위치가 안 바뀌니 스크롤이 튀지 않는다.
/// - 새 메시지는 row 0 에 붙는다. 맨 아래(contentOffset 최소)를 보고 있었다면 그대로 보인다.
///
/// 실서비스 버전은 앞쪽 삽입 후 reloadData() + scrollToRow(.top) 으로 위치를 맞췄는데,
/// 행 단위로만 복원돼서 보고 있던 행 안의 오프셋만큼 화면이 움직였다.
///
/// ## 채널
/// viewId 별 채널(`native_chat_view/<viewId>`).
final class NativeChatView: NSObject, FlutterPlatformView {
  private let tableView = UITableView(frame: .zero, style: .plain)
  private let channel: FlutterMethodChannel
  private let theme: ChatTheme

  /// 최신 → 오래된 순 (Dart 와 동일).
  private var items: [ChatRenderItem] = []
  /// 실제로 그려진 셀 높이. 추정 높이가 실제와 다르면 콘텐츠 크기가 출렁여 스크롤 위치가 흔들린다.
  private var heightCache: [String: CGFloat] = [:]

  private var hasMoreOlder: Bool
  private var loadingOlder = false
  private var lastOlderRequestAt: CFTimeInterval = 0
  private var atBottom = true
  private let olderLoader = UIActivityIndicatorView(style: .medium)

  private static let prefetchScreens: CGFloat = 0.5
  private static let olderRequestDebounce: CFTimeInterval = 1.0

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let params = args as? [String: Any] ?? [:]
    channel = FlutterMethodChannel(name: "native_chat_view/\(viewId)", binaryMessenger: messenger)
    theme = ChatTheme(wire: params["config"])
    hasMoreOlder = params["hasMoreOlder"] as? Bool ?? true
    items = ChatRenderItem.list(fromWire: params["initialItems"])
    super.init()

    setUpTable(frame: frame)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      self.handle(call, result: result)
    }
    DispatchQueue.main.async { [weak self] in self?.requestOlderIfViewportNotFilled() }
  }

  func view() -> UIView { tableView }

  private func setUpTable(frame: CGRect) {
    tableView.frame = frame
    tableView.transform = CGAffineTransform(scaleX: 1, y: -1)
    tableView.backgroundColor = theme.background
    tableView.separatorStyle = .none
    tableView.allowsSelection = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 56
    tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

    tableView.register(TextMessageCell.self, forCellReuseIdentifier: TextMessageCell.reuseId)
    tableView.register(ImageMessageCell.self, forCellReuseIdentifier: ImageMessageCell.reuseId)
    tableView.register(GiftMessageCell.self, forCellReuseIdentifier: GiftMessageCell.reuseId)
    tableView.register(CenterLabelCell.self, forCellReuseIdentifier: CenterLabelCell.reuseId)

    // 테이블 footer = 콘텐츠 끝 = 반전 후 화면 맨 위 → 이전 메시지 로딩 표시 자리
    let footer = UIView(frame: CGRect(x: 0, y: 0, width: frame.width, height: 0))
    olderLoader.transform = CGAffineTransform(scaleX: 1, y: -1)
    olderLoader.translatesAutoresizingMaskIntoConstraints = false
    footer.addSubview(olderLoader)
    NSLayoutConstraint.activate([
      olderLoader.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
      olderLoader.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
    ])
    footer.clipsToBounds = true
    tableView.tableFooterView = footer

    let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
    tap.cancelsTouchesInView = false
    tableView.addGestureRecognizer(tap)
  }

  // MARK: - Dart → Native

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "applyPatch":
      applyPatch(args)
      result(nil)

    case "setOlderState":
      loadingOlder = args["loading"] as? Bool ?? false
      hasMoreOlder = args["hasMore"] as? Bool ?? true
      setOlderLoaderVisible(loadingOlder && hasMoreOlder)
      if !loadingOlder {
        DispatchQueue.main.async { [weak self] in self?.requestOlderIfViewportNotFilled() }
      }
      result(nil)

    case "scrollToBottom":
      scrollToBottom(animated: args["animated"] as? Bool ?? true)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyPatch(_ args: [String: Any]) {
    let wasAtBottom = isAtBottom
    let stickToBottom = args["stickToBottom"] as? Bool ?? false
    let contentHeightBefore = tableView.contentSize.height
    let offsetBefore = tableView.contentOffset.y
    var insertedNewest = false

    switch args["type"] as? String {
    case "reset":
      items = ChatRenderItem.list(fromWire: args["items"])
      tableView.reloadData()

    case "ops":
      let ops = args["ops"] as? [[String: Any]] ?? []
      UIView.performWithoutAnimation {
        insertedNewest = applyOps(ops)
      }

    default:
      ChatViewLog.warn("unknown patch type")
    }

    if stickToBottom || (insertedNewest && wasAtBottom) {
      tableView.layoutIfNeeded()
      scrollToBottom(animated: !stickToBottom)
    } else if insertedNewest {
      // 위로 올려 읽는 중에 새 메시지가 row 0(콘텐츠 시작)에 들어오면 기존 행들이 전부 밀린다.
      // 늘어난 높이만큼 오프셋을 같이 옮겨서 보고 있던 화면을 고정한다.
      tableView.layoutIfNeeded()
      let delta = tableView.contentSize.height - contentHeightBefore
      tableView.contentOffset.y = offsetBefore + delta
    }
    notifyAtBottomIfChanged()
  }

  /// op 는 "앞선 op 적용 직후" 기준 index 이므로 하나씩 순서대로 적용한다.
  /// 연속된 update 는 한 번에 reconfigure 한다 (셀을 다시 만들지 않고 configure 만 다시 호출 — 깜빡임 없음).
  private func applyOps(_ ops: [[String: Any]]) -> Bool {
    var insertedNewest = false
    var pendingUpdates: [IndexPath] = []

    func flushUpdates() {
      guard !pendingUpdates.isEmpty else { return }
      let rows = pendingUpdates
      pendingUpdates.removeAll()
      tableView.performBatchUpdates { self.tableView.reconfigureRows(at: rows) }
    }

    for op in ops {
      guard let kind = op["op"] as? String, let index = (op["index"] as? NSNumber)?.intValue else { continue }
      switch kind {
      case "update":
        guard let item = ChatRenderItem(wire: op["item"]), index < items.count else { continue }
        items[index] = item
        pendingUpdates.append(IndexPath(row: index, section: 0))

      case "insert":
        flushUpdates()
        let newItems = ChatRenderItem.list(fromWire: op["items"])
        guard !newItems.isEmpty, index <= items.count else { continue }
        items.insert(contentsOf: newItems, at: index)
        let rows = (index..<(index + newItems.count)).map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates { self.tableView.insertRows(at: rows, with: .none) }
        if index == 0 { insertedNewest = true }

      case "remove":
        flushUpdates()
        let count = (op["count"] as? NSNumber)?.intValue ?? 0
        guard count > 0, index + count <= items.count else { continue }
        for removed in items[index..<(index + count)] { heightCache[removed.key] = nil }
        items.removeSubrange(index..<(index + count))
        let rows = (index..<(index + count)).map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates { self.tableView.deleteRows(at: rows, with: .none) }

      default:
        continue
      }
    }
    flushUpdates()
    return insertedNewest
  }

  // MARK: - Scroll

  /// 반전된 테이블에서 "화면 맨 아래" = contentOffset 최소값.
  private var isAtBottom: Bool {
    tableView.contentOffset.y <= -tableView.adjustedContentInset.top + 4
  }

  private func scrollToBottom(animated: Bool) {
    let y = -tableView.adjustedContentInset.top
    tableView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
  }

  private func setOlderLoaderVisible(_ visible: Bool) {
    guard let footer = tableView.tableFooterView else { return }
    let height: CGFloat = visible ? 44 : 0
    guard footer.frame.height != height else { return }
    footer.frame.size.height = height
    tableView.tableFooterView = footer // 높이 변경을 테이블에 반영하려면 다시 할당해야 한다
    if visible { olderLoader.startAnimating() } else { olderLoader.stopAnimating() }
  }

  private func requestOlderIfNearTop() {
    // 반전된 테이블에서 화면 맨 위 = 콘텐츠 끝
    let distanceToTop = tableView.contentSize.height - (tableView.contentOffset.y + tableView.bounds.height)
    if distanceToTop < tableView.bounds.height * Self.prefetchScreens {
      requestOlder()
    }
  }

  private func requestOlderIfViewportNotFilled() {
    // 아직 레이아웃 전(높이 0)이면 판단할 수 없다. setOlderState 를 받을 때 다시 확인한다.
    guard tableView.bounds.height > 0 else { return }
    if tableView.contentSize.height <= tableView.bounds.height { requestOlder() }
  }

  private func requestOlder() {
    guard hasMoreOlder, !loadingOlder else { return }
    let now = CACurrentMediaTime()
    guard now - lastOlderRequestAt > Self.olderRequestDebounce else { return }
    lastOlderRequestAt = now
    channel.invokeMethod("onLoadOlder", arguments: nil)
  }

  private func notifyAtBottomIfChanged() {
    let now = isAtBottom
    guard now != atBottom else { return }
    atBottom = now
    channel.invokeMethod("onAtBottomChanged", arguments: ["atBottom": now])
  }

  @objc private func backgroundTapped() {
    channel.invokeMethod("onTapBackground", arguments: nil)
  }

  private func send(_ method: String, key: String) {
    channel.invokeMethod(method, arguments: ["key": key])
  }
}

// MARK: - UITableViewDataSource / Delegate

extension NativeChatView: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let item = items[indexPath.row]

    switch item.kind {
    case .date, .notice:
      let cell = tableView.dequeueReusableCell(withIdentifier: CenterLabelCell.reuseId, for: indexPath) as! CenterLabelCell
      cell.configure(item)
      return cell

    case .text, .image, .gift:
      let reuseId: String
      switch item.kind {
      case .image: reuseId = ImageMessageCell.reuseId
      case .gift: reuseId = GiftMessageCell.reuseId
      default: reuseId = TextMessageCell.reuseId
      }
      let cell = tableView.dequeueReusableCell(withIdentifier: reuseId, for: indexPath) as! MessageCell
      cell.configure(item, theme: theme)

      // 클로저에는 index 가 아니라 key 를 담는다. index 는 이후 삽입/삭제로 바뀐다.
      let key = item.key
      cell.onTapAvatar = { [weak self] in self?.channel.invokeMethod("onTapAvatar", arguments: nil) }
      cell.onTapRetry = { [weak self] in self?.send("onTapRetry", key: key) }
      cell.onTapBubble = { [weak self] in
        guard let self, let current = self.items.first(where: { $0.key == key }) else { return }
        self.send(current.locked ? "onTapLocked" : "onTapMessage", key: key)
      }
      return cell
    }
  }

  func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
    let item = items[indexPath.row]
    if let cached = heightCache[item.key] { return cached }
    switch item.kind {
    case .text: return 44
    case .image: return 220
    case .gift: return 190
    case .notice, .date: return 40
    }
  }

  func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    guard indexPath.row < items.count else { return }
    heightCache[items[indexPath.row].key] = cell.bounds.height
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    notifyAtBottomIfChanged()
    guard scrollView.isDragging || scrollView.isDecelerating else { return }
    requestOlderIfNearTop()
  }
}

/// 이 파일 안에서만 쓰는 간단한 로그.
private enum ChatViewLog {
  static func warn(_ message: String) {
    NSLog("[NativeChatView] %@", message)
  }
}

// MARK: - Factory

final class NativeChatViewFactory: NSObject, FlutterPlatformViewFactory {
  /// Dart `NativeChatView.viewType` 과 같아야 한다.
  static let viewType = "native_chat_view"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    NativeChatView(frame: frame, viewId: viewId, args: args, messenger: messenger)
  }

  /// creationParams 를 [String: Any] 로 디코딩하려면 코덱을 지정해야 한다 (기본값은 nil → args 가 nil 로 온다).
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
