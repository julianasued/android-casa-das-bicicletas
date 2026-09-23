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

/// Lado de um módulo do QR, em pontos. Oito pontos deixam um QR de ~25 mm
/// para o código de venda, que qualquer câmera de celular lê de perto.
const int defaultQrModulePoints = 8;

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
/// [lineDots], quando informado e maior que o código, centraliza as barras
/// numa faixa dessa largura. É como o código sai centralizado no papel: o
/// `ImprimeImagem` do SDK não recebe alinhamento nenhum, e o que ele imprime
/// encosta na margem esquerda. Pintar a folga dentro da própria imagem resolve
/// sem depender de o SDK colaborar — e de graça vem a zona de silêncio que o
/// CODE 128 precisa nas duas pontas para decodificar com folga.
Future<Uint8List> code128Png(
  String data, {
  int modulePoints = defaultModulePoints,
  int barHeightDots = defaultBarHeightDots,
  int? lineDots,
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

  final larguraDoCodigo = code128Modules(data.length) * modulePoints;

  // Não encolhe nem recorta: se o código for mais largo que a linha, ele sai
  // no tamanho que tem, e quem escolhe o módulo é que precisa caber.
  final larguraTotal = (lineDots != null && lineDots > larguraDoCodigo)
      ? lineDots
      : larguraDoCodigo;
  final margem = (larguraTotal - larguraDoCodigo) ~/ 2;

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
    final inicio = margem + (barra.left * modulePoints).round();
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

/// Desenha [data] em QR Code e devolve o PNG.
///
/// O SDK tem `ImpressaoQRCode` e ele **funciona** neste aparelho (conferido em
/// 10/09/2026, § "Como cada símbolo ficou" do checklist) — o que ele não tem é
/// alinhamento: nem o QR nem a imagem recebem posição, e o que sai encosta na
/// margem esquerda. Desenhado aqui, o QR vem centralizado dentro da própria
/// imagem, que é o único jeito de centralizar sem depender do `DefinePosicao`
/// — da mesma família que já falhou neste terminal (`DefineDensidade` ignorado,
/// `DefineLarguraBobina` respondendo -3).
///
/// Serve também à tela de comprovante, que precisa do QR como imagem e não
/// fala com hardware nenhum: é a mesma conta, num lugar só.
Future<Uint8List> qrCodePng(
  String data, {
  int modulePoints = defaultQrModulePoints,
  int? lineDots,
}) async {
  // O tamanho sai do próprio código: `make` recebe a caixa e devolve os
  // módulos já posicionados dentro dela, então basta pedir uma caixa múltipla
  // do módulo para cada módulo cair em ponto inteiro.
  final matriz = Barcode.qrCode().make(
    data,
    width: 100,
    height: 100,
    drawText: false,
  );
  final colunas = _modulosPorLinha(matriz);
  final ladoDoCodigo = colunas * modulePoints;

  final lado = (lineDots != null && lineDots > ladoDoCodigo)
      ? lineDots
      : ladoDoCodigo;
  final margem = (lado - ladoDoCodigo) ~/ 2;

  final gravador = ui.PictureRecorder();
  final canvas = ui.Canvas(gravador);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, lado.toDouble(), ladoDoCodigo.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  final tinta = ui.Paint()..color = const ui.Color(0xFF000000);
  for (final modulo in Barcode.qrCode()
      .make(
        data,
        width: ladoDoCodigo.toDouble(),
        height: ladoDoCodigo.toDouble(),
        drawText: false,
      )
      .whereType<BarcodeBar>()
      .where((modulo) => modulo.black)) {
    canvas.drawRect(
      ui.Rect.fromLTWH(
        margem + modulo.left,
        modulo.top,
        modulo.width,
        modulo.height,
      ),
      tinta,
    );
  }

  final imagem =
      await gravador.endRecording().toImage(lado, ladoDoCodigo);
  final png = await imagem.toByteData(format: ui.ImageByteFormat.png);
  imagem.dispose();

  return png!.buffer.asUint8List();
}

/// Quantos módulos o QR tem por linha, contados no desenho que o pacote
/// devolve — a versão do código depende do dado, e não há como saber antes.
int _modulosPorLinha(Iterable<BarcodeElement> matriz) {
  final barras = matriz.whereType<BarcodeBar>().toList();
  if (barras.isEmpty) return 0;

  // Todos os módulos da primeira linha têm a mesma altura; a largura da caixa
  // dividida pela do módulo dá a contagem.
  final altura = barras.first.height;
  return altura <= 0 ? 0 : (100 / altura).round();
}
