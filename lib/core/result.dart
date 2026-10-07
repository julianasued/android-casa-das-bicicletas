/// Resultado de uma operação que pode falhar.
///
/// O aplicativo roda em balcão, com rede instável por definição (RNF06): quase
/// toda chamada tem um caminho de erro que a tela precisa mostrar. Exceção
/// serve para o que não se previu; falha de rede, senha errada e impressora sem
/// papel são previstos, e por isso viajam no valor de retorno — o compilador
/// cobra o tratamento, o `try/catch` esquecido não.
library;

import 'failure.dart';

sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.failed(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isFailure => this is Err<T>;

  /// Valor quando deu certo, `null` quando não — para quem só quer exibir algo.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final failure) => Err<R>(failure),
      };

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onFailure) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onFailure(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  String toString() => 'Err(${failure.message})';
}
