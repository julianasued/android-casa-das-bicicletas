/// Estado da tela de POC do M10.
///
/// Fica fora da tela porque o POC é uma sequência de operações de hardware com
/// resultado — e o que interessa registrar (último erro, última leitura, estado
/// de cada periférico) é justamente o que se olha depois, quando alguém
/// pergunta "o que aconteceu no aparelho?".
///
/// Nenhuma regra de venda passa por aqui: o POC prova a comunicação com o
/// hardware e nada mais.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../domain/entities/barcode_read.dart';
import '../../domain/ports/barcode_scanner.dart';
import '../../domain/ports/customer_display.dart';
import '../../domain/ports/document_printer.dart';
import '../../platform/printer/print_command.dart';
import '../../platform/printer/printer_diagnostics.dart';
import '../../platform/scanner/scanner_channel.dart';

class M10PocController extends ChangeNotifier {
  M10PocController({
    required PrinterDiagnostics printer,
    required BarcodeScanner scanner,
    required CustomerDisplay display,
  })  : _printer = printer,
        _scanner = scanner,
        _display = display;

  final PrinterDiagnostics _printer;
  final BarcodeScanner _scanner;
  final CustomerDisplay _display;

  StreamSubscription<BarcodeRead>? _subscription;

  PrinterStatus? _printerStatus;
  CustomerDisplayStatus? _displayStatus;
  Map<String, Object?> _scannerProbe = const <String, Object?>{};
  BarcodeRead? _lastRead;
  bool _scannerRunning = false;
  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;

  PrinterStatus? get printerStatus => _printerStatus;
  CustomerDisplayStatus? get displayStatus => _displayStatus;
  Map<String, Object?> get scannerProbe => _scannerProbe;
  BarcodeRead? get lastRead => _lastRead;
  bool get scannerRunning => _scannerRunning;
  bool get busy => _busy;
  String? get lastError => _lastError;
  String? get lastSuccess => _lastSuccess;

  /// Levantamento inicial dos três periféricos, sem imprimir nada.
  Future<void> refreshAll() async {
    await _run('Diagnóstico', () async {
      final printer = await _printer.status();
      _printerStatus = printer.valueOrNull;

      final display = await _display.probe();
      _displayStatus = display.valueOrNull;

      if (_scanner case final ScannerChannel channel) {
        _scannerProbe = await channel.probe();
      }
      return printer.failureOrNull ?? display.failureOrNull;
    });
  }

  // -------------------------------------------------------------------------
  // Impressora
  // -------------------------------------------------------------------------

  Future<void> printText() => _run('Impressão de texto', () async {
        final result = await _printer.sendCommands(const [
          PrintText('CASA DAS BICICLETAS', align: PrintAlign.center, bold: true),
          PrintText('--------------------------------'),
          PrintText('Alinhado a esquerda'),
          PrintText('Centralizado', align: PrintAlign.center),
          PrintText('A direita', align: PrintAlign.right),
          PrintText('Negrito', bold: true),
          PrintText('Sublinhado', underline: true),
          PrintText('Altura dupla', doubleHeight: true),
          PrintText('Largura dupla', doubleWidth: true),
          PrintFeed(2),
          PrintCut(),
        ]);
        return result.failureOrNull;
      });

  /// Uma via por simbologia, com dado válido para cada uma.
  ///
  /// O comprimento importa: EAN-13 quer 12–13 dígitos, EAN-8 quer 7–8. Mandar o
  /// dado errado devolve erro do SDK, não código torto no papel — e é bom que o
  /// POC mostre a diferença.
  Future<void> printBarcodes() => _run('Impressão de código de barras', () async {
        final result = await _printer.sendCommands(const [
          PrintText('CODE 128', align: PrintAlign.center),
          PrintBarcode('SALE-L1-7F3A9C2B'),
          PrintFeed(),
          PrintText('EAN-13', align: PrintAlign.center),
          PrintBarcode('789123456789', symbology: BarcodeSymbology.ean13),
          PrintFeed(),
          PrintText('EAN-8', align: PrintAlign.center),
          PrintBarcode('7891234', symbology: BarcodeSymbology.ean8),
          PrintFeed(2),
          PrintCut(),
        ]);
        return result.failureOrNull;
      });

