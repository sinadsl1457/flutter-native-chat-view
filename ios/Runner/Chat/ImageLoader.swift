import UIKit

/// 셀 재사용을 고려한 최소한의 이미지 로더 (외부 의존성 없이).
///
/// - 메모리 캐시(NSCache) + URLSession 캐시
/// - 셀이 재사용되면 이전 요청을 취소하고, 늦게 도착한 이전 이미지가 덮어쓰지 않게 요청 키를 확인한다
/// - `thumbnailWidth` 를 주면 아주 작게 줄여서 돌려준다 → 잠긴 사진의 흐릿한 미리보기
final class ImageLoader {
  static let shared = ImageLoader()

  private let cache = NSCache<NSString, UIImage>()
  private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
    return URLSession(configuration: config)
  }()

  private init() {
    cache.countLimit = 200
  }

  /// 같은 이미지뷰에 같은 키로 다시 요청하면 아무것도 하지 않는다.
  /// (ack·읽음 변경으로 셀이 다시 configure 돼도 사진이 깜빡이지 않게)
  func load(_ urlString: String?, into imageView: UIImageView, thumbnailWidth: CGFloat? = nil) {
    let key = "\(urlString ?? "")|\(thumbnailWidth.map { "\($0)" } ?? "full")"
    if imageView.loaderKey == key { return }
    imageView.loaderKey = key
    imageView.loaderTask?.cancel()
    imageView.loaderTask = nil

    guard let urlString, let url = URL(string: urlString) else {
      imageView.image = nil
      return
    }
    if let cached = cache.object(forKey: key as NSString) {
      imageView.image = cached
      return
    }

    imageView.image = nil
    let task = session.dataTask(with: url) { [weak self, weak imageView] data, _, _ in
      guard let self, let data, var image = UIImage(data: data) else { return }
      if let thumbnailWidth { image = image.resized(toWidth: thumbnailWidth) }
      self.cache.setObject(image, forKey: key as NSString)

      DispatchQueue.main.async {
        // 그 사이 셀이 다른 메시지로 재사용됐으면 버린다.
        guard let imageView, imageView.loaderKey == key else { return }
        imageView.image = image
      }
    }
    imageView.loaderTask = task
    task.resume()
  }
}

private var loaderKeyHandle: UInt8 = 0
private var loaderTaskHandle: UInt8 = 0

private extension UIImageView {
  var loaderKey: String? {
    get { objc_getAssociatedObject(self, &loaderKeyHandle) as? String }
    set { objc_setAssociatedObject(self, &loaderKeyHandle, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
  }

  var loaderTask: URLSessionDataTask? {
    get { objc_getAssociatedObject(self, &loaderTaskHandle) as? URLSessionDataTask }
    set { objc_setAssociatedObject(self, &loaderTaskHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }
}

private extension UIImage {
  func resized(toWidth width: CGFloat) -> UIImage {
    guard size.width > width else { return self }
    let target = CGSize(width: width, height: size.height * width / size.width)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
