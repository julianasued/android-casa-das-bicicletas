/// A tela do POC, com hardware falso.
///
/// O que se verifica aqui não é o desenho: é que cada botão chega ao hardware,
/// e que uma falha da impressora aparece na tela em vez de sumir. É o mínimo
/// para que o teste no M10 físico esteja medindo o aparelho, e não um defeito
/// do aplicativo.
library;

import 'package:casa_das_bicicletas/domain/entities/barcode_read.dart';
import 'package:casa_das_bicicletas/domain/ports/customer_display.dart';
import 'package:casa_das_bicicletas/domain/ports/document_printer.dart';
import 'package:casa_das_bicicletas/platform/printer/print_command.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:casa_das_bicicletas/platform/scanner/fake_barcode_scanner.dart';
import 'package:casa_das_bicicletas/presentation/m10_poc/m10_poc_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeDocumentPrinter printer;
  late FakeBarcodeScanner scanner;
  late FakeCustomerDisplay display;
  late M10PocController controller;

  void build({PrinterStatus? status}) {
    printer = status == null
        ? FakeDocumentPrinter()
        : FakeDocumentPrinter(currentStatus: status);
    scanner = FakeBarcodeScanner();
    display = FakeCustomerDisplay();
    controller = M10PocController(
      printer: printer,
      scanner: scanner,
      display: display,
    );
  }

  setUp(build);

  tearDown(() async {
    controller.dispose();
    await scanner.dispose();
  });

  group('impressora', () {
    test('imprimir texto envia comandos de texto e registra sucesso', () async {
      await controller.printText();

      expect(printer.printed, hasLength(1));
      expect(printer.printed.single.whereType<PrintText>(), isNotEmpty);
      expect(controller.lastError, isNull);
      expect(controller.lastSuccess, contains('Impressão de texto'));
    });

    test('imprimir código de barras cobre CODE128, EAN-13 e EAN-8', () async {
      await controller.printBarcodes();

      final symbologies = printer.printed.single
          .whereType<PrintBarcode>()
          .map((command) => command.symbology)
          .toSet();

      expect(symbologies, {
        BarcodeSymbology.code128,
        BarcodeSymbology.ean13,
        BarcodeSymbology.ean8,
      });
    });

    test('imprimir QR Code envia um comando de QR', () async {
      await controller.printQrCode();

      expect(printer.printed.single.whereType<PrintQrCode>(), hasLength(1));
    });

    test('imagem sem caminho nem chega ao hardware', () async {
      await controller.printImage('   ');

      expect(printer.printed, isEmpty);
      expect(controller.lastError, contains('caminho'));
    });

    test('avanço, corte e reinício chegam ao hardware', () async {
      await controller.feedPaper();
      await controller.cutPaper();
      await controller.reconnectPrinter();

      expect(printer.operations, containsAll(<String>['feed:3', 'cut:3']));
      expect(
        printer.operations,
        containsAllInOrder(<String>['disconnect', 'reset']),
        reason: 'reabrir é fechar e reinicializar, nessa ordem',
      );
    });

    test('falta de papel vira erro visível, não silêncio', () async {
      build(status: const PrinterStatus(available: true, outOfPaper: true));

      await controller.printText();

      expect(printer.printed, isEmpty);
      expect(controller.lastError, isNotNull);
      expect(controller.lastError, contains('papel'));
    });
  });

  group('leitor', () {
    test('iniciar liga o leitor e a leitura aparece na tela', () async {
      await controller.startScanner();
      expect(scanner.started, isTrue);
      expect(controller.scannerRunning, isTrue);

      scanner.emit('SALE-L1-7F3A9C2B', symbology: 'CODE128');
      await Future<void>.delayed(Duration.zero);

      expect(controller.lastRead?.code, 'SALE-L1-7F3A9C2B');
      expect(controller.lastRead?.symbology, 'CODE128');
    });

    test('parar desliga o leitor', () async {
      await controller.startScanner();
      await controller.stopScanner();

      expect(scanner.started, isFalse);
      expect(controller.scannerRunning, isFalse);
    });

    test('código digitado entra como leitura de origem manual', () {
      controller.registerManualRead('7891234567890');

      expect(controller.lastRead?.code, '7891234567890');
      expect(controller.lastRead?.source, BarcodeSource.manual);
    });

    test('campo vazio não vira leitura', () {
      controller.registerManualRead('  ');
      expect(controller.lastRead, isNull);
    });
  });

  group('display do cliente', () {
    test('enviar mensagem chega ao display', () async {
      await controller.showOnDisplay('Total: R\$ 150,00');

      expect(display.shown, hasLength(1));
      expect(display.shown.single, contains('Total: R\$ 150,00'));
    });

    test('mensagem vazia vira saudação, em vez de linha em branco', () async {
      await controller.showOnDisplay('');

      expect(display.shown.single, contains('Bem-vindo'));
    });

    test('limpar chega ao display', () async {
      await controller.clearDisplay();
      expect(display.cleared, isTrue);
    });
  });

  test('diagnóstico inicial consulta impressora e display sem imprimir', () async {
    await controller.refreshAll();

    expect(controller.printerStatus, isNotNull);
    expect(controller.displayStatus, isNotNull);
    expect(printer.printed, isEmpty, reason: 'diagnóstico não gasta papel');
  });

  test('uma operação de cada vez: a segunda chamada é ignorada', () async {
    // Toque duplo no botão é comum no balcão; duas impressões simultâneas na
    // mesma bobina, não.
    final first = controller.printText();
    final second = controller.printText();
    await Future.wait([first, second]);

    expect(printer.printed, hasLength(1));
  });
}
