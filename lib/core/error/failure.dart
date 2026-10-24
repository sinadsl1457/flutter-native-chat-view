sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.code});

  /// 예: `INSUFFICIENT_POINTS` — 잠긴 사진 구매 시 포인트 부족.
  final String? code;
}
