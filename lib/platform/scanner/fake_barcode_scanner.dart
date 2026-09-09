/// Leitor de mentira, para rodar o aplicativo e o POC fora do M10.
///
/// Mora em `lib/`, e não em `test/`, de propósito: sem hardware — em emulador,
/// na máquina de quem desenvolve, ou num M10 cujo leitor ainda não foi
/// configurado — a tela precisa de uma origem de leituras para ser exercitada.
/// Trocar `ScannerChannel` por este é uma linha em `AppDependencies`.
library;

import 'dart:async';

import '../../core/result.dart';
import '../../domain/entities/barcode_read.dart';
import '../../domain/ports/barcode_scanner.dart';

class FakeBarcodeScanner implements BarcodeScanner {
  FakeBarcodeScanner({this.available = true});

  final StreamController<BarcodeRead> _controller =
      StreamController<BarcodeRead>.broadcast();

  bool available;
  bool started = false;

  /// Dispara uma leitura, como se o gatilho tivesse sido apertado.
  void emit(String code, {String? symbology}) => _controller.add(
        BarcodeRead(
          code: code,
          readAt: DateTime.now(),
          symbology: symbology,
        ),
      );

  void emitRead(BarcodeRead read) => _controller.add(read);

  @override
  Stream<BarcodeRead> get reads => _controller.stream;

  @override
  Future<Result<void>> start() async {
    started = true;
    return const Ok(null);
  }

  @override
  Future<Result<void>> stop() async {
    started = false;
    return const Ok(null);
  }

  @override
  Future<bool> isAvailable() async => available;

  Future<void> dispose() => _controller.close();
}
