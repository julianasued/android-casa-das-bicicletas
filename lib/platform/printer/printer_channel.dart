/// Impressora térmica do M10 Pro, atrás de um canal de método.
///
/// A tradução dos comandos para o SDK da Elgin acontece do lado Kotlin
/// (`PrinterChannel.kt`). Deste lado ficam duas responsabilidades: montar o
/// documento (`DocumentLayout`) e transformar os códigos de erro do canal nas
/// falhas que a interface sabe explicar — falta de papel tem solução no balcão,
/// SDK ausente não tem, e o operador precisa saber qual é o caso (§11).
library;

import 'package:flutter/services.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/ports/document_printer.dart';
import 'document_layout.dart';
import 'print_command.dart';

/// Códigos combinados com o lado Kotlin.
class PrinterErrorCode {
  static const String unavailable = 'PRINTER_UNAVAILABLE';
  static const String outOfPaper = 'OUT_OF_PAPER';
  static const String printFailed = 'PRINT_FAILED';
}

class PrinterChannel implements DocumentPrinter {
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
          detail: raw['detail']?.toString() ?? '',
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

  @override
  Future<Result<void>> printDocument(PrintedDocument document) =>
      _print(_layout.build(document));

  @override
  Future<Result<void>> printTestPage({required String terminalName}) =>
      _print(_layout.buildTestPage(terminalName: terminalName));

  @override
  Future<Result<void>> feed({int lines = 3}) async {
    try {
      await _channel.invokeMethod<void>('feed', {'lines': lines});
      return const Ok(null);
    } on PlatformException catch (error) {
      return Err(_failureFor(error));
    } on MissingPluginException {
      return const Err(PrinterUnavailableFailure());
    }
  }

  Future<Result<void>> _print(List<PrintCommand> commands) async {
    try {
      await _channel.invokeMethod<void>('print', {
        'commands': encodeCommands(commands),
      });
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

/// Impressora de mentira, para rodar o aplicativo fora do M10.
///
/// Existe para a tela poder ser exercitada em emulador e em teste de widget sem
/// `MissingPluginException` a cada botão. Guarda o que "imprimiu" para que o
/// teste possa conferir o papel.
class FakeDocumentPrinter implements DocumentPrinter {
  FakeDocumentPrinter({
    this.currentStatus = const PrinterStatus(available: true, outOfPaper: false),
  });

  final PrinterStatus currentStatus;
  final List<List<PrintCommand>> printed = <List<PrintCommand>>[];
  final DocumentLayout _layout = const DocumentLayout();

  @override
  Future<Result<PrinterStatus>> status() async => Ok(currentStatus);

  @override
  Future<Result<void>> printDocument(PrintedDocument document) async {
    if (!currentStatus.canPrint) {
      return Err(
        currentStatus.outOfPaper
            ? const OutOfPaperFailure()
            : const PrinterUnavailableFailure(),
      );
    }
    printed.add(_layout.build(document));
    return const Ok(null);
  }

  @override
  Future<Result<void>> printTestPage({required String terminalName}) async {
    printed.add(_layout.buildTestPage(terminalName: terminalName));
    return const Ok(null);
  }

  @override
  Future<Result<void>> feed({int lines = 3}) async => const Ok(null);
}
