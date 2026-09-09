/// A tela do POC, com o lado nativo espionado.
///
/// O que se verifica não é o desenho: é que cada botão chega ao hardware na
/// sequência certa, e que uma falha do SDK aparece na tela em vez de sumir. É o
/// mínimo para que o teste no M10 físico esteja medindo o aparelho, e não um
/// defeito do aplicativo.
library;

import 'package:casa_das_bicicletas/presentation/m10_poc/m10_poc_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const printer = MethodChannel('elgin_m10/printer');
  const display = MethodChannel('elgin_m10/display');
  const scanner = MethodChannel('elgin_m10/scanner');

  final methods = <String>[];
  late Object? Function(MethodCall call) respond;

  void mock(MethodChannel channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return respond(call);
    });
  }

  late M10PocController controller;

  setUp(() {
    methods.clear();
    respond = (call) => switch (call.method) {
          'printer.status' => <String, Object?>{
              'drawer': 0,
              'cover': 0,
              'paper': 0,
              'ejector': 0,
              'general': 0,
            },
          'printer.info' => <String, Object?>{
              'sdk_version': '02.34.04',
              'serial': 'TESTE',
            },
          _ => null,
        };

    mock(printer);
    mock(display);
    mock(scanner);
    controller = M10PocController();
  });

  tearDown(() {
    controller.dispose();
    for (final channel in [printer, display, scanner]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('impressora', () {
    test('abrir registra a conexão e lê a versão do SDK', () async {
      await controller.openPrinter();

      expect(methods, containsAllInOrder(['printer.open', 'printer.info']));
      expect(controller.printerOpen, isTrue);
      expect(controller.printerInfo['sdk_version'], '02.34.04');
      expect(controller.lastError, isNull);
    });

    test('imprimir abre a conexão sozinho quando ela não está aberta', () async {
      await controller.printText();

      expect(methods.first, 'printer.open');
      expect(methods, contains('printer.printText'));
      expect(methods, contains('printer.cut'));
    });

    test('a conexão não é reaberta a cada impressão', () async {
      // `AbreConexaoImpressora` devolve erro quando já está aberta; reabrir a
      // cada botão transformaria uso normal em falha.
      await controller.openPrinter();
      methods.clear();

      await controller.printQrCode();

      expect(methods, isNot(contains('printer.open')));
      expect(methods, contains('printer.printQrCode'));
    });

    test('imprimir código de barras cobre as três simbologias', () async {
      await controller.printBarcodes();

      final barcodes =
          methods.where((method) => method == 'printer.printBarcode').length;
      expect(barcodes, 3);
    });

    test('imagem vai pelo caminho de bytes', () async {
      await controller.printImage();
      expect(methods, contains('printer.printImage'));
    });

    test('reabrir fecha, abre e reinicializa nessa ordem', () async {
      await controller.openPrinter();
      methods.clear();

      await controller.reconnectPrinter();

      expect(
        methods,
        containsAllInOrder([
          'printer.close',
          'printer.open',
          'printer.initialize',
          'printer.status',
        ]),
      );
    });

    test('falha do SDK aparece com o código, e derruba o estado da conexão',
        () async {
      await controller.openPrinter();
      respond = (_) => throw PlatformException(
            code: 'ELGIN_SDK_ERROR',
            message: 'ImpressaoTexto falhou (código -44).',
            details: <String, Object?>{'code': -44, 'operation': 'ImpressaoTexto'},
          );

      await controller.printText();

      expect(controller.lastError, contains('-44'));
      expect(
        controller.printerOpen,
        isFalse,
        reason: 'insistir sobre uma conexão que o SDK perdeu repete o erro',
      );
    });
  });

  group('parâmetros de conexão', () {
    test('a combinação da documentação pública pode ser testada sem recompilar',
        () async {
      controller
        ..connectionType = 5
        ..connectionModel = '';

      MethodCall? aberta;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(printer, (call) async {
        if (call.method == 'printer.open') aberta = call;
        return null;
      });

      await controller.openPrinter();

      final argumentos = aberta!.arguments as Map<Object?, Object?>;
      expect(argumentos['type'], 5);
      expect(argumentos['model'], '');
    });
  });

  group('display', () {
    test('enviar abre o display antes de escrever', () async {
      await controller.showOnDisplay('Total: 150,00');

      expect(methods, containsAllInOrder(['display.open', 'display.showText']));
      expect(controller.displayOpen, isTrue);
    });

    test('mensagem vazia vira saudação, em vez de linha em branco', () async {
      MethodCall? texto;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(display, (call) async {
        if (call.method == 'display.showText') texto = call;
        return null;
      });

      await controller.showOnDisplay('   ');

      final argumentos = texto!.arguments as Map<Object?, Object?>;
      expect(argumentos['text'], 'Bem-vindo');
    });

    test('limpar reinicializa, porque a API não tem "limpar"', () async {
      await controller.clearDisplay();
      expect(methods, contains('display.reinitialize'));
    });
  });

  group('leitor', () {
    test('iniciar liga o leitor', () async {
      await controller.startScanner();

      expect(methods, contains('scanner.start'));
      expect(controller.scannerRunning, isTrue);
    });

    test('parar desliga o leitor', () async {
      await controller.startScanner();
      await controller.stopScanner();

      expect(methods, contains('scanner.stop'));
      expect(controller.scannerRunning, isFalse);
    });
  });

  test('uma operação de cada vez: a segunda chamada é ignorada', () async {
    // Toque duplo no botão é comum no balcão; duas impressões simultâneas na
    // mesma bobina, não.
    final primeira = controller.printText();
    final segunda = controller.printText();
    await Future.wait([primeira, segunda]);

    expect(
      methods.where((method) => method == 'printer.printText').length,
      greaterThan(0),
    );
    expect(methods.where((method) => method == 'printer.open').length, 1);
  });
}
