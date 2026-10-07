/// Comprovante da venda, no visual do papel térmico (§7 da integração com o
/// M10 Pro).
///
/// A impressora recebe o documento como comandos ESC/POS
/// (`DocumentLayout`/`PrinterChannel`) — isto aqui não participa dessa
/// impressão nem muda o que sai no papel. É a mesma informação, desenhada na
/// tela: fonte monoespaçada, preto e branco, linhas pontilhadas separando as
/// seções, código de barras e QR ao final — para conferir o comprovante sem
/// depender do papel em mãos, com a referência visual de
/// `fluxo-frontend/handoff/PDV Elgin M10 Pro - Nota Modelo.dc.html`.
///
/// Todo dado vem de [PrintedDocument]: o mesmo objeto que o servidor devolveu
/// e que a impressora já usou (ou vai usar, na reimpressão). Nada é inventado
/// aqui — o aviso legal no rodapé é `document.notice`, o texto que também sai
/// no papel; não há "avalie o atendimento" nem outro recurso que o aplicativo
/// não tenha.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/entities/sale.dart';
import '../../platform/printer/barcode_bitmap.dart'
    show code128Png, qrCodePng;

/// Larguras das colunas ITEM/QTD/VALOR.
///
/// Mais folgadas que os 28/60 da referência: a fonte do sistema (`monospace`,
/// já que o Courier Prime da referência não está empacotado no aplicativo) é
/// mais larga por caractere, e com as medidas originais um valor como
/// "R$ 1.234,56" quebrava em duas linhas dentro da própria coluna.
class _Colunas {
  const _Colunas._();

  static const double quantidade = 46;
  static const double valor = 96;
}

/// Cor única do papel: preto quase puro sobre branco, como na referência.
class _Papel {
  const _Papel._();

  static const Color tinta = Color(0xFF1A1A1A);
  static const Color tintaFraca = Color(0xFF555555);
  static const Color fundoDaTela = Color(0xFFE4E7EE);
  static const Color folha = Colors.white;

  static const String fonte = 'monospace';

  static const TextStyle texto = TextStyle(
    fontFamily: fonte,
    fontSize: 13,
    color: tinta,
  );

  static const TextStyle textoForte = TextStyle(
    fontFamily: fonte,
    fontSize: 13,
    fontWeight: FontWeight.bold,
    color: tinta,
  );
}

class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    required this.document,
    this.discountPercentHundredths = 0,
    super.key,
  });

  final PrintedDocument document;

  /// Percentual negociado, em centésimos de ponto — só o critério exibido
  /// ("5% sobre o subtotal"). O valor que vale é sempre
  /// `document.discountAmount`, que já veio pronto do servidor; isto não
  /// recalcula nada, só explica de onde ele saiu.
  final int discountPercentHundredths;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  Uint8List? _barras;
  Uint8List? _qr;

  @override
  void initState() {
    super.initState();
    _gerarCodigos();
  }

  Future<void> _gerarCodigos() async {
    final codigo = widget.document.saleBarcode;
    if (codigo.isEmpty) return;

    try {
      final barras = await code128Png(codigo, modulePoints: 2, barHeightDots: 90);
      final qr = await qrCodePng(codigo);
      if (!mounted) return;
      setState(() {
        _barras = barras;
        _qr = qr;
      });
    } on Exception {
      // Sem os códigos a tela ainda mostra tudo o mais: o comprovante em
      // papel já saiu (ou vai sair) de qualquer forma, e o número por extenso
      // continua visível abaixo do espaço reservado ao desenho.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Papel.fundoDaTela,
      appBar: AppBar(title: const Text('Comprovante')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _Nota(
              document: widget.document,
              percentualDoDesconto: widget.discountPercentHundredths,
              barras: _barras,
              qr: _qr,
            ),
          ),
        ),
      ),
    );
  }
}

/// A folha: mesma estrutura da referência, de cima para baixo.
class _Nota extends StatelessWidget {
  const _Nota({
    required this.document,
    required this.percentualDoDesconto,
    required this.barras,
    required this.qr,
  });

