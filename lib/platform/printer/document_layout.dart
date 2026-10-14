/// Montagem dos documentos 1 e 2 para a impressora térmica de 2".
///
/// O conteúdo obrigatório está nos §7 e §8 da especificação de integração com o
/// M10 Pro; o que este arquivo decide é a **forma**: onde quebra a linha, o que
/// fica à esquerda e o que fica à direita, o que é destaque. A forma segue o
/// modelo das duas vias — nota de conferência e comprovante de retirada —,
/// desenhado para 80 mm e aqui trazido para as 32 colunas desta bobina.
///
/// É código puro de propósito — entra um `PrintedDocument`, saem comandos. Sem
/// impressora, sem canal, sem Flutter: o layout do papel que o cliente leva ao
/// caixa é testável em memória, e é o único jeito de saber que ele não vai sair
/// cortado pela largura de 32 colunas.
library;

import '../../core/formatters.dart';
import '../../domain/entities/printed_document.dart';
import 'print_command.dart';

/// Colunas da bobina de 2" na fonte padrão do M10 Pro.
const int paperColumns = 32;

class DocumentLayout {
  const DocumentLayout({this.columns = paperColumns});

  final int columns;

  List<PrintCommand> build(PrintedDocument document) => switch (document.type) {
        DocumentType.doc1 => <PrintCommand>[
            ..._header(document),
            ..._identification(document),
            ..._items(document),
            ..._totals(document),
            ..._barcode(document),
            ..._closing(),
          ],
        DocumentType.doc2 => <PrintCommand>[
            ..._header(document),
            ..._release(document),
            ..._barcode(document),
            ..._handover(),
            ..._closing(),
          ],
      };

  /// Página de teste da instalação — confere bobina, alinhamento e código.
  List<PrintCommand> buildTestPage({required String terminalName}) => <PrintCommand>[
        const PrintText('CASA DAS BICICLETAS', align: PrintAlign.center, bold: true),
        PrintText(_divider()),
        const PrintText('TESTE DE IMPRESSAO', align: PrintAlign.center),
        PrintText(_divider()),
        PrintText('Terminal: $terminalName'),
        PrintText('Em: ${formatDateTime(DateTime.now())}'),
        PrintText(_divider()),
        const PrintText('Negrito', bold: true),
        const PrintText('Sublinhado', underline: true),
        const PrintText('Altura dupla', doubleHeight: true),
        const PrintText('Largura dupla', doubleWidth: true),
        PrintText(_divider()),
        const PrintText('CODE 128:', align: PrintAlign.center),
        const PrintBarcode('SALE-L0-00000000'),
        const PrintText('QR Code:', align: PrintAlign.center),
        const PrintQrCode('CASA-DAS-BICICLETAS-TESTE'),
        PrintText(_divider()),
        const PrintText('Se este papel saiu inteiro e os', align: PrintAlign.center),
        const PrintText('codigos acima sao legiveis, a', align: PrintAlign.center),
        const PrintText('impressora esta operacional.', align: PrintAlign.center),
        const PrintFeed(2),
        const PrintCut(),
      ];

  // -------------------------------------------------------------------------
  // Blocos
  // -------------------------------------------------------------------------

  /// O logo e o que é este papel.
  ///
  /// A identificação da empresa que o §7 da integração exige é o logo. CNPJ e
  /// endereço saíram: as duas vias são comprovante interno, e é isso que o pé
  /// do papel diz.
  ///
  /// A 1ª via é a nota de conferência, que o cliente leva ao caixa; a 2ª é o
  /// comprovante de retirada, que o caixa emite e o cliente entrega ao
  /// vendedor. "Via" aqui é o papel do fluxo — a reimpressão tem marca própria,
  /// para as duas coisas não se confundirem.
  List<PrintCommand> _header(PrintedDocument document) {
    final conferencia = document.type == DocumentType.doc1;

    return <PrintCommand>[
      PrintLogo(
        fallback: document.storeName.toUpperCase(),
        size: conferencia ? LogoSize.regular : LogoSize.small,
      ),
      PrintText(_divider('=')),
      PrintText(
        conferencia ? 'NOTA DE CONFERÊNCIA' : 'COMPROVANTE DE RETIRADA',
        align: PrintAlign.center,
        bold: true,
        // Só a nota de conferência ganha corpo alto: a de retirada é curta de
        // propósito, e o destaque dela é a faixa "MERCADORIA LIBERADA".
        doubleHeight: conferencia,
      ),
      PrintText(
        conferencia ? '1ª VIA' : '2ª VIA',
        align: PrintAlign.center,
        bold: true,
        doubleHeight: conferencia,
      ),
      if (document.isReprint)
        PrintText(
          '** REIMPRESSÃO ${document.sequence} **',
          align: PrintAlign.center,
          bold: true,
        ),
      PrintText(_divider('=')),
      if (conferencia) const PrintBanner('LEVE AO CAIXA PARA PAGAMENTO'),
    ];
  }

