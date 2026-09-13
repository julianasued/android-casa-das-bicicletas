/// Código de barras desenhado por nós, e não pelo SDK.
///
/// O E1 aceita o dado e devolve sucesso, mas no M10 quem dimensiona as barras é
/// o serviço NYX, e o resultado não decodifica: no aparelho, o CODE 128 do
/// código de venda só foi lido até seis caracteres. As duas alavancas que o SDK
/// oferece não valem aqui — `DefineDensidade` escreve um `ESC 7` que o serviço
/// ignora, e `DefineLarguraBobina` responde -3, porque o SDK não tem registro
/// de hardware para este terminal.
///
/// Desenhando o bitmap, cada módulo ocupa um número inteiro de pontos e as
/// proporções ficam exatas — que é justamente o que se perde quando alguém
/// arredonda barra a barra. A impressora recebe uma imagem e não reinterpreta
/// nada.
///
/// O tamanho continua sendo física, não software: o papel de 58 mm tem 384
/// pontos úteis, então com [modulePoints] igual a 2 cabem cerca de catorze
/// caracteres. Ver `docs/checklist_teste_m10.md`.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';

/// Pontos úteis na linha do papel de 58 mm a 203 dpi.
const int paperDots = 384;

/// Largura de um módulo, em pontos. Dois pontos são 0,25 mm — o mínimo que se
/// lê com alguma folga; um ponto cabe mais dado, mas fica no limite do leitor.
const int defaultModulePoints = 2;

/// Altura das barras, em pontos. 120 pontos são cerca de 15 mm.
const int defaultBarHeightDots = 120;

/// Quantos módulos um CODE 128 gasta para [characters] caracteres.
///
/// São 11 por caractere, mais start, checksum e stop, mais os 2 pontos da
/// barra final. Serve para saber se o dado cabe antes de tentar desenhá-lo.
int code128Modules(int characters) => 11 * (characters + 3) + 2;

/// Se o dado cabe na linha com esta largura de módulo.
bool code128Fits(String data, {int modulePoints = defaultModulePoints}) =>
    code128Modules(data.length) * modulePoints <= paperDots;

/// Desenha [data] em CODE 128 e devolve o PNG.
///
/// [modulePoints] é a largura da barra mais fina. Aumentar melhora a leitura e
/// gasta linha; o dado que não couber estoura [paperDots] e o desenho sai
/// cortado, então confira antes com [code128Fits].
Future<Uint8List> code128Png(
  String data, {
  int modulePoints = defaultModulePoints,
  int barHeightDots = defaultBarHeightDots,
}) async {
  final barras = Barcode.code128()
      .make(
        data,
        width: code128Modules(data.length).toDouble(),
        height: barHeightDots.toDouble(),
        drawText: false,
      )
      .whereType<BarcodeBar>()
      .where((barra) => barra.black);

  final larguraTotal = code128Modules(data.length) * modulePoints;

  final gravador = ui.PictureRecorder();
  final canvas = ui.Canvas(gravador);

  // Fundo branco: o papel térmico não é o fundo da imagem, e sem isto o que
  // não for barra sai preto.
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, larguraTotal.toDouble(), barHeightDots.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  final tinta = ui.Paint()..color = const ui.Color(0xFF000000);
  for (final barra in barras) {
    // Arredondar aqui, e uma vez só, é o ponto de tudo isto: cada barra começa
    // e termina em ponto inteiro, então nenhuma engorda ou emagrece.
    final inicio = (barra.left * modulePoints).round();
    final largura = (barra.width * modulePoints).round();

    canvas.drawRect(
      ui.Rect.fromLTWH(
        inicio.toDouble(),
        0,
        largura.toDouble(),
        barHeightDots.toDouble(),
      ),
      tinta,
    );
  }

  final imagem = await gravador
      .endRecording()
      .toImage(larguraTotal, barHeightDots);
  final png = await imagem.toByteData(format: ui.ImageByteFormat.png);
  imagem.dispose();

  return png!.buffer.asUint8List();
}
