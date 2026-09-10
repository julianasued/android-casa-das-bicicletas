/// O que se pode conferir do código de barras sem o aparelho.
///
/// A leitura em si é do papel — nenhum teste aqui prova que um leitor
/// decodifica. O que dá para travar é a aritmética que decide se o dado cabe na
/// linha, que é onde o formato do código de venda encosta no limite físico do
/// papel de 58 mm.
library;

import 'package:casa_das_bicicletas/platform/printer/barcode_bitmap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('code128Modules', () {
    test('conta 11 módulos por caractere, mais start, checksum, stop e final',
        () {
      // 11 * (6 + 3) + 2
      expect(code128Modules(6), 101);
      expect(code128Modules(8), 123);
      expect(code128Modules(11), 156);
      expect(code128Modules(16), 211);
    });
  });

  group('code128Fits', () {
    test('o formato atual do código de venda não cabe com módulo de 2 pontos',
        () {
      // 211 módulos * 2 = 422, contra 384 úteis. É o motivo de o código não
      // poder simplesmente ser desenhado maior.
      expect(code128Fits('SALE-L1-7F3A9C2B'), isFalse);
    });

    test('o mesmo dado cabe com módulo de 1 ponto', () {
      expect(code128Fits('SALE-L1-7F3A9C2B', modulePoints: 1), isTrue);
    });

    test('sem o prefixo SALE- cabe com folga no módulo de 2', () {
      // 156 * 2 = 312, contra 384.
      expect(code128Fits('L1-7F3A9C2B'), isTrue);
    });

    test('catorze caracteres é o limite prático do módulo de 2', () {
      expect(code128Fits('A' * 14), isTrue);
      expect(code128Fits('A' * 15), isFalse);
    });
  });

  group('code128Png', () {
    test('desenha na largura exata que a conta de módulos previu', () async {
      final png = await code128Png('ABC123');

      // PNG guarda largura e altura em big-endian nos bytes 16..23.
      final bytes = png.buffer.asByteData();
      expect(bytes.getUint32(16), code128Modules(6) * defaultModulePoints);
      expect(bytes.getUint32(20), defaultBarHeightDots);
    });

    test('o módulo multiplica a largura sem mexer na altura', () async {
      final estreito = await code128Png('ABC123', modulePoints: 1);
      final largo = await code128Png('ABC123', modulePoints: 3);

      final larguraEstreita = estreito.buffer.asByteData().getUint32(16);
      final larguraLarga = largo.buffer.asByteData().getUint32(16);

      expect(larguraLarga, larguraEstreita * 3);
      expect(largo.buffer.asByteData().getUint32(20), defaultBarHeightDots);
    });

    test('sai um PNG de verdade', () async {
      final png = await code128Png('ABC123');
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });
}
