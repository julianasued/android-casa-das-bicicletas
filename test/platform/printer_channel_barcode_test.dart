/// O CODE 128 sai daqui como imagem, não como comando de código de barras.
///
/// No M10 o SDK aceita o dado, devolve sucesso e o que sai não decodifica —
/// quem dimensiona as barras é o serviço NYX. Estes testes prendem a troca no
/// lugar onde ela acontece: o que o canal envia ao lado nativo.
library;

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
    // 16 caracteres = 211 módulos: só entra com 1 ponto por módulo.
    await printer.sendCommands([const PrintBarcode('SALE-L1-7F3A9C2B')]);
    var largura =
        ByteData.sublistView(enviados.single['bytes']! as Uint8List).getUint32(16);
    expect(largura, code128Modules(16) * 1);

    // 11 caracteres = 156 módulos: cabe com 2.
    await printer.sendCommands([const PrintBarcode('L1-7F3A9C2B')]);
    largura =
        ByteData.sublistView(enviados.single['bytes']! as Uint8List).getUint32(16);
    expect(largura, code128Modules(11) * 2);

    // 8 caracteres = 123 módulos: cabe com 3.
    await printer.sendCommands([const PrintBarcode('7F3A9C2B')]);
    largura =
        ByteData.sublistView(enviados.single['bytes']! as Uint8List).getUint32(16);
    expect(largura, code128Modules(8) * 3);
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
