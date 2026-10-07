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
import '../../core/quantity.dart';
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

  /// Identificação da empresa e o que é este papel.
  ///
  /// O CNPJ e o endereço não estão no modelo visual — ele é um desenho de
  /// referência, e omite o que a nota de verdade precisa carregar: §7 da
  /// integração exige a identificação da empresa. O resto do cabeçalho segue
  /// o modelo.
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
        PrintText(
          _titleFor(document),
          align: PrintAlign.center,
          bold: true,
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

  /// Quem vendeu, para quem, qual venda e quando — no formato `Rótulo:valor`
  /// do modelo.
  ///
  /// Vendedor e cliente saem em linhas separadas, e não na mesma linha do
  /// modelo, por aritmética: dois nomes completos não cabem em 32 colunas, e
  /// cortar nome de cliente no papel que ele leva ao caixa é pior que gastar
  /// uma linha a mais.
  List<PrintCommand> _identification(PrintedDocument document) => <PrintCommand>[
        PrintText('Vendedor:${_fit(document.sellerName, reserved: 9)}'),
        PrintText(
          'Cliente:${_fit(document.customerName ?? 'nao informado', reserved: 8)}',
        ),
        // Só quando o terminal tem nome: na venda montada offline o cadastro
        // pode não ter chegado ainda, e "Terminal:" sozinho é ruído no papel.
        if (document.terminalName.isNotEmpty)
          PrintText('Terminal:${_fit(document.terminalName, reserved: 9)}'),
        PrintText('VENDA:#${document.saleId}'),
        PrintText('REF:${_fit(document.reference, reserved: 4)}'),
        PrintText(
          _row(
            'Data:${formatDate(document.saleOccurredAt)}',
            'Hora:${formatTime(document.saleOccurredAt)}',
          ),
        ),
        PrintText(_columns('ITEM', 'QTD', 'VALOR'), bold: true),
        PrintText(_divider()),
      ];

  /// Os itens em três colunas, como no modelo: nome, quantidade e total.
  ///
  /// O preço unitário só aparece quando a quantidade não é 1 — aí ele deixa de
  /// ser repetição do total e vira a conta que o cliente confere. Com nome
  /// maior que a coluna, o nome ocupa a linha inteira e a conta desce para a
  /// seguinte: o nome é o que se confere primeiro, e cortá-lo é pior que
  /// gastar linha.
  List<PrintCommand> _items(PrintedDocument document) {
    final commands = <PrintCommand>[];

    for (final item in document.items) {
      final quantidade = item.quantity.toDisplayString();
      final total = item.lineTotal.toDisplayString(symbol: false);

      if (item.productName.length <= _larguraDoItem) {
        commands.add(PrintText(_columns(item.productName, quantidade, total)));
      } else {
        commands.addAll(_wrapped(item.productName));
        commands.add(PrintText(_columns('', quantidade, total)));
      }

      if (item.quantity != const Quantity.units(1)) {
        commands.add(
          PrintText(
            '  $quantidade x ${item.unitPrice.toDisplayString(symbol: false)}',
          ),
        );
      }
    }

    if (document.hasDiscount) {
      commands.add(
        PrintText(
          _row(
            '[Desconto]',
            '-${document.discountAmount.toDisplayString(symbol: false)}',
          ),
        ),
      );
    }

    commands.add(PrintText(_divider()));
    return commands;
  }

  /// Subtotal, desconto e o total — com a forma de pagamento repetindo o valor
  /// embaixo, como no modelo.
  ///
  /// O subtotal sai sempre, mesmo sem desconto: no modelo ele é uma linha
  /// fixa, e uma nota que mostra só o total esconde a conta de quem confere.
  List<PrintCommand> _totals(PrintedDocument document) => <PrintCommand>[
        PrintText(
          _row('Sub-total', document.grossAmount.toDisplayString(symbol: false)),
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
          _row('Total', document.totalAmount.toDisplayString(symbol: false)),
          bold: true,
          doubleHeight: true,
        ),
        PrintText(
          _row(
            document.paymentMethodLabel,
            document.totalAmount.toDisplayString(symbol: false),
          ),
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

  /// O pé do papel: os dois códigos, o agradecimento e o aviso legal.
  ///
  /// O CODE 128 é o que o caixa bipa — sai como imagem, desenhada no canal
  /// (`printer_channel.dart`), porque pelo SDK ele não decodifica neste
  /// aparelho. O QR vai pelo SDK mesmo, que aqui funciona: conferido no M10 em
  /// 10/09/2026 (§ "Como cada símbolo ficou" do checklist). Ele carrega o
  /// mesmo código da venda — é o mesmo dado em outra forma, para quem tiver
  /// celular na mão e não leitor.
  List<PrintCommand> _footer(PrintedDocument document) => <PrintCommand>[
        PrintBarcode(document.saleBarcode),
        PrintText(document.saleBarcode, align: PrintAlign.center),
        PrintText(_divider()),
        const PrintText(
          'OBRIGADO! VOLTE SEMPRE!',
          align: PrintAlign.center,
          bold: true,
        ),
        ..._wrapped(document.notice, align: PrintAlign.center),
        PrintQrCode(document.saleBarcode, align: PrintAlign.center),
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

  /// Largura das colunas QTD e VALOR; o que sobra é do nome do item.
  static const int _larguraDaQuantidade = 3;
  static const int _larguraDoValor = 10;

  int get _larguraDoItem =>
      columns - _larguraDaQuantidade - _larguraDoValor - 2;

  /// As três colunas do modelo — ITEM, QTD e VALOR — alinhadas na mesma
  /// medida do cabeçalho até a última linha.
  String _columns(String item, String quantidade, String valor) =>
      '${item.padRight(_larguraDoItem).substring(0, _larguraDoItem)} '
      '${quantidade.padLeft(_larguraDaQuantidade)} '
      '${valor.padLeft(_larguraDoValor)}';

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
