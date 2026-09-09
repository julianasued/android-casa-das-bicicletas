/// Montagem dos documentos 1 e 2 para a impressora térmica de 2".
///
/// O conteúdo obrigatório está nos §7 e §8 da especificação de integração com o
/// M10 Pro; o que este arquivo decide é a **forma**: onde quebra a linha, o que
/// fica à esquerda e o que fica à direita, o que é destaque.
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

  List<PrintCommand> build(PrintedDocument document) => <PrintCommand>[
        ..._header(document),
        ..._identification(document),
        ..._items(document),
        ..._totals(document),
        ..._confirmation(document),
        ..._footer(document),
      ];

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

  List<PrintCommand> _header(PrintedDocument document) => <PrintCommand>[
        PrintText(
          document.storeName.toUpperCase(),
          align: PrintAlign.center,
          bold: true,
        ),
        if (document.storeDocument.isNotEmpty)
          PrintText(
            'CNPJ ${formatDocument(document.storeDocument)}',
            align: PrintAlign.center,
          ),
        if (document.storeAddress.isNotEmpty)
          ..._wrapped(document.storeAddress, align: PrintAlign.center),
        PrintText('Loja ${document.storeCode}', align: PrintAlign.center),
        PrintText(_divider()),
        PrintText(
          _titleFor(document),
          align: PrintAlign.center,
          bold: true,
          doubleHeight: true,
        ),
        if (document.isReprint)
          PrintText(
            '** ${document.sequence}a VIA - REIMPRESSAO **',
            align: PrintAlign.center,
            bold: true,
          ),
        PrintText(_divider()),
      ];

  String _titleFor(PrintedDocument document) => switch (document.type) {
        DocumentType.doc1 => 'ENCAMINHAMENTO AO CAIXA',
        DocumentType.doc2 => 'DOCUMENTO DE RETIRADA',
      };

  List<PrintCommand> _identification(PrintedDocument document) => <PrintCommand>[
        PrintText(_row('Venda', '#${document.saleId}')),
        PrintText(_row('Documento', document.reference)),
        PrintText(_row('Data', formatDateTime(document.saleOccurredAt))),
        PrintText(_row('Vendedor', _fit(document.sellerName))),
        PrintText(_row('Terminal', _fit(document.terminalName))),
        if (document.customerName != null)
          PrintText(_row('Cliente', _fit(document.customerName!))),
        PrintText(_row('Pagamento', document.paymentMethodLabel)),
        PrintText(_divider()),
      ];

  /// Cada item ocupa duas linhas: descrição em uma, conta e total na outra.
  ///
  /// Numa bobina de 32 colunas não cabe "nome + quantidade + unitário + total"
  /// em uma linha só sem cortar o nome do produto — e o nome é o que o cliente
  /// confere.
  List<PrintCommand> _items(PrintedDocument document) {
    final commands = <PrintCommand>[];

    for (final item in document.items) {
      commands.addAll(_wrapped(item.productName));
      commands.add(
        PrintText(
          _row(
            '  ${item.quantity.toDisplayString()} x ${item.unitPrice.toDisplayString(symbol: false)}',
            item.lineTotal.toDisplayString(symbol: false),
          ),
        ),
      );
    }

    commands.add(PrintText(_divider()));
    return commands;
  }

  List<PrintCommand> _totals(PrintedDocument document) => <PrintCommand>[
        if (document.hasDiscount) ...[
          PrintText(_row('Subtotal', document.grossAmount.toDisplayString(symbol: false))),
          PrintText(
            _row('Desconto', '-${document.discountAmount.toDisplayString(symbol: false)}'),
          ),
        ],
        PrintText(
          _row('TOTAL', document.totalAmount.toDisplayString(symbol: false)),
          bold: true,
          doubleHeight: true,
        ),
        PrintText(_divider()),
      ];

  /// Só no documento 2: o que o caixa recebeu, de quem e quando (RF11/RF12).
  List<PrintCommand> _confirmation(PrintedDocument document) {
    if (document.type != DocumentType.doc2) return const <PrintCommand>[];

    return <PrintCommand>[
      const PrintText('PAGAMENTO CONFIRMADO', align: PrintAlign.center, bold: true),
      if (document.confirmedAt != null)
        PrintText(_row('Confirmado em', formatDateTime(document.confirmedAt!))),
      if (document.cashierName != null)
        PrintText(_row('Caixa', _fit(document.cashierName!))),
      for (final payment in document.payments)
        PrintText(
          _row(
            '  ${payment.paymentMethodLabel}',
            payment.amount.toDisplayString(symbol: false),
          ),
        ),
      PrintText(_divider()),
    ];
  }

  List<PrintCommand> _footer(PrintedDocument document) => <PrintCommand>[
        PrintBarcode(document.saleBarcode),
        PrintText(document.saleBarcode, align: PrintAlign.center),
        PrintText(_divider()),
        ..._wrapped(document.notice, align: PrintAlign.center),
        PrintText(
          'Impresso ${formatDateTime(document.printedAt)}',
          align: PrintAlign.center,
        ),
        if (document.printedByName.isNotEmpty)
          PrintText('por ${document.printedByName}', align: PrintAlign.center),
        const PrintFeed(2),
        const PrintCut(),
      ];

  // -------------------------------------------------------------------------
  // Utilidades de largura
  // -------------------------------------------------------------------------

  String _divider() => '-' * columns;

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

  /// Corta um valor que não pode empurrar a linha para fora da bobina.
  String _fit(String value, {int reserved = 12}) {
    final available = columns - reserved;
    if (value.length <= available) return value;
    return value.substring(0, available);
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
      case PrintImage(:final path):
        buffer.writeln(_centered('[IMG: $path]', columns));
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
