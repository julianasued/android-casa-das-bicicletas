/// Impressora térmica do M10, atrás de um canal de método.
///
/// A tradução dos comandos para o SDK E1 da Elgin acontece do lado Kotlin
/// (`PrinterChannel.kt` → `ElginThermalPrinter.kt`). Deste lado ficam duas
/// responsabilidades: montar o documento (`DocumentLayout`) e transformar os
/// códigos de erro do canal nas falhas que a interface sabe explicar — falta de
/// papel tem solução no balcão, SDK ausente não tem, e o operador precisa saber
/// qual é o caso (§11).
///
/// A classe atende dois contratos: `DocumentPrinter`, que é o que a venda usa,
/// e `PrinterDiagnostics`, que é o que a tela do POC usa. Uma instância só,
/// porque é um aparelho só.
library;

import 'package:flutter/services.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/ports/document_printer.dart';
import 'barcode_bitmap.dart';
import 'document_layout.dart';
import 'print_command.dart';
import 'printer_diagnostics.dart';

/// Códigos combinados com o lado Kotlin.
class PrinterErrorCode {
  static const String unavailable = 'PRINTER_UNAVAILABLE';
  static const String outOfPaper = 'OUT_OF_PAPER';
  static const String printFailed = 'PRINT_FAILED';
}

class PrinterChannel implements DocumentPrinter, PrinterDiagnostics {
  PrinterChannel({
    MethodChannel? channel,
    DocumentLayout layout = const DocumentLayout(),
  })  : _channel = channel ?? const MethodChannel(channelName),
        _layout = layout;

  static const String channelName = 'br.com.casadasbicicletas.vendas/printer';

  final MethodChannel _channel;
  final DocumentLayout _layout;

  @override
  Future<Result<PrinterStatus>> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      if (raw == null) {
        return const Ok(PrinterStatus.unavailable('Impressora não respondeu.'));
      }

      return Ok(
        PrinterStatus(
          available: raw['available'] as bool? ?? false,
          outOfPaper: raw['out_of_paper'] as bool? ?? false,
          coverOpen: raw['cover_open'] as bool? ?? false,
          detail: raw['detail']?.toString() ?? '',
          rawStatus: _readRawStatus(raw['raw_status']),
        ),
      );
    } on PlatformException catch (error) {
      return Err(_failureFor(error));
    } on MissingPluginException {
      // Aplicativo rodando fora do terminal (emulador, teste de tela): não é
      // erro do operador, e a tela precisa dizer isso em vez de "falha".
      return const Ok(
        PrinterStatus.unavailable('Canal da impressora indisponível neste aparelho.'),
      );
    }
  }

  /// `StatusImpressora` por assunto, como veio do SDK — sem interpretação.
  Map<String, int> _readRawStatus(Object? value) {
    if (value is! Map) return const <String, int>{};

    final parsed = <String, int>{};
    value.forEach((key, item) {
      if (item is int) parsed[key.toString()] = item;
    });
    return parsed;
  }

  // ---------------------------------------------------------------------------
  // DocumentPrinter — o que a venda usa
  // ---------------------------------------------------------------------------

  @override
  Future<Result<void>> printDocument(PrintedDocument document) =>
      sendCommands(_layout.build(document));

  @override
  Future<Result<void>> printTestPage({required String terminalName}) =>
      sendCommands(_layout.buildTestPage(terminalName: terminalName));

  // ---------------------------------------------------------------------------
  // PrinterDiagnostics — o que o POC usa
  // ---------------------------------------------------------------------------

  @override
  Future<Result<void>> sendCommands(List<PrintCommand> commands) async =>
      _call('print', {'commands': encodeCommands(await _drawBarcodes(commands))});

  /// Troca cada CODE 128 pelo bitmap que desenhamos.
  ///
  /// O SDK aceita o dado e devolve sucesso, mas no M10 quem dimensiona as
  /// barras é o serviço NYX e o resultado não decodifica — conferido no
  /// aparelho, onde o mesmo código saiu ilegível pelo SDK e legível como
  /// imagem, na mesma tirada de papel.
  ///
  /// Acontece aqui, e não no [DocumentLayout], porque desenhar é assíncrono e o
  /// layout é síncrono de propósito: é o que permite testar o documento inteiro
  /// sem rasterizar nada.
  ///
  /// As outras simbologias seguem pelo SDK. O EAN-8 lê bem por lá, e o que não
  /// se sabe se está quebrado não se conserta às cegas.
  Future<List<PrintCommand>> _drawBarcodes(List<PrintCommand> commands) async {
    final saida = <PrintCommand>[];

    for (final command in commands) {
      if (command is! PrintBarcode ||
          command.symbology != BarcodeSymbology.code128) {
        saida.add(command);
        continue;
      }

      // Módulo maior lê com mais folga, mas o papel de 58mm tem 384 pontos: o
      // código de venda de hoje, com 16 caracteres, só entra com 1 ponto por
      // módulo. Pega o maior que couber em vez de fixar um número que quebra
      // quando o formato do código mudar.
      final modulo = [3, 2, 1].firstWhere(
        (candidato) => code128Fits(command.data, modulePoints: candidato),
        orElse: () => 1,
      );

      saida.add(
        PrintImageBytes(
          await code128Png(
            command.data,
            modulePoints: modulo,
            barHeightDots: command.height,
          ),
          label: command.data,
        ),
      );
    }

    return saida;
  }

  @override
  Future<Result<void>> feed({int lines = 3}) => _call('feed', {'lines': lines});

  @override
  Future<Result<void>> cut({int advance = 3}) => _call('cut', {'advance': advance});

  @override
  Future<Result<void>> reset() => _call('reset');

  @override
  Future<Result<void>> disconnect() => _call('disconnect');

  Future<Result<void>> _call(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
      return const Ok(null);
    } on PlatformException catch (error) {
      return Err(_failureFor(error));
    } on MissingPluginException {
      return const Err(PrinterUnavailableFailure());
    }
  }

  Failure _failureFor(PlatformException error) => switch (error.code) {
        PrinterErrorCode.outOfPaper => OutOfPaperFailure(
            error.message ?? 'Sem papel. Reponha a bobina e reimprima o documento.',
          ),
        PrinterErrorCode.unavailable => PrinterUnavailableFailure(
            error.message ?? 'Impressora indisponível neste terminal.',
          ),
        _ => PrintFailure(
            error.message ?? 'Falha ao imprimir. Confira a impressora e reimprima.',
          ),
      };
}

