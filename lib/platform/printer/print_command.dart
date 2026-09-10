/// Comandos que o canal nativo sabe executar.
///
/// A camada Dart não fala ESC/POS nem chama o SDK da Elgin: ela descreve o
/// documento como uma sequência de comandos, e o lado Kotlin traduz para as
/// funções `ImpressaoTexto`, `ImpressaoCodigoBarras`, `ImpressaoQRCode`,
/// `ImprimeImagem`, `AvancaPapel` e `Corte`. É essa fronteira que permite
/// trocar o modelo de impressora sem reescrever o documento — e testar o
/// documento sem impressora nenhuma.
///
/// Os parâmetros aqui são intenções ("centralizado", "negrito", "EAN-13"); os
/// inteiros que o SDK espera ficam do lado Kotlin, em um lugar só.
library;

import 'dart:typed_data';

enum PrintAlign { left, center, right }

/// Simbologias que `ImpressaoCodigoBarras` aceita, pelos nomes da documentação.
///
/// O comprimento aceito é do SDK e está anotado para quem for escolher: mandar
/// 13 dígitos num EAN-8 é erro de dado, não de impressora.
enum BarcodeSymbology {
  upcA('UPCA', 'UPC-A (11–12 dígitos)'),
  upcE('UPCE', 'UPC-E (6–12 dígitos)'),
  ean13('EAN13', 'EAN-13 (12–13 dígitos)'),
  ean8('EAN8', 'EAN-8 (7–8 dígitos)'),
  code39('CODE39', 'CODE 39'),
  itf('ITF', 'ITF (par de dígitos)'),
  codebar('CODEBAR', 'CODEBAR'),
  code93('CODE93', 'CODE 93'),
  code128('CODE128', 'CODE 128');

  const BarcodeSymbology(this.code, this.label);

  /// Nome enviado ao canal; o Kotlin converte no inteiro do SDK.
  final String code;
  final String label;
}

/// Posição do texto legível em relação ao código de barras (`HRI`).
enum HriPosition {
  above('above'),
  below('below'),
  both('both'),
  none('none');

  const HriPosition(this.code);

  final String code;
}

sealed class PrintCommand {
  const PrintCommand();

  /// Forma serializável para atravessar o `MethodChannel`.
  Map<String, Object?> toMap();
}

class PrintText extends PrintCommand {
  const PrintText(
    this.value, {
    this.align = PrintAlign.left,
    this.bold = false,
    this.underline = false,
    this.doubleHeight = false,
    this.doubleWidth = false,
  });

  final String value;
  final PrintAlign align;
  final bool bold;
  final bool underline;
  final bool doubleHeight;
  final bool doubleWidth;

  @override
  Map<String, Object?> toMap() => {
        'type': 'text',
        'value': value,
        'align': align.name,
        'bold': bold,
        'underline': underline,
        'double_height': doubleHeight,
        'double_width': doubleWidth,
      };
}

/// Código de barras da venda (RF08) — o que o caixa vai ler (RF09).
class PrintBarcode extends PrintCommand {
  const PrintBarcode(
    this.data, {
    this.symbology = BarcodeSymbology.code128,
    this.height = 60,
    this.width = 2,
    this.hri = HriPosition.below,
  });

  final String data;
  final BarcodeSymbology symbology;
  final int height;
  final int width;
  final HriPosition hri;

  @override
  Map<String, Object?> toMap() => {
        'type': 'barcode',
        'data': data,
        'symbology': symbology.code,
        'height': height,
        'width': width,
        'hri': hri.code,
      };
}

/// `ImpressaoQRCode(dados, tamanho, nivelCorrecao)`.
///
/// `size` vai de 1 a 6 e `correctionLevel` de 1 a 4 (7%, 15%, 25%, 30%),
/// conforme a documentação do SDK. Os limites são conferidos aqui porque um
/// valor fora da faixa volta do SDK como erro genérico, difícil de diagnosticar
/// no balcão.
class PrintQrCode extends PrintCommand {
  const PrintQrCode(
    this.data, {
    this.size = 4,
    this.correctionLevel = 2,
  })  : assert(size >= 1 && size <= 6, 'tamanho do QR Code vai de 1 a 6'),
        assert(
          correctionLevel >= 1 && correctionLevel <= 4,
          'nível de correção do QR Code vai de 1 a 4',
        );

  final String data;
  final int size;
  final int correctionLevel;

  @override
  Map<String, Object?> toMap() => {
        'type': 'qrcode',
        'data': data,
        'size': size,
        'correction_level': correctionLevel,
      };
}

/// Imagem por caminho de arquivo, como `ImprimeImagem` espera.
class PrintImage extends PrintCommand {
  const PrintImage(this.path);

  final String path;

  @override
  Map<String, Object?> toMap() => {'type': 'image', 'path': path};
}

/// Imagem já em memória, sem passar por arquivo.
///
/// É assim que o código de barras chega à impressora neste terminal. O E1
/// aceita o dado e devolve sucesso, mas quem dimensiona as barras no M10 é o
/// serviço NYX, e o que sai não decodifica — no aparelho, só até seis
/// caracteres. Desenhado por nós, cada módulo ocupa um número inteiro de
/// pontos e as proporções ficam exatas. Ver `barcode_bitmap.dart`.
///
/// Sem arquivo temporário de propósito: o bitmap nasce, imprime e morre no
/// mesmo caminho, e arquivo a mais no terminal é coisa a mais para sobrar
/// quando a impressão falha no meio.
class PrintImageBytes extends PrintCommand {
  const PrintImageBytes(this.bytes, {this.label});

  final Uint8List bytes;

  /// O que a imagem representa, para quem lê um teste ou um log. Nunca vai
  /// para o papel.
  final String? label;

  @override
  Map<String, Object?> toMap() => {'type': 'image_bytes', 'bytes': bytes};
}

class PrintFeed extends PrintCommand {
  const PrintFeed([this.lines = 1]);

  final int lines;

  @override
  Map<String, Object?> toMap() => {'type': 'feed', 'lines': lines};
}

/// Corte parcial do papel (`Corte`), avançando antes o número de linhas dado.
///
/// Se o M10 não tiver guilhotina, o efeito é o avanço — que é justamente o que
/// o operador precisa para destacar na serrilha.
class PrintCut extends PrintCommand {
  const PrintCut([this.advance = 3]);

  final int advance;

  @override
  Map<String, Object?> toMap() => {'type': 'cut', 'advance': advance};
}

List<Map<String, Object?>> encodeCommands(List<PrintCommand> commands) =>
    [for (final command in commands) command.toMap()];
