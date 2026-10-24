import 'package:logger/logger.dart';

final Logger _logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 6,
    printEmojis: false,
    noBoxingByDefault: true,
  ),
);

/// 태그 기반 로거. 통화 흐름은 네이티브 로그(Logcat/Console)와 함께 봐야 하는 경우가 많아서
/// 네이티브 쪽과 같은 태그 이름을 쓴다.
abstract final class Log {
  static void d(String tag, String message) => _logger.d('[$tag] $message');

  static void i(String tag, String message) => _logger.i('[$tag] $message');

  static void w(String tag, String message, [Object? error]) =>
      _logger.w('[$tag] $message', error: error);

  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _logger.e('[$tag] $message', error: error, stackTrace: stackTrace);
}
