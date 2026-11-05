/// Venda feita sem internet: receber aqui mesmo, ou mandar para o caixa.
///
/// Sem rede o caixa não enxerga a venda, então o padrão é o vendedor receber e
/// o cliente sair com o comprovante de retirada. "Pagar no caixa depois" fica
/// como saída para quando a internet voltar logo, ou o cliente preferir — aí
/// sai o papel de sempre, o encaminhamento ao caixa.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/money.dart';
import '../../data/session/session_manager.dart';
import '../../core/result.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/usecases/create_sale.dart';
import '../shared/brand.dart';
import '../shared/confirmacao_do_vendedor.dart';
import '../shared/feedback.dart';
import 'payment_confirmed_page.dart';

class OfflinePaymentPage extends StatefulWidget {
  const OfflinePaymentPage({required this.finished, super.key});

  final SaleFinished finished;

  @override
  State<OfflinePaymentPage> createState() => _OfflinePaymentPageState();
}

class _OfflinePaymentPageState extends State<OfflinePaymentPage> {
  final TextEditingController _recebido = TextEditingController();
  bool _ocupado = false;

  @override
  void dispose() {
    _recebido.dispose();
    super.dispose();
  }

  PaymentMethod get _forma => widget.finished.result.sale.paymentMethod;
  Money get _total => widget.finished.result.sale.totalAmount;

  /// Valor entregue pelo cliente, em dinheiro. Vazio vale como valor exato.
  Money? get _valorRecebido {
    final texto = _recebido.text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (texto.isEmpty) return _total;
    try {
      return Money.parse(texto);
    } on FormatException {
      return null;
    }
  }

  Money? get _troco {
    final recebido = _valorRecebido;
    if (recebido == null) return null;
    final troco = recebido - _total;
    return troco.cents < 0 ? null : troco;
  }

  bool get _podeConfirmar =>
      !_ocupado && (_forma != PaymentMethod.dinheiro || _troco != null);

  String get _instrucao => switch (_forma) {
        PaymentMethod.dinheiro =>
          'Receba o dinheiro e devolva o troco. Entregue o valor ao caixa depois.',
        PaymentMethod.pix =>
          'Confira no celular se o PIX caiu na conta antes de confirmar.',
        PaymentMethod.credito || PaymentMethod.debito =>
          'Passe o cartão na maquininha e espere aprovar antes de confirmar.',
        PaymentMethod.notinha =>
          'Venda fiada: o valor fica na conta do cliente. Confira quem está levando.',
      };

  Future<void> _receber() async {
    final receber = context.deps.receiveOfflinePayment;
    final finished = widget.finished;
    final documento = finished.result.document;
    if (receber == null || documento == null || !_podeConfirmar) return;

    final navigator = Navigator.of(context);
    final sessao = context.deps.session;
    final quem = sessao.seller?.name ?? finished.result.sale.sellerName;
    final troco = _forma == PaymentMethod.dinheiro ? _troco : null;

    setState(() => _ocupado = true);
    final resultado = await receber(
      sale: finished.result.sale,
      document1: documento,
      receiverName: quem,
    );
    if (!mounted) return;
    setState(() => _ocupado = false);

    switch (resultado) {
      case Ok(:final value):
        if (value.printFailure case final falha?) {
          showMessage(
            context,
            'Pagamento registrado, mas o comprovante não saiu: ${falha.message}',
          );
        } else if (troco != null && troco.isPositive) {
          showMessage(context, 'Troco: ${troco.toDisplayString()}');
        }
        await navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PaymentConfirmedPage(
              sale: value.sale,
              recebidoNoPdv: true,
              onNovaVenda: () => _novaVenda(navigator, sessao),
              onInicio: () => navigator.pushNamedAndRemoveUntil(
                AppRoutes.welcome,
                (_) => false,
              ),
            ),
          ),
        );
      case Err(:final failure):
        showFailure(context, failure);
    }
  }

  /// O cliente vai pagar no caixa: sai o encaminhamento, como com internet.
  Future<void> _pagarNoCaixa() async {
    final finished = widget.finished;
    final documento = finished.result.document;
    final navigator = Navigator.of(context);
    final impressora = context.deps.printer;

    setState(() => _ocupado = true);
    final impresso = documento == null
        ? null
        : await impressora.printDocument(documento);
    if (!mounted) return;
    setState(() => _ocupado = false);

    await navigator.pushReplacementNamed(
      AppRoutes.saleFinished,
      arguments: SaleFinished(
        result: finished.result,
        printFailure: impresso?.failureOrNull,
        pendingOperationId: finished.pendingOperationId,
        customerPhone: finished.customerPhone,
        discountPercentHundredths: finished.discountPercentHundredths,
      ),
    );
  }

  /// Chamada pela tela de confirmação, quando esta já saiu da pilha: por isso
  /// recebe a sessão em vez de ler do `context`.
  static Future<void> _novaVenda(
    NavigatorState navigator,
    SessionManager sessao,
  ) async {
    final vendedor = sessao.seller?.name;
    if (vendedor == null) {
      await navigator.pushNamedAndRemoveUntil(AppRoutes.newSale, (_) => false);
      return;
    }
    final resposta = await confirmarVendedor(navigator.context, vendedor: vendedor);
    if (resposta == null) return;
    switch (resposta) {
      case ConfirmacaoDoVendedor.confirmado:
        await navigator.pushNamedAndRemoveUntil(AppRoutes.newSale, (_) => false);
      case ConfirmacaoDoVendedor.trocar:
        await sessao.clearSession();
        await navigator.pushNamedAndRemoveUntil(
          AppRoutes.sellerSelection,
          (_) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.finished.result.sale;
    final troco = _troco;

    return PopScope(
      // A venda já está na fila: voltar para a montagem a duplicaria.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFEEF1F8),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Marca.amarelo,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_off, color: Marca.tinta),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sem internet. A venda está guardada no aparelho '
                              'e pode ser recebida aqui mesmo.',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Marca.tinta,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'RECEBER PAGAMENTO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Marca.tinta,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'TOTAL',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                                color: Marca.tintaFraca,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _total.toDisplayString(),
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  color: Marca.azul,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Forma: ${_forma.label}'
                              '${sale.customerName == null ? '' : ' · Cliente: ${sale.customerName}'}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Marca.tinta,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _instrucao,
                              style: const TextStyle(color: Marca.tintaFraca),
                            ),
                            if (_forma == PaymentMethod.dinheiro) ...[
                              const SizedBox(height: 16),
                              TextField(
                                key: const Key('valor-recebido'),
                                controller: _recebido,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Valor entregue pelo cliente',
                                  hintText: _total.toDisplayString(symbol: false),
                                  prefixText: 'R\$ ',
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                troco == null
                                    ? 'Valor menor que o total.'
                                    : 'Troco: ${troco.toDisplayString()}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: troco == null
                                      ? Marca.vermelhoTexto
                                      : Marca.tinta,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 64,
                      child: FilledButton.icon(
                        key: const Key('confirmar-recebimento'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1B8A4B),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: _podeConfirmar ? _receber : null,
                        icon: _ocupado
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle),
                        label: Text(
                          _forma == PaymentMethod.notinha
                              ? 'Confirmar entrega e imprimir'
                              : 'Confirmar recebimento e imprimir',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        key: const Key('pagar-no-caixa'),
                        onPressed: _ocupado ? null : _pagarNoCaixa,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Cliente vai pagar no caixa depois'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
