/// Venda feita sem internet: receber aqui mesmo, ou mandar para o caixa.
///
/// Sem rede o caixa não enxerga a venda, então o padrão é o vendedor receber e
/// o cliente sair com o comprovante de retirada. "Pagar no caixa depois" fica
/// como saída para quando a internet voltar logo, ou o cliente preferir — aí
/// sai o papel de sempre, o encaminhamento ao caixa.
///
/// Como no caixa, a forma pode ser outra que não a escolhida na montagem, e o
/// pagamento pode ser dividido em duas formas (13.7). As regras são as mesmas
/// que o servidor aplica ao receber (`offlinePaymentProblem`): a soma fecha com
/// o total, e venda com desconto não vai no crédito (13.3).
///
/// Notinha fica de fora da troca: ela muda a venda em si (cliente, pendência),
/// e a venda já está na fila. Venda em notinha só confirma a entrega.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/money.dart';
import '../../core/result.dart';
import '../../data/session/session_manager.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/sale.dart';
import '../../domain/usecases/create_sale.dart';
import '../../domain/usecases/receive_offline_payment.dart';
import '../shared/brand.dart';
import '../shared/confirmacao_do_vendedor.dart';
import '../shared/feedback.dart';
import 'payment_confirmed_page.dart';

/// Formas que o PDV recebe — as do caixa. Notinha não é recebimento (RF14).
const List<PaymentMethod> _formasRecebiveis = [
  PaymentMethod.dinheiro,
  PaymentMethod.pix,
  PaymentMethod.debito,
  PaymentMethod.credito,
];

/// Texto digitado (`150`, `150,5`, `1.500,00`) para dinheiro. `null` se inválido.
Money? _lerValor(String texto) {
  final limpo = texto.trim().replaceAll('.', '').replaceAll(',', '.');
  if (limpo.isEmpty) return null;
  try {
    return Money.parse(limpo);
  } on FormatException {
    return null;
  }
}

class OfflinePaymentPage extends StatefulWidget {
  const OfflinePaymentPage({required this.finished, super.key});

  final SaleFinished finished;

  @override
  State<OfflinePaymentPage> createState() => _OfflinePaymentPageState();
}

class _OfflinePaymentPageState extends State<OfflinePaymentPage> {
  /// Quanto o cliente entregou em dinheiro, para o troco.
  final TextEditingController _entregue = TextEditingController();

  /// Valor da primeira forma, quando o pagamento é dividido.
  final TextEditingController _valorDaPrimeira = TextEditingController();

  bool _ocupado = false;

  late PaymentMethod _primeira = _formaInicial;
  bool _dividir = false;
  PaymentMethod? _segunda;

  @override
  void dispose() {
    _entregue.dispose();
    _valorDaPrimeira.dispose();
    super.dispose();
  }

  Sale get _venda => widget.finished.result.sale;
  Money get _total => _venda.totalAmount;
  bool get _notinha => _venda.paymentMethod == PaymentMethod.notinha;

  /// A forma da montagem — ou dinheiro, se ela não puder ser usada (crédito
  /// numa venda com desconto não chega aqui, mas a tela não confia nisso).
  PaymentMethod get _formaInicial {
    final forma = _venda.paymentMethod;
    return _formasRecebiveis.contains(forma) && _permitida(forma)
        ? forma
        : PaymentMethod.dinheiro;
  }

  /// 13.3 — com desconto, o crédito não entra nem como parte do pagamento.
  bool _permitida(PaymentMethod forma) =>
      !(forma == PaymentMethod.credito && _venda.hasDiscount);

  /// As partes como estão na tela. A segunda é o que falta para o total.
  List<OfflinePaymentPart>? get _partes {
    if (_notinha) return const [];
    if (!_dividir) return [OfflinePaymentPart(_primeira, _total)];

    final segunda = _segunda;
    final primeiraValor = _lerValor(_valorDaPrimeira.text);
    if (segunda == null || primeiraValor == null) return null;
    return [
      OfflinePaymentPart(_primeira, primeiraValor),
      OfflinePaymentPart(segunda, _total - primeiraValor),
    ];
  }

