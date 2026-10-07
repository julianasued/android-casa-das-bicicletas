/// Falhas da ponte com o SDK E1.
///
/// A convenção do SDK é `0` para sucesso e negativo para erro. Esse inteiro
/// **não** sobe para a interface: vira esta exceção, com o código preservado
/// para diagnóstico e uma mensagem que alguém consegue ler. Devolver o número
/// cru obrigaria cada tela a conhecer a tabela do fabricante.
library;

import 'package:flutter/services.dart';

/// Motivo da falha, na granularidade que muda a conduta de quem chamou.
enum ElginFailureKind {
  /// Nenhuma `Activity` anexada — as APIs da E1 exigem uma.
  noActivity,

  /// O SDK recusou a operação e devolveu um código.
  sdkError,

  /// As classes da E1 não estão no APK (emulador, build sem os AARs).
  sdkMissing,

  /// Argumento inválido antes de chegar ao SDK.
  invalidArgument,

  /// O que não se previu.
  unexpected,
}

class ElginException implements Exception {
  const ElginException({
    required this.kind,
    required this.message,
    this.code,
    this.operation,
  });

  /// Reconstrói a exceção a partir do erro do canal.
  factory ElginException.fromPlatform(PlatformException error) {
    final details = error.details;
    final data = details is Map ? details : const <Object?, Object?>{};

    return ElginException(
      kind: _kindOf(error.code),
      message: error.message ?? 'Falha na comunicação com o hardware.',
      code: data['code'] as int?,
      operation: data['operation'] as String?,
    );
  }

  final ElginFailureKind kind;
  final String message;

  /// Código devolvido pela E1, quando houve um.
  final int? code;

  /// Função da E1 que falhou (`ImpressaoTexto`, `AbreConexaoDisplay`, ...).
  final String? operation;

  /// O hardware está ausente, e não com defeito — muda o que dizer ao operador.
  bool get isUnavailable =>
      kind == ElginFailureKind.sdkMissing || kind == ElginFailureKind.noActivity;

  static ElginFailureKind _kindOf(String code) => switch (code) {
        'NO_ACTIVITY' => ElginFailureKind.noActivity,
        'ELGIN_SDK_ERROR' => ElginFailureKind.sdkError,
        'SDK_MISSING' => ElginFailureKind.sdkMissing,
        'INVALID_ARGUMENT' => ElginFailureKind.invalidArgument,
        _ => ElginFailureKind.unexpected,
      };

  @override
  String toString() {
    final parts = <String>[
      if (operation != null) operation!,
      message,
      if (code != null) 'código $code',
    ];
    return 'ElginException(${parts.join(' · ')})';
  }
}

/// Chama o canal traduzindo qualquer falha em [ElginException].
///
/// Existe para que nenhuma tela precise capturar `PlatformException`: a ponte
/// tem um tipo de erro só, e ele é do domínio do hardware.
Future<T?> invokeElgin<T>(
  MethodChannel channel,
  String method, [
  Map<String, Object?>? arguments,
]) async {
  try {
    return await channel.invokeMethod<T>(method, arguments);
  } on PlatformException catch (error) {
    throw ElginException.fromPlatform(error);
  } on MissingPluginException {
    throw const ElginException(
      kind: ElginFailureKind.sdkMissing,
      message: 'Plugin elgin_m10 não registrado neste aparelho.',
    );
  }
}