  /// Qual venda, quando e quem vendeu — rótulo à esquerda, valor à direita.
  ///
  /// Cliente e forma de pagamento não estão no modelo da nota, mas ficam: a
  /// forma de pagamento é exigência do §7 da integração, e na notinha o nome
  /// do cliente é o que o caixa confere antes de liberar. O cliente só sai
  /// quando existe.
  List<PrintCommand> _identification(PrintedDocument document) => <PrintCommand>[
        PrintText(_row('Venda', document.saleBarcode)),
        PrintText(_row('Data', formatDate(document.saleOccurredAt))),
        PrintText(_row('Hora', formatTime(document.saleOccurredAt))),
        PrintText(_labeled('Vendedor', document.sellerName)),
        if (document.customerName != null)
          PrintText(_labeled('Cliente', document.customerName!)),
        PrintText(_labeled('Pagamento', document.paymentMethodLabel)),
        PrintText(_divider()),
        PrintText(_row('DESCRIÇÃO', 'TOTAL'), bold: true),
        const PrintText('  QTD x UNITÁRIO', bold: true),
        PrintText(_divider()),
      ];

  /// Os itens: o nome numa linha, a conta na seguinte.
  ///
  /// Tentar espremer nome, quantidade, unitário e total em 32 colunas corta
  /// justamente o nome do produto, que é o que se confere primeiro.
  List<PrintCommand> _items(PrintedDocument document) => <PrintCommand>[
        for (final item in document.items) ...[
          ..._wrapped(item.productName),
          PrintText(
            _row(
              '  ${item.quantity.toDisplayString()} x '
                  '${item.unitPrice.toDisplayString(symbol: false)}',
              item.lineTotal.toDisplayString(symbol: false),
            ),
          ),
        ],
        PrintText(_divider()),
      ];

  /// Subtotal, desconto e o total a pagar em destaque.
  ///
  /// O subtotal sai sempre, mesmo sem desconto: uma nota que mostra só o total
  /// esconde a conta de quem confere.
  List<PrintCommand> _totals(PrintedDocument document) => <PrintCommand>[
        PrintText(
          _row('Subtotal', document.grossAmount.toDisplayString(symbol: false)),
        ),
        if (document.hasDiscount)
          PrintText(
            _row(
              'Desconto',
              '-${document.discountAmount.toDisplayString(symbol: false)}',
            ),
          ),
        PrintText(_divider()),
        PrintText(
          _row('TOTAL A PAGAR', document.totalAmount.toDisplayString()),
          bold: true,
          doubleHeight: true,
        ),
        PrintText(_divider()),
      ];

  /// O miolo da 2ª via: qual venda, de quem, quanto — e que está liberada.
  ///
  /// Sem itens de propósito: quem confere a mercadoria é o vendedor, com a
  /// venda na mão, e este papel só precisa dizer que o caixa liberou. A
  /// referência do documento fica porque é ela que a devolução pede (13.4), e
  /// a data porque o §8 da integração exige.
  List<PrintCommand> _release(PrintedDocument document) => <PrintCommand>[
        const PrintText('VENDA', align: PrintAlign.center),
        PrintText(
          document.saleBarcode,
          align: PrintAlign.center,
          bold: true,
          doubleHeight: true,
        ),
        PrintText(_labeled('Ref.', document.reference)),
        PrintText(
          _row(
            'Emitido em',
            formatDateTime(document.confirmedAt ?? document.printedAt),
          ),
        ),
        PrintText(_labeled('Vendedor', document.sellerName)),
        PrintText(
          _row('Total da venda', document.totalAmount.toDisplayString()),
          bold: true,
        ),
        const PrintBanner('MERCADORIA LIBERADA', large: true),
      ];

