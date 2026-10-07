/// O CODE 128 sai daqui como imagem, não como comando de código de barras.
///
/// No M10 o SDK aceita o dado, devolve sucesso e o que sai não decodifica —
/// quem dimensiona as barras é o serviço NYX. Estes testes prendem a troca no
/// lugar onde ela acontece: o que o canal envia ao lado nativo.
library;

import 'dart:ui' as ui;

import 'package:casa_das_bicicletas/platform/printer/barcode_bitmap.dart';
import 'package:casa_das_bicicletas/platform/printer/print_command.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<Object?, Object?>> enviados;
  late PrinterChannel printer;

  const canal = MethodChannel(PrinterChannel.channelName);

  setUp(() {
    enviados = [];
    printer = PrinterChannel(channel: canal);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      if (call.method == 'print') {
        final comandos = (call.arguments as Map)['commands'] as List;
        enviados = comandos.cast<Map<Object?, Object?>>();
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  test('CODE 128 vira imagem antes de chegar ao lado nativo', () async {
    await printer.sendCommands([const PrintBarcode('SALE-L1-7F3A9C2B')]);

    expect(enviados, hasLength(1));
    expect(enviados.single['type'], 'image_bytes');
    expect(enviados.single['bytes'], isA<Uint8List>());

    // PNG de verdade, não um punhado de bytes qualquer.
    final bytes = enviados.single['bytes']! as Uint8List;
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('escolhe o maior módulo que cabe no papel', () async {
    // A largura do PNG é sempre a da linha, porque o código sai centralizado
    // nela: quem revela o módulo escolhido é a extensão da tinta.
    Future<int> larguraDesenhada(String dado) async {
      await printer.sendCommands([PrintBarcode(dado)]);
      final tinta =
          await _extensaoDaTinta(enviados.single['bytes']! as Uint8List);
      return tinta.fim - tinta.inicio + 1;
    }

    // 16 caracteres = 211 módulos: só entra com 1 ponto por módulo.
    expect(await larguraDesenhada('SALE-L1-7F3A9C2B'), code128Modules(16) * 1);
    // 11 caracteres = 156 módulos: cabe com 2.
    expect(await larguraDesenhada('L1-7F3A9C2B'), code128Modules(11) * 2);
    // 8 caracteres = 123 módulos: cabe com 3.
    expect(await larguraDesenhada('7F3A9C2B'), code128Modules(8) * 3);
  });

  group('centralização no papel', () {
    test('a imagem ocupa a linha inteira, com o código no meio', () async {
      await printer.sendCommands([const PrintBarcode('7F3A9C2B')]);
      final bytes = enviados.single['bytes']! as Uint8List;

      expect(ByteData.sublistView(bytes).getUint32(16), paperDots);

      // Sobra igual nas duas pontas, a menos de um ponto de arredondamento —
      // é isso que faz o código sair no meio do papel em vez de encostado na
      // margem esquerda, já que `ImprimeImagem` não aceita alinhamento.
      final tinta = await _extensaoDaTinta(bytes);
      final sobraEsquerda = tinta.inicio;
      final sobraDireita = tinta.largura - 1 - tinta.fim;
      expect((sobraEsquerda - sobraDireita).abs(), lessThanOrEqualTo(1));
      expect(sobraEsquerda, greaterThan(0));
    });

    test('o QR centralizado sai como imagem; o da esquerda, pelo SDK',
        () async {
      await printer.sendCommands([
        const PrintQrCode('SALE-L1-7F3A9C2B', align: PrintAlign.center),
      ]);
      expect(enviados.single['type'], 'image_bytes');

      final tinta =
          await _extensaoDaTinta(enviados.single['bytes']! as Uint8List);
      expect(tinta.largura, paperDots);
      expect(
        (tinta.inicio - (tinta.largura - 1 - tinta.fim)).abs(),
        lessThanOrEqualTo(1),
      );

      // O caminho do SDK continua intacto: é o que o POC exercita e o que foi
      // conferido no aparelho.
      await printer.sendCommands([const PrintQrCode('SALE-L1-7F3A9C2B')]);
      expect(enviados.single['type'], 'qrcode');
      expect(enviados.single['data'], 'SALE-L1-7F3A9C2B');
    });
  });

  test('a altura padrao da faixa que o leitor precisa', () async {
    // 60 pontos saiam desenhados e nao decodificavam no M10 Pro; 120 sao ~15mm,
    // o minimo usual para leitura por camera.
    await printer.sendCommands([const PrintBarcode('7F3A9C2B')]);

    final altura =
        ByteData.sublistView(enviados.single['bytes']! as Uint8List).getUint32(20);
    expect(altura, 120);
  });

  test('respeita a altura pedida no comando', () async {
    await printer.sendCommands([const PrintBarcode('7F3A9C2B', height: 90)]);

    final altura =
        ByteData.sublistView(enviados.single['bytes']! as Uint8List).getUint32(20);
    expect(altura, 90);
  });

  test('as outras simbologias seguem pelo SDK', () async {
    // O EAN-8 lê bem por lá; o que não se sabe se está quebrado não se
    // conserta às cegas.
    await printer.sendCommands([
      const PrintBarcode('7891234', symbology: BarcodeSymbology.ean8),
    ]);

    expect(enviados.single['type'], 'barcode');
    expect(enviados.single['data'], '7891234');
  });

  test('não mexe no resto do documento', () async {
    await printer.sendCommands([
      const PrintText('CASA DAS BICICLETAS'),
      const PrintBarcode('SALE-L1-7F3A9C2B'),
      const PrintFeed(2),
      const PrintCut(),
    ]);

    expect(
      enviados.map((comando) => comando['type']),
      ['text', 'image_bytes', 'feed', 'cut'],
    );
  });
}

/// Primeira e última coluna com tinta na imagem.
///
/// Serve para conferir centralização e largura do desenho: a largura do PNG
/// sozinha não diz onde as barras caíram dentro dele.
Future<({int inicio, int fim, int largura})> _extensaoDaTinta(
  Uint8List png,
) async {
  final codec = await ui.instantiateImageCodec(png);
  final quadro = await codec.getNextFrame();
  final imagem = quadro.image;
  final pixels = await imagem.toByteData(format: ui.ImageByteFormat.rawRgba);

  var inicio = -1;
  var fim = -1;
  for (var x = 0; x < imagem.width; x++) {
    var temTinta = false;
    for (var y = 0; y < imagem.height && !temTinta; y++) {
      final offset = (y * imagem.width + x) * 4;
      // Qualquer pixel escuro conta como barra.
      temTinta = pixels!.getUint8(offset) < 128;
    }
    if (temTinta) {
      inicio = inicio < 0 ? x : inicio;
      fim = x;
    }
  }

  final largura = imagem.width;
  imagem.dispose();
  return (inicio: inicio, fim: fim, largura: largura);
}