  final PrintedDocument document;
  final int percentualDoDesconto;
  final Uint8List? barras;
  final Uint8List? qr;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Papel.folha,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecalho(document: document),
            const SizedBox(height: 16),
            _LinhaVendedorCliente(document: document),
            const SizedBox(height: 12),
            _Identificacao(document: document),
            const SizedBox(height: 8),
            const _LinhaPontilhada(),
            const SizedBox(height: 8),
            _Itens(document: document, percentualDoDesconto: percentualDoDesconto),
            const SizedBox(height: 2),
            const _LinhaPontilhada(),
            const SizedBox(height: 10),
            _Totais(document: document),
            const SizedBox(height: 10),
            const _LinhaPontilhada(),
            const SizedBox(height: 10),
            _TotalFinal(document: document),
            const SizedBox(height: 18),
            _Codigo(barras: barras, numero: document.saleBarcode),
            const SizedBox(height: 16),
            _Rodape(document: document),
            if (qr != null) ...[
              const SizedBox(height: 10),
              _QrCode(png: qr!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.document});

  final PrintedDocument document;

  String get _subtitulo => switch (document.type) {
        DocumentType.doc1 => 'ENCAMINHAMENTO AO CAIXA',
        DocumentType.doc2 => 'DOCUMENTO DE RETIRADA',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: _Papel.tinta, width: 2)),
          ),
          child: const Icon(Icons.print_outlined, size: 30, color: _Papel.tinta),
        ),
        const SizedBox(height: 6),
        Text(
          document.storeName.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: _Papel.fonte,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: _Papel.tinta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _subtitulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: _Papel.fonte,
            fontSize: 11,
            letterSpacing: 1.4,
            color: _Papel.tintaFraca,
          ),
        ),
        if (document.isReprint) ...[
          const SizedBox(height: 4),
          Text(
            '** ${document.sequence}ª VIA - REIMPRESSÃO **',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _Papel.fonte,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _Papel.tinta,
            ),
          ),
        ],
      ],
    );
  }
}

class _LinhaVendedorCliente extends StatelessWidget {
  const _LinhaVendedorCliente({required this.document});

  final PrintedDocument document;

  @override
  Widget build(BuildContext context) {
    final cliente = document.customerName?.trim();
    final semCliente = cliente == null || cliente.isEmpty;

    return Text(
      'Vendedor:${document.sellerName}   '
      'Cliente:${semCliente ? 'Não informado' : cliente}',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: _Papel.fonte,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: _Papel.tinta,
      ),
    );
  }
}

class _Identificacao extends StatelessWidget {
  const _Identificacao({required this.document});

  final PrintedDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LinhaDeDuasColunas(
          esquerda: 'VENDA:#${document.saleId}',
          direita: 'REF:${document.reference}',
          estilo: _Papel.texto,
        ),
        const SizedBox(height: 2),
        _LinhaDeDuasColunas(
          esquerda: 'Data:${formatDate(document.saleOccurredAt)}',
          direita: 'Hora:${formatTime(document.saleOccurredAt)}',
          estilo: _Papel.texto,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Expanded(child: Text('ITEM', style: _Papel.textoForte)),
            const SizedBox(width: 8),
            SizedBox(
              width: _Colunas.quantidade,
              child: const Text(
                'QTD',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: _Papel.textoForte,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: _Colunas.valor,
              child: const Text(
                'VALOR',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: _Papel.textoForte,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rótulo à esquerda, valor à direita — usada nas linhas de identificação e
/// nos totais, sempre com o mesmo par de estilos da referência.
class _LinhaDeDuasColunas extends StatelessWidget {
  const _LinhaDeDuasColunas({
    required this.esquerda,
    required this.direita,
    required this.estilo,
  });

  final String esquerda;
  final String direita;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(esquerda, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
        ),
        const SizedBox(width: 8),
        Text(direita, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
      ],
    );
  }
}

/// Os itens da venda e, logo abaixo deles, o desconto — mesmo agrupamento da
/// referência, antes da primeira linha pontilhada do bloco de totais.
class _Itens extends StatelessWidget {
  const _Itens({required this.document, required this.percentualDoDesconto});

  final PrintedDocument document;
  final int percentualDoDesconto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in document.items) ...[
          _LinhaDoItem(item: item),
          const SizedBox(height: 6),
        ],
        if (document.hasDiscount)
          _LinhaDeDesconto(
            valor: document.discountAmount.toDisplayString(),
            percentual: percentualDoDesconto,
          ),
      ],
    );
  }
}

