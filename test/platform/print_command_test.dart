/// O protocolo entre Dart e Kotlin.
///
/// Estes testes existem porque as chaves do mapa são um contrato invisível: um
/// `double_height` que virasse `doubleHeight` não quebraria a compilação de
/// lado nenhum, e o defeito só apareceria no papel, no M10, no dia do teste.
library;

import 'package:casa_das_bicicletas/platform/printer/print_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('texto', () {
    test('leva alinhamento e os quatro atributos de formatação', () {
      const command = PrintText(
        'Total',
        align: PrintAlign.center,
        bold: true,
        underline: true,
        doubleHeight: true,
        doubleWidth: true,
      );

      expect(command.toMap(), {
        'type': 'text',
        'value': 'Total',
        'align': 'center',
        'bold': true,
        'underline': true,
        'double_height': true,
        'double_width': true,
      });
    });

    test('sem formatação, tudo é falso', () {
      final map = const PrintText('linha').toMap();

      expect(map['align'], 'left');
      expect(map['bold'], isFalse);
      expect(map['underline'], isFalse);
    });
  });

  group('código de barras', () {
    test('CODE 128 é o padrão, com texto legível abaixo', () {
      final map = const PrintBarcode('SALE-L1-7F3A9C2B').toMap();

      expect(map['type'], 'barcode');
      expect(map['data'], 'SALE-L1-7F3A9C2B');
      expect(map['symbology'], 'CODE128');
      expect(map['hri'], 'below');
    });

    test('as simbologias usam os nomes que o lado Kotlin converte', () {
      // Os inteiros do SDK (0=UPC-A ... 8=CODE128) ficam no Kotlin; aqui
      // trafega o nome, para o Dart não carregar tabela de fabricante.
      expect(
        const PrintBarcode('789123456789', symbology: BarcodeSymbology.ean13)
            .toMap()['symbology'],
        'EAN13',
      );
      expect(
        const PrintBarcode('7891234', symbology: BarcodeSymbology.ean8)
            .toMap()['symbology'],
        'EAN8',
      );
    });

    test('a posição do texto legível é enviada por nome', () {
      expect(
        const PrintBarcode('123', hri: HriPosition.none).toMap()['hri'],
        'none',
      );
    });
  });

  group('QR Code', () {
    test('leva tamanho e nível de correção', () {
      final map = const PrintQrCode('https://exemplo', size: 5, correctionLevel: 3)
          .toMap();

      expect(map['type'], 'qrcode');
      expect(map['size'], 5);
      expect(map['correction_level'], 3);
    });

    test('recusa tamanho fora da faixa documentada (1 a 6)', () {
      // Fora da faixa o SDK devolve erro genérico, difícil de diagnosticar no
      // balcão; barrar aqui aponta o defeito onde ele foi escrito.
      expect(() => PrintQrCode('x', size: 7), throwsAssertionError);
      expect(() => PrintQrCode('x', size: 0), throwsAssertionError);
    });

    test('recusa nível de correção fora da faixa (1 a 4)', () {
      expect(() => PrintQrCode('x', correctionLevel: 5), throwsAssertionError);
    });
  });

  test('imagem trafega por caminho de arquivo', () {
    expect(
      const PrintImage('/sdcard/logo.png').toMap(),
      {'type': 'image', 'path': '/sdcard/logo.png'},
    );
  });

  test('avanço e corte levam a quantidade', () {
    expect(const PrintFeed(4).toMap(), {'type': 'feed', 'lines': 4});
    expect(const PrintCut(5).toMap(), {'type': 'cut', 'advance': 5});
  });

  test('encodeCommands preserva a ordem da sequência', () {
    final encoded = encodeCommands(const [
      PrintText('a'),
      PrintQrCode('b'),
      PrintCut(),
    ]);

    expect(encoded.map((command) => command['type']), ['text', 'qrcode', 'cut']);
  });
}
