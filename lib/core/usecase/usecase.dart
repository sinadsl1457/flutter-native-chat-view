import 'package:dartz/dartz.dart';

import '../error/failure.dart';

abstract interface class UseCase<In, Out> {
  Future<Either<Failure, Out>> call(In input);
}