  /// O que impede confirmar, em português, ou `null`.
  String? get _problema {
    final partes = _partes;
    if (partes == null) {
      return _segunda == null
          ? 'Escolha a segunda forma.'
          : 'Informe quanto vai na primeira forma.';
    }
    final regra = offlinePaymentProblem(_venda, partes);
    if (regra != null) return regra;
    if (_parteEmDinheiro != null && _troco == null) {
      return 'O dinheiro entregue é menor que o valor em dinheiro.';
    }
    return null;
  }

  /// Quanto desta venda é pago em dinheiro — é sobre isso que sai o troco.
  Money? get _parteEmDinheiro {
    for (final parte in _partes ?? const <OfflinePaymentPart>[]) {
      if (parte.method == PaymentMethod.dinheiro && parte.amount.isPositive) {
        return parte.amount;
      }
    }
    return null;
  }

  Money? get _troco {
    final devido = _parteEmDinheiro;
    if (devido == null) return null;
    final texto = _entregue.text.trim();
    // Vazio vale como valor exato: sem troco.
    final entregue = texto.isEmpty ? devido : _lerValor(texto);
    if (entregue == null) return null;
    final troco = entregue - devido;
    return troco.cents < 0 ? null : troco;
  }

  bool get _podeConfirmar => !_ocupado && _problema == null;

  String _instrucaoDe(PaymentMethod forma) => switch (forma) {
        PaymentMethod.dinheiro =>
          'Dinheiro: receba e devolva o troco. Entregue o valor ao caixa depois.',
        PaymentMethod.pix =>
          'PIX: confira no celular se caiu na conta antes de confirmar.',
        PaymentMethod.credito ||
        PaymentMethod.debito =>
          'Cartão: passe na maquininha e espere aprovar antes de confirmar.',
        PaymentMethod.notinha =>
          'Venda fiada: o valor fica na conta do cliente. Confira quem está levando.',
      };

  void _escolherPrimeira(PaymentMethod forma) => setState(() {
        _primeira = forma;
        if (_segunda == forma) _segunda = null;
      });

  void _alternarDivisao(bool dividir) => setState(() {
        _dividir = dividir;
        if (!dividir) {
          _segunda = null;
          _valorDaPrimeira.clear();
        }
      });

