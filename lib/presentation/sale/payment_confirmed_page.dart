/// Confirmação de que o caixa recebeu a venda (RF10–RF12).
///
/// Existe porque o cliente fica esperando no balcão: depois de pagar, ele
/// volta para o vendedor e alguém precisa dizer "está tudo certo" sem abrir
/// relatório nem procurar a venda numa lista.
///
/// A tela **não confirma** nada — ela mostra o que o servidor já registrou. O
/// recebimento é do caixa, noutra estação; aqui foi só uma leitura. Por isso
/// não há o que duplicar: nenhum pagamento, nenhuma venda, nenhum documento.
///
/// O texto sai do estado real da venda, e não de uma frase fixa. Notinha é o
/// caso que cobra essa disciplina: o caixa conferiu, mas ninguém pagou nada —
/// escrever "pagamento confirmado" ali seria dizer ao vendedor que entrou
/// dinheiro que não entrou.
library;

import 'package:flutter/material.dart';

import '../../domain/entities/sale.dart';
import '../shared/brand.dart';

class PaymentConfirmedPage extends StatelessWidget {
  const PaymentConfirmedPage({
    required this.sale,
    required this.onNovaVenda,
    required this.onInicio,
    super.key,
  });

  final Sale sale;

  /// Continua o balcão: a próxima venda.
  final VoidCallback onNovaVenda;

  /// Encerra e devolve o aparelho ao repouso.
  final VoidCallback onInicio;

  /// O que dizer, conforme o que o servidor registrou.
  ({String titulo, String texto, IconData icone}) get _anuncio =>
      switch (sale.status) {
        SaleStatus.paga => (
            titulo: 'PAGAMENTO CONFIRMADO',
            texto: 'Venda finalizada com sucesso.',
            icone: Icons.check_circle,
          ),
        // O caixa conferiu, mas é fiado: o valor fica em aberto e não houve
        // pagamento nenhum a anunciar.
        SaleStatus.pendenteNotinha => (
            titulo: 'CONFIRMADO NO CAIXA',
            texto: 'Venda em notinha: o valor fica em aberto.',
            icone: Icons.assignment_turned_in,
          ),
        SaleStatus.quitada => (
            titulo: 'NOTINHA QUITADA',
            texto: 'Venda finalizada com sucesso.',
            icone: Icons.check_circle,
          ),
        _ => (
            titulo: sale.status.label.toUpperCase(),
            texto: 'Situação registrada pelo servidor.',
            icone: Icons.info_outline,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final anuncio = _anuncio;

    return Scaffold(
      backgroundColor: const Color(0xFFEEF1F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 600;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compacto ? 20 : 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        anuncio.icone,
                        size: compacto ? 84 : 110,
                        color: const Color(0xFF1B8A4B),
                      ),
                      SizedBox(height: compacto ? 14 : 20),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          anuncio.titulo,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compacto ? 30 : 40,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                            color: Marca.tinta,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        anuncio.texto,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compacto ? 16 : 20,
                          fontWeight: FontWeight.w600,
                          color: Marca.tintaFraca,
                        ),
                      ),
                      SizedBox(height: compacto ? 18 : 26),
                      _CartaoDaVenda(sale: sale, compacto: compacto),
                      SizedBox(height: compacto ? 20 : 28),
                      // A ação que continua o balcão é a maior: é o que o
                      // vendedor toca com o próximo cliente já na frente.
                      SizedBox(
                        height: 72,
                        child: FilledButton.icon(
                          onPressed: onNovaVenda,
                          icon: const Icon(Icons.shopping_cart_outlined,
                              size: 28),
                          style: FilledButton.styleFrom(
                            backgroundColor: Marca.laranja,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'NOVA VENDA',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: onInicio,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 56),
                            side: const BorderSide(
                                color: Marca.bordaCampo, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'INÍCIO',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Marca.tinta,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Qual venda foi conferida — o vendedor confere o número com o papel na mão.
class _CartaoDaVenda extends StatelessWidget {
  const _CartaoDaVenda({required this.sale, required this.compacto});

  final Sale sale;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 16 : 22,
        vertical: compacto ? 14 : 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Marca.bordaCampo),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'VENDA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: Marca.tintaFraca,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              sale.barcode,
              style: TextStyle(
                fontSize: compacto ? 20 : 25,
                fontWeight: FontWeight.w800,
                color: Marca.tinta,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: Marca.tintaFraca,
                ),
              ),
              const SizedBox(width: 12),
              // Encolhe em vez de estourar: com a fonte do sistema ampliada
              // um total de quatro dígitos já passa da largura do M10.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    sale.totalAmount.toDisplayString(),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: compacto ? 20 : 25,
                      fontWeight: FontWeight.w800,
                      color: Marca.tinta,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
