/// Leitor de código de barras 1D/2D integrado do M10 Pro.
///
/// Um `Stream`, e não um `Future`: o leitor não é chamado, ele dispara. O
/// operador aperta o gatilho e o código chega — que é a diferença entre
/// "digitar o número" e "bipar a etiqueta".
///
/// A ordem importa: **assine [onScan] antes de chamar [start]**. É a assinatura
/// que registra o ouvinte da E1 no lado nativo; chamar `start()` sem ouvinte
/// dispara uma leitura que não tem para onde ir, e o plugin recusa com uma
/// mensagem dizendo isso.
library;

import 'package:flutter/services.dart';

import 'elgin_exception.dart';

class ElginScanner {
  const ElginScanner._();

  static const MethodChannel _channel = MethodChannel('elgin_m10/scanner');
  static const EventChannel _events = EventChannel('elgin_m10/scanner_events');

  /// Códigos lidos, na ordem em que chegam.
  ///
  /// O stream é convertido para `broadcast` porque mais de uma parte da tela
  /// pode querer ouvir — o campo da venda e um indicador de diagnóstico, por
  /// exemplo — e um stream de assinante único faria a segunda escuta falhar.
  static Stream<String> get onScan => _events
      .receiveBroadcastStream()
      .map((event) => event?.toString() ?? '')
      .where((code) => code.isNotEmpty)
      .handleError(
        (Object error) => throw ElginException.fromPlatform(error as PlatformException),
        test: (error) => error is PlatformException,
      );

  /// Liga o leitor.
  ///
  /// `continuous` mantém o leitor ativo entre disparos; `false` é leitura
  /// única, e exige nova chamada a cada bipe. A sobrecarga contínua só existe a
  /// partir do SDK 02.34.04.
  static Future<void> start({bool continuous = true}) =>
      invokeElgin<void>(_channel, 'scanner.start', {'continuous': continuous});

  static Future<void> stop() => invokeElgin<void>(_channel, 'scanner.stop');
}
