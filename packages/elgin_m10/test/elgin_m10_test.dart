/// O contrato entre o Dart e o Kotlin.
///
/// Estes testes trocam o lado nativo por um espião e conferem o que atravessa o
/// canal: nome do método e argumentos. É um contrato invisível — um
/// `double_height` que virasse `doubleHeight`, ou um `BarcodeType.ean13` que
/// mandasse `13` em vez de `2`, não quebraria compilação de lado nenhum e só
/// apareceria no papel, no M10, no dia do teste.
library;

import 'package:elgin_m10/elgin_m10.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uma chamada capturada no caminho para o lado nativo.
class _Call {
  _Call(this.method, this.arguments);

  final String method;
  final Map<Object?, Object?> arguments;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const printer = MethodChannel('elgin_m10/printer');
  const display = MethodChannel('elgin_m10/display');
  const scanner = MethodChannel('elgin_m10/scanner');

  final calls = <_Call>[];
  late Object? Function(MethodCall call) respond;

  void mock(MethodChannel channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(
        _Call(
          call.method,
          call.arguments is Map
              ? call.arguments as Map<Object?, Object?>
              : const <Object?, Object?>{},
        ),
      );
      return respond(call);
    });
  }

  setUp(() {
    calls.clear();
    respond = (_) => null;
    mock(printer);
    mock(display);
    mock(scanner);
  });

  tearDown(() {
    for (final channel in [printer, display, scanner]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('impressora', () {
    test('open usa (6, "M8", "", 0) por padrão', () async {
      await ElginPrinter.open();

      expect(calls.last.method, 'printer.open');
      expect(calls.last.arguments['type'], 6);
      expect(calls.last.arguments['model'], 'M8');
      expect(calls.last.arguments['connection'], '');
      expect(calls.last.arguments['parameter'], 0);
    });

    test('open aceita a combinação da documentação pública', () async {
      // A doc pública descreve tipo 1..5 e o exemplo oficial usa (5, "").
      // Poder trocar sem recompilar é o motivo de os parâmetros existirem.
      await ElginPrinter.open(type: 5, model: '');

      expect(calls.last.arguments['type'], 5);
      expect(calls.last.arguments['model'], '');
    });

    test('printText envia alinhamento, estilo e tamanho', () async {
      await ElginPrinter.printText(
        'Total',
        align: PrinterAlign.center,
        style: PrinterStyle.of(bold: true, underline: true),
        size: PrinterSize.of(height: PrinterSize.height2x),
      );

      expect(calls.last.method, 'printer.printText');
      expect(calls.last.arguments['text'], 'Total');
      expect(calls.last.arguments['align'], 1);
      // `estilo` é soma de bits: sublinhado (2) + negrito (8).
      expect(calls.last.arguments['style'], 10);
      expect(calls.last.arguments['size'], 1);
    });

    test('as simbologias usam o código do SDK, não a ordem do enum', () async {
      await ElginPrinter.printBarcode('789123456789', type: BarcodeType.ean13);
      expect(calls.last.arguments['type'], 2);

      await ElginPrinter.printBarcode('7891234', type: BarcodeType.ean8);
      expect(calls.last.arguments['type'], 3);

      await ElginPrinter.printBarcode('X', type: BarcodeType.code128);
      expect(calls.last.arguments['type'], 8);
    });

    test('CODE 128 ganha o seletor de conjunto que o SDK exige', () async {
      // Sem o `{B` o SDK devolve -65 até para dados triviais (M10 Pro, 09/2026).
      await ElginPrinter.printBarcode('SALE-L1-7F3A9C2B', type: BarcodeType.code128);
      expect(calls.last.arguments['data'], '{BSALE-L1-7F3A9C2B');

      await ElginPrinter.printBarcode('12345678', type: BarcodeType.code128);
      expect(calls.last.arguments['data'], '{B12345678');
    });

    test('seletor já escolhido por quem chama é preservado', () async {
      await ElginPrinter.printBarcode('{C123456', type: BarcodeType.code128);
      expect(calls.last.arguments['data'], '{C123456');

      // `{` sem conjunto válido logo depois não conta como seletor.
      await ElginPrinter.printBarcode('{X99', type: BarcodeType.code128);
      expect(calls.last.arguments['data'], '{B{X99');
    });

    test('as outras simbologias passam intactas', () async {
      // EAN-13 aceita 12 ou 13 dígitos; nada de seletor aqui.
      await ElginPrinter.printBarcode('789123456789', type: BarcodeType.ean13);
      expect(calls.last.arguments['data'], '789123456789');

      await ElginPrinter.printBarcode('7891234', type: BarcodeType.ean8);
      expect(calls.last.arguments['data'], '7891234');
    });

    test('HRI abaixo é o padrão', () async {
      await ElginPrinter.printBarcode('X', type: BarcodeType.code128);
      expect(calls.last.arguments['hri'], 2);

      await ElginPrinter.printBarcode(
        'X',
        type: BarcodeType.code128,
        hri: HriPosition.none,
      );
      expect(calls.last.arguments['hri'], 4);
    });

    test('QR Code usa nivel de correcao valido por padrao', () async {
      // O padrao era 0, que o SDK recusa com -52 (M10 Pro, 09/2026).
      await ElginPrinter.printQrCode('https://exemplo');
      expect(calls.last.arguments['correction'], 2);
      expect(calls.last.arguments['size'], 4);
    });

    test('cut distingue corte parcial de total', () async {
      await ElginPrinter.cut();
      expect(calls.last.arguments['full'], isFalse);

      await ElginPrinter.cut(feed: 5, full: true);
      expect(calls.last.arguments['full'], isTrue);
      expect(calls.last.arguments['feed'], 5);
    });

    test('imagem atravessa como bytes, sem caminho de arquivo', () async {
      await ElginPrinter.printImageFromBytes(Uint8List.fromList([1, 2, 3]));

      expect(calls.last.method, 'printer.printImage');
      expect(calls.last.arguments['bytes'], isA<Uint8List>());
      expect(calls.last.arguments.containsKey('path'), isFalse);
    });

    test('status devolve os cinco assuntos sem interpretar', () async {
      respond = (_) => <String, Object?>{
            'drawer': 1,
            'cover': 0,
            'paper': 3,
            'ejector': 0,
            'general': 7,
          };

      final status = await ElginPrinter.status();

      expect(status.paper, 3);
      expect(status.general, 7);
      expect(status.toMap().keys, hasLength(5));
    });
  });

  group('erros', () {
    test('retorno do SDK vira ElginException com código e operação', () async {
      respond = (_) => throw PlatformException(
            code: 'ELGIN_SDK_ERROR',
            message: 'ImpressaoTexto falhou (código -44).',
            details: <String, Object?>{'code': -44, 'operation': 'ImpressaoTexto'},
          );

      await expectLater(
        ElginPrinter.printText('x'),
        throwsA(
          isA<ElginException>()
              .having((e) => e.kind, 'kind', ElginFailureKind.sdkError)
              .having((e) => e.code, 'code', -44)
              .having((e) => e.operation, 'operation', 'ImpressaoTexto'),
        ),
      );
    });

    test('sem Activity é falha de indisponibilidade, não de impressão', () async {
      respond = (_) => throw PlatformException(
            code: 'NO_ACTIVITY',
            message: 'Nenhuma Activity anexada ao plugin.',
          );

      try {
        await ElginPrinter.open();
        fail('deveria ter lançado');
      } on ElginException catch (error) {
        expect(error.kind, ElginFailureKind.noActivity);
        expect(error.isUnavailable, isTrue);
      }
    });

    test('SDK ausente é distinguido de recusa do aparelho', () async {
      respond = (_) => throw PlatformException(
            code: 'SDK_MISSING',
            message: 'SDK da Elgin ausente neste build.',
          );

      try {
        await ElginPrinter.open();
        fail('deveria ter lançado');
      } on ElginException catch (error) {
        expect(error.kind, ElginFailureKind.sdkMissing);
        expect(error.code, isNull);
      }
    });
  });

  group('display', () {
    test('open manda M10_PRO por padrão, não AUTO', () async {
      await ElginDisplay.open();

      expect(calls.last.method, 'display.open');
      expect(calls.last.arguments['device'], 'M10_PRO');
    });

    test('showText sem cor não envia o campo de cor', () async {
      await ElginDisplay.showText('Bem-vindo');

      expect(calls.last.arguments['text'], 'Bem-vindo');
      expect(calls.last.arguments.containsKey('color'), isFalse);
    });

    test('showText com cor usa a variante colorida', () async {
      await ElginDisplay.showText('Total', color: '#FF0000');
      expect(calls.last.arguments['color'], '#FF0000');
    });
  });

  group('scanner', () {
    test('start pede leitura contínua por padrão', () async {
      await ElginScanner.start();

      expect(calls.last.method, 'scanner.start');
      expect(calls.last.arguments['continuous'], isTrue);
    });

    test('start aceita disparo único', () async {
      await ElginScanner.start(continuous: false);
      expect(calls.last.arguments['continuous'], isFalse);
    });

    test('stop não leva argumento', () async {
      await ElginScanner.stop();
      expect(calls.last.method, 'scanner.stop');
    });
  });
}
