import 'failures.dart';

sealed class Result<S, F extends Failure> {
  const Result();
  bool get isSuccess => this is Success<S, F>;
  bool get isFailure => this is FailureResult<S, F>;
  S? get data => this is Success<S, F> ? (this as Success<S, F>).value : null;
  F? get failure => this is FailureResult<S, F> ? (this as FailureResult<S, F>).error : null;
}

class Success<S, F extends Failure> extends Result<S, F> {
  final S value;
  const Success(this.value);
}

class FailureResult<S, F extends Failure> extends Result<S, F> {
  final F error;
  const FailureResult(this.error);
}