/// Impressora de mentira, para rodar o aplicativo e o POC fora do M10.
///
/// Existe para a tela poder ser exercitada em emulador e em teste de widget sem
/// `MissingPluginException` a cada botão. Guarda o que "imprimiu" para que o
/// teste possa conferir o papel.
class FakeDocumentPrinter implements DocumentPrinter, PrinterDiagnostics {
  FakeDocumentPrinter({
    this.currentStatus = const PrinterStatus(available: true, outOfPaper: false),
  });

  final PrinterStatus currentStatus;
  final List<List<PrintCommand>> printed = <List<PrintCommand>>[];
  final List<String> operations = <String>[];
  final DocumentLayout _layout = const DocumentLayout();

  @override
  Future<Result<PrinterStatus>> status() async => Ok(currentStatus);

  @override
  Future<Result<void>> printDocument(PrintedDocument document) =>
      sendCommands(_layout.build(document));

  @override
  Future<Result<void>> printTestPage({required String terminalName}) =>
      sendCommands(_layout.buildTestPage(terminalName: terminalName));

  @override
  Future<Result<void>> sendCommands(List<PrintCommand> commands) async {
    if (!currentStatus.canPrint) {
      return Err(
        currentStatus.outOfPaper
            ? const OutOfPaperFailure()
            : const PrinterUnavailableFailure(),
      );
    }
    printed.add(commands);
    operations.add('print');
    return const Ok(null);
  }

  @override
  Future<Result<void>> feed({int lines = 3}) async {
    operations.add('feed:$lines');
    return const Ok(null);
  }

  @override
  Future<Result<void>> cut({int advance = 3}) async {
    operations.add('cut:$advance');
    return const Ok(null);
  }

  @override
  Future<Result<void>> reset() async {
    operations.add('reset');
    return const Ok(null);
  }

  @override
  Future<Result<void>> disconnect() async {
    operations.add('disconnect');
    return const Ok(null);
  }
}