  /// O código da venda, para o leitor e para quem precisar digitar.
  ///
  /// O CODE 128 sai como imagem, desenhada no canal (`printer_channel.dart`),
  /// porque pelo SDK ele não decodifica neste aparelho. O texto vai embaixo
  /// porque a imagem não tem legenda: quando o leitor falha, alguém digita.
  List<PrintCommand> _barcode(PrintedDocument document) => <PrintCommand>[
        PrintBarcode(document.saleBarcode),
        PrintText(document.saleBarcode, align: PrintAlign.center),
      ];

  /// O que fazer com a 2ª via.
  List<PrintCommand> _handover() => <PrintCommand>[
        PrintText(_divider()),
        const PrintText(
          'ENTREGUE ESTA VIA AO VENDEDOR',
          align: PrintAlign.center,
          bold: true,
        ),
        const PrintText(
          'PARA RETIRAR A MERCADORIA',
          align: PrintAlign.center,
          bold: true,
        ),
        PrintText(_divider()),
      ];

  /// O pé das duas vias, e o corte.
  List<PrintCommand> _closing() => const <PrintCommand>[
        PrintFeed(),
        PrintText('Comprovante interno.', align: PrintAlign.center),
        PrintText('Não possui valor fiscal.', align: PrintAlign.center),
        PrintFeed(2),
        PrintCut(),
      ];

  // -------------------------------------------------------------------------
  // Utilidades de largura
  // -------------------------------------------------------------------------

  String _divider([String character = '-']) => character * columns;

  /// Rótulo à esquerda, valor à direita, preenchendo o meio com espaços.
  String _row(String left, String right) {
    final space = columns - left.length - right.length;
    if (space <= 0) {
      // Não cabe: o valor é o que não pode ser cortado, então o rótulo cede.
      final available = columns - right.length - 1;
      final trimmed = available > 0 ? left.substring(0, available) : '';
      return '$trimmed $right';
    }
    return '$left${' ' * space}$right';
  }

  /// Rótulo e um valor de texto livre — nome, referência —, que é quem cede
  /// quando os dois não cabem: nome cortado ainda identifica, linha estourada
  /// desalinha o papel inteiro.
  String _labeled(String label, String value) {
    final available = columns - label.length - 1;
    return _row(
      label,
      value.length <= available ? value : value.substring(0, available),
    );
  }

  /// Quebra o texto na largura da bobina, sem partir palavra no meio.
  List<PrintCommand> _wrapped(String text, {PrintAlign align = PrintAlign.left}) {
    if (text.isEmpty) return const <PrintCommand>[];

    final lines = <String>[];
    var current = StringBuffer();

    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;

      if (current.isEmpty) {
        current.write(word.length <= columns ? word : word.substring(0, columns));
        continue;
      }
      if (current.length + 1 + word.length <= columns) {
        current.write(' $word');
        continue;
      }
      lines.add(current.toString());
      current = StringBuffer(word.length <= columns ? word : word.substring(0, columns));
    }
    if (current.isNotEmpty) lines.add(current.toString());

    return [for (final line in lines) PrintText(line, align: align)];
  }
}

/// Texto do documento como sairia no papel — usado no teste e na pré-visualização.
String renderCommandsAsText(List<PrintCommand> commands, {int columns = paperColumns}) {
  final buffer = StringBuffer();

  for (final command in commands) {
    switch (command) {
      case PrintText(:final value, :final align):
        buffer.writeln(switch (align) {
          PrintAlign.left => value,
          PrintAlign.center => _centered(value, columns),
          PrintAlign.right => value.padLeft(columns),
        });
      case PrintBarcode(:final data, :final symbology):
        buffer.writeln(_centered('[${symbology.code}: $data]', columns));
      case PrintQrCode(:final data):
        buffer.writeln(_centered('[QR: $data]', columns));
      case PrintLogo():
        buffer.writeln(_centered('[LOGO]', columns));
      case PrintBanner(:final text):
        buffer.writeln(_centered(text, columns));
      case PrintImage(:final path):
        buffer.writeln(_centered('[IMG: $path]', columns));
      case PrintImageBytes(:final label):
        // O que interessa na prévia é o dado que virou desenho, não o bitmap.
        buffer.writeln(_centered('[${label ?? 'IMG'}]', columns));
      case PrintFeed(:final lines):
        buffer.write('\n' * lines);
      case PrintCut():
        buffer.writeln('-' * columns);
    }
  }
  return buffer.toString();
}

String _centered(String value, int columns) {
  if (value.length >= columns) return value;
  final padding = (columns - value.length) ~/ 2;
  return '${' ' * padding}$value';
}