  Future<void> _receber() async {
    final receber = context.deps.receiveOfflinePayment;
    final finished = widget.finished;
    final documento = finished.result.document;
    final partes = _partes;
    if (receber == null ||
        documento == null ||
        partes == null ||
        !_podeConfirmar) {
      return;
    }

    final navigator = Navigator.of(context);
    final sessao = context.deps.session;
    final quem = sessao.seller?.name ?? _venda.sellerName;
    final troco = _troco;

    setState(() => _ocupado = true);
    final resultado = await receber(
      sale: _venda,
      document1: documento,
      receiverName: quem,
      payments: partes,
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
    final impresso =
        documento == null ? null : await impressora.printDocument(documento);
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
    final resposta =
        await confirmarVendedor(navigator.context, vendedor: vendedor);
    if (resposta == null) return;
    switch (resposta) {
      case ConfirmacaoDoVendedor.confirmado:
        await navigator.pushNamedAndRemoveUntil(
            AppRoutes.newSale, (_) => false);
      case ConfirmacaoDoVendedor.trocar:
        await sessao.clearSession();
        await navigator.pushNamedAndRemoveUntil(
          AppRoutes.sellerSelection,
          (_) => false,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Tela
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final problema = _problema;

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
                    const _AvisoSemInternet(),
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
                            _Total(total: _total, cliente: _venda.customerName),
                            const SizedBox(height: 16),
                            if (_notinha)
                              Text(
                                _instrucaoDe(PaymentMethod.notinha),
                                style: const TextStyle(color: Marca.tintaFraca),
                              )
                            else
                              ..._formas(),
                            if (_parteEmDinheiro case final emDinheiro?) ...[
                              const SizedBox(height: 16),
                              _Troco(
                                controller: _entregue,
                                emDinheiro: emDinheiro,
                                troco: _troco,
                                onChanged: () => setState(() {}),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (problema != null && !_ocupado) ...[
                      const SizedBox(height: 12),
                      Text(
                        problema,
                        key: const Key('problema-do-pagamento'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Marca.vermelhoTexto,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
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
                          _notinha
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

  /// Escolha da forma, a divisão e as instruções de cada forma usada.
  List<Widget> _formas() {
    final segunda = _segunda;
    final usadas = [_primeira, if (_dividir && segunda != null) segunda];

    return [
      Text(
        _dividir ? 'PRIMEIRA FORMA' : 'FORMA DE PAGAMENTO',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Marca.tintaFraca,
        ),
      ),
      const SizedBox(height: 8),
      _SeletorDeForma(
        chave: 'primeira',
        selecionada: _primeira,
        permitida: _permitida,
        onSelecionar: _escolherPrimeira,
      ),
      if (_venda.hasDiscount) ...[
        const SizedBox(height: 6),
        const Text(
          'Venda com desconto não pode ser no crédito.',
          style: TextStyle(fontSize: 13, color: Marca.tintaFraca),
        ),
      ],
      const SizedBox(height: 8),
      SwitchListTile(
        key: const Key('dividir-pagamento'),
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Dividir em duas formas',
          style: TextStyle(fontWeight: FontWeight.w700, color: Marca.tinta),
        ),
        value: _dividir,
        onChanged: _ocupado ? null : _alternarDivisao,
      ),
      if (_dividir) ...[
        TextField(
          key: const Key('valor-da-primeira'),
          controller: _valorDaPrimeira,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quanto vai em ${_primeira.label}',
            prefixText: 'R\$ ',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        const Text(
          'SEGUNDA FORMA',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Marca.tintaFraca,
          ),
        ),
        const SizedBox(height: 8),
        _SeletorDeForma(
          chave: 'segunda',
          selecionada: segunda,
          permitida: (forma) => forma != _primeira && _permitida(forma),
          onSelecionar: (forma) => setState(() => _segunda = forma),
        ),
        if (segunda != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _restanteNaSegunda(segunda),
              key: const Key('valor-da-segunda'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Marca.tinta,
              ),
            ),
          ),
      ],
      const SizedBox(height: 12),
      for (final forma in usadas.toSet())
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            _instrucaoDe(forma),
            style: const TextStyle(color: Marca.tintaFraca),
          ),
        ),
    ];
  }

  String _restanteNaSegunda(PaymentMethod segunda) {
    final primeira = _lerValor(_valorDaPrimeira.text);
    if (primeira == null) return 'Em ${segunda.label}: o restante.';
    final resto = _total - primeira;
    return 'Em ${segunda.label}: ${resto.toDisplayString()}';
  }
}

class _AvisoSemInternet extends StatelessWidget {
  const _AvisoSemInternet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              'Sem internet. A venda está guardada no aparelho e pode ser '
              'recebida aqui mesmo.',
              style: TextStyle(fontWeight: FontWeight.w700, color: Marca.tinta),
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.total, this.cliente});

  final Money total;
  final String? cliente;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'TOTAL',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: Marca.tintaFraca,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            total.toDisplayString(),
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: Marca.azul,
            ),
          ),
        ),
        if (cliente != null)
          Text(
            'Cliente: $cliente',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Marca.tinta,
            ),
          ),
      ],
    );
  }
}

/// Botões de forma de pagamento, um ao lado do outro.
class _SeletorDeForma extends StatelessWidget {
  const _SeletorDeForma({
    required this.chave,
    required this.selecionada,
    required this.permitida,
    required this.onSelecionar,
  });

  final String chave;
  final PaymentMethod? selecionada;
  final bool Function(PaymentMethod) permitida;
  final ValueChanged<PaymentMethod> onSelecionar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final forma in _formasRecebiveis)
          ChoiceChip(
            key: Key('forma-$chave-${forma.code}'),
            label: Text(
              forma.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            selected: selecionada == forma,
            onSelected: permitida(forma) ? (_) => onSelecionar(forma) : null,
          ),
      ],
    );
  }
}

/// Quanto o cliente entregou em dinheiro, e o troco.
class _Troco extends StatelessWidget {
  const _Troco({
    required this.controller,
    required this.emDinheiro,
    required this.troco,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Money emDinheiro;
  final Money? troco;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final troco = this.troco;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('valor-recebido'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Dinheiro entregue pelo cliente',
            hintText: emDinheiro.toDisplayString(symbol: false),
            prefixText: 'R\$ ',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        Text(
          troco == null
              ? 'Valor menor que o devido em dinheiro.'
              : 'Troco: ${troco.toDisplayString()}',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: troco == null ? Marca.vermelhoTexto : Marca.tinta,
          ),
        ),
      ],
    );
  }
}