  Future<void> printQrCode() => _run('Impressão de QR Code', () async {
        final result = await _printer.sendCommands(const [
          PrintText('QR CODE', align: PrintAlign.center),
          PrintQrCode('https://casadasbicicletas.com.br/venda/TESTE'),
          PrintFeed(2),
          PrintCut(),
        ]);
        return result.failureOrNull;
      });

  /// Imagem por caminho de arquivo, como `ImprimeImagem` espera.
  ///
  /// O caminho é informado na tela porque não há logo embarcado no aplicativo:
  /// o POC prova a chamada, não o desenho.
  Future<void> printImage(String path) => _run('Impressão de imagem', () async {
        if (path.trim().isEmpty) {
          return const BusinessRuleFailure(
            'Informe o caminho de um arquivo de imagem no aparelho.',
          );
        }
        final result = await _printer.sendCommands([PrintImage(path.trim())]);
        return result.failureOrNull;
      });

  Future<void> feedPaper() => _run('Avanço de papel', () async {
        final result = await _printer.feed();
        return result.failureOrNull;
      });

  Future<void> cutPaper() => _run('Corte de papel', () async {
        final result = await _printer.cut();
        return result.failureOrNull;
      });

  Future<void> checkPrinter() => _run('Status da impressora', () async {
        final result = await _printer.status();
        _printerStatus = result.valueOrNull;
        return result.failureOrNull;
      });

  /// Fecha e reabre: é o teste de recuperação depois de um erro.
  Future<void> reconnectPrinter() => _run('Reabertura da impressora', () async {
        final closed = await _printer.disconnect();
        if (closed.failureOrNull case final Failure failure) return failure;

        final reset = await _printer.reset();
        if (reset.failureOrNull case final Failure failure) return failure;

        final status = await _printer.status();
        _printerStatus = status.valueOrNull;
        return status.failureOrNull;
      });

  // -------------------------------------------------------------------------
  // Leitor
  // -------------------------------------------------------------------------

  Future<void> startScanner() => _run('Início do leitor', () async {
        _subscription ??= _scanner.reads.listen(
          (read) {
            _lastRead = read;
            notifyListeners();
          },
          onError: (Object error) {
            _lastError = error is Failure ? error.message : error.toString();
            notifyListeners();
          },
        );

        final result = await _scanner.start();
        _scannerRunning = result.isOk;

        if (_scanner case final ScannerChannel channel) {
          _scannerProbe = await channel.probe();
        }
        return result.failureOrNull;
      });

  Future<void> stopScanner() => _run('Parada do leitor', () async {
        final result = await _scanner.stop();
        _scannerRunning = false;

        await _subscription?.cancel();
        _subscription = null;
        return result.failureOrNull;
      });

  /// Entrada manual — vale como leitura para exercitar a tela sem hardware.
  void registerManualRead(String code) {
    if (code.trim().isEmpty) return;

    _lastRead = BarcodeRead(
      code: code.trim(),
      readAt: DateTime.now(),
      source: BarcodeSource.manual,
    );
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Display do cliente
  // -------------------------------------------------------------------------

  Future<void> showOnDisplay(String message) => _run('Envio ao display', () async {
        final result = await _display.show([
          'CASA DAS BICICLETAS',
          message.trim().isEmpty ? 'Bem-vindo' : message.trim(),
        ]);
        return result.failureOrNull;
      });

  Future<void> clearDisplay() => _run('Limpeza do display', () async {
        final result = await _display.clear();
        return result.failureOrNull;
      });

  // -------------------------------------------------------------------------

  /// Executa a operação registrando o desfecho — é isso que o POC precisa ver.
  Future<void> _run(String label, Future<Failure?> Function() action) async {
    if (_busy) return;

    _busy = true;
    _lastError = null;
    _lastSuccess = null;
    notifyListeners();

    Failure? failure;
    try {
      failure = await action();
    } catch (error) {
      failure = UnexpectedFailure('$label: $error');
    }

    _busy = false;
    if (failure == null) {
      _lastSuccess = '$label: OK';
    } else {
      _lastError = '$label: ${failure.message}';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_scanner.stop());
    super.dispose();
  }
}