class _LinhaDoItem extends StatelessWidget {
  const _LinhaDoItem({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            item.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _Papel.texto,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: _Colunas.quantidade,
          child: Text(
            item.quantity.toDisplayString(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _Papel.texto,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: _Colunas.valor,
          child: Text(
            item.lineTotal.toDisplayString(),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _Papel.texto,
          ),
        ),
      ],
    );
  }
}

/// A linha do desconto, indentada, com o critério ("5% sobre o subtotal" ou
/// "valor fixo") — mesma regra usada na tela de Venda Registrada, para as
/// duas telas não divergirem na explicação do mesmo número.
class _LinhaDeDesconto extends StatelessWidget {
  const _LinhaDeDesconto({required this.valor, required this.percentual});

  final String valor;
  final int percentual;

  @override
  Widget build(BuildContext context) {
    final criterio = percentual > 0
        ? '${formatPercentDisplay(percentual)} sobre o subtotal'
        : 'valor fixo';

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '[Desconto $criterio]',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _Papel.texto,
            ),
          ),
          const SizedBox(width: 8),
          Text('-$valor', style: _Papel.texto),
        ],
      ),
    );
  }
}

class _Totais extends StatelessWidget {
  const _Totais({required this.document});

  final PrintedDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LinhaDeDuasColunas(
          esquerda: 'Sub-total',
          direita: document.grossAmount.toDisplayString(),
          estilo: _Papel.texto,
        ),
        if (document.hasDiscount) ...[
          const SizedBox(height: 4),
          _LinhaDeDuasColunas(
            esquerda: 'Desconto',
            direita: '-${document.discountAmount.toDisplayString()}',
            estilo: _Papel.texto,
          ),
        ],
      ],
    );
  }
}

class _TotalFinal extends StatelessWidget {
  const _TotalFinal({required this.document});

  final PrintedDocument document;

  @override
  Widget build(BuildContext context) {
    const estiloTotal = TextStyle(
      fontFamily: _Papel.fonte,
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: _Papel.tinta,
    );

    return Column(
      children: [
        _LinhaDeDuasColunas(
          esquerda: 'Total',
          direita: document.totalAmount.toDisplayString(),
          estilo: estiloTotal,
        ),
        const SizedBox(height: 5),
        _LinhaDeDuasColunas(
          esquerda: document.paymentMethodLabel,
          direita: document.totalAmount.toDisplayString(),
          estilo: _Papel.texto,
        ),
      ],
    );
  }
}

class _Codigo extends StatelessWidget {
  const _Codigo({required this.barras, required this.numero});

  final Uint8List? barras;
  final String numero;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: barras != null
              ? Image.memory(barras!, fit: BoxFit.contain)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          numero,
          style: const TextStyle(
            fontFamily: _Papel.fonte,
            fontSize: 12,
            letterSpacing: 1.2,
            color: _Papel.tinta,
          ),
        ),
      ],
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.document});

  final PrintedDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'OBRIGADO! VOLTE SEMPRE!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _Papel.fonte,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _Papel.tinta,
          ),
        ),
        if (document.notice.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            document.notice,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _Papel.fonte,
              fontSize: 12,
              color: _Papel.tintaFraca,
            ),
          ),
        ],
      ],
    );
  }
}

class _QrCode extends StatelessWidget {
  const _QrCode({required this.png});

  final Uint8List png;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          border: Border.fromBorderSide(BorderSide(color: _Papel.tinta, width: 2)),
        ),
        child: Image.memory(png, fit: BoxFit.contain),
      ),
    );
  }
}

/// Linha pontilhada, como as que separam as seções na referência.
class _LinhaPontilhada extends StatelessWidget {
  const _LinhaPontilhada();

  static const double _tracinho = 4;
  static const double _vao = 3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, restricoes) {
          final quantidade = (restricoes.maxWidth / (_tracinho + _vao)).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < quantidade; i++)
                const SizedBox(
                  width: _tracinho,
                  height: 1,
                  child: DecoratedBox(decoration: BoxDecoration(color: _Papel.tinta)),
                ),
            ],
          );
        },
      ),
    );
  }
}
