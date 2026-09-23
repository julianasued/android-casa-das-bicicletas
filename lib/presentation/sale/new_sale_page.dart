/// Montagem da venda pelo vendedor (RF06) e emissão do documento 1 (RF08).
///
/// A tela é dividida em duas metades porque o balcão é assim: em cima o
/// operador procura o produto (digitando ou bipando a etiqueta), embaixo ele
/// confere com o cliente o que já foi lançado e quanto deu. O total fica
/// sempre visível — é a informação que o cliente pede, e é a que o vendedor
/// não pode ter de rolar a tela para achar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/receivable.dart';
import '../../domain/rules/sale_draft.dart';
import '../../domain/rules/sale_pricing.dart';
import '../../domain/usecases/create_sale.dart';
import '../../platform/connectivity/connectivity_channel.dart';
import '../shared/brand.dart';
import '../shared/feedback.dart';
import 'customer_picker_page.dart';
import 'new_sale_controller.dart';

class NewSalePage extends StatefulWidget {
  const NewSalePage({super.key});

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final TextEditingController _searchController = TextEditingController();

  /// Criado em `didChangeDependencies`, e não em `initState`: é ali que o
  /// `InheritedWidget` das dependências pode ser lido com segurança.
  NewSaleController? _controllerOrNull;

  NewSaleController get _controller => _controllerOrNull!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controllerOrNull != null) return;

    final deps = context.deps;
    _controllerOrNull = NewSaleController(
      catalog: deps.catalog,
      createSale: deps.createSale,
      scanner: deps.scanner,
    );
    unawaited(_controller.search(''));
    unawaited(_controller.loadCategories());
  }

  @override
  void dispose() {
    _controllerOrNull?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEEF1F8),
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Duas colunas só quando há espaço nas duas direções: a
              // referência é de 1280x800, e espremê-la numa tela baixa põe o
              // teclado e a venda disputando altura que não existe.
              final compacto =
                  constraints.maxWidth < 900 || constraints.maxHeight < 640;

              return Column(
                children: [
                  _CabecalhoDaVenda(
                    vendedor: deps.session.seller?.name,
                    conectividade: deps.connectivity,
                    compacto: compacto,
                    onMenu: _openMenu,
                    onSair: _exit,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ListenableBuilder(
                            listenable: _controller,
                            builder: (context, _) => compacto
                                ? _CorpoEstreito(
                                    controller: _controller,
                                    onLancar: _lancarNaCategoria,
                                    onPickCustomer: _pickCustomer,
                                    onEditDiscount: _editDiscount,
                                    onFinish: _finish,
                                  )
                                : _CorpoLargo(
                                    controller: _controller,
                                    onLancar: _lancarNaCategoria,
                                    onPickCustomer: _pickCustomer,
                                    onEditDiscount: _editDiscount,
                                    onFinish: _finish,
                                  ),
                          ),
                        ),
                        // Flutuante só na tela larga, onde o canto inferior
                        // esquerdo é o teclado. No estreito ali fica o painel
                        // da venda, e a barra cobriria o botão de finalizar —
                        // por isso lá ela entra em linha, logo abaixo das
                        // categorias.
                        if (!compacto)
                          Positioned(
                            left: 20,
                            bottom: 20,
                            child: ListenableBuilder(
                              listenable: _controller,
                              builder: (context, _) => _BarraDeDesfazer(
                                linha: _controller.ultimaLinha,
                                onDesfazer: _controller.desfazerUltimo,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Fecha o lançamento: o valor digitado vira uma linha da categoria tocada.
  void _lancarNaCategoria(ProductCategory categoria) {
    _controller.lancarNaCategoria(categoria);
  }

  // -------------------------------------------------------------------------
  // Ações
  // -------------------------------------------------------------------------

  /// Enter no campo de busca vale como código bipado: o leitor em modo teclado
  /// entrega o código exatamente assim.
  Future<void> _addTypedCode(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;

    final failure = await _controller.addByBarcode(code);
    if (!mounted) return;

    if (failure != null) {
      showFailure(context, failure);
      return;
    }
    _searchController.clear();
    await _controller.search('');
  }

  /// Menu do cabeçalho (§6).
  ///
  /// Sobe de baixo em vez de abrir uma gaveta lateral: no M10, segurado com uma
  /// mão, o canto superior esquerdo é o ponto mais difícil de alcançar da tela —
  /// o ícone fica lá porque é onde se procura um menu, mas o conteúdo vem para
  /// onde o polegar está.
  Future<void> _openMenu() async {
    final navigator = Navigator.of(context);
    final temItens = !_controller.draft.isEmpty;

    final destino = await showModalBottomSheet<String>(
      context: context,
      // A folha padrão reserva 9/16 da altura, e a lista passa disso na tela
      // do M10: sem soltar o limite, a última opção nasce fora da folha e só
      // aparece para quem adivinha que dá para rolar.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (context) => SafeArea(
        // Rolável ainda assim: com a fonte do sistema ampliada a lista volta a
        // passar da altura, e aí rolar é melhor que cortar.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primeiro porque é a única volta desta tela: as outras
              // entradas são ferramentas, esta é o caminho de quem selecionou
              // o vendedor errado.
              ListTile(
                leading: const Icon(Icons.switch_account),
                title: const Text('Trocar vendedor'),
                subtitle: const Text('Mantém o terminal aberto'),
                onTap: () => Navigator.of(context).pop('vendedor'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Buscar produto no catálogo'),
                subtitle:
                    const Text('Capacidade futura; a V1 lança por categoria'),
                onTap: () => Navigator.of(context).pop('catalogo'),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Leitor de código'),
                subtitle:
                    const Text('Localiza a venda pelo código do documento'),
                onTap: () => Navigator.of(context).pop(AppRoutes.scanner),
              ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Impressora'),
                subtitle: const Text('Estado, avanço de papel e teste'),
                onTap: () =>
                    Navigator.of(context).pop(AppRoutes.printerDiagnostics),
              ),
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Teste Elgin M10'),
                subtitle: const Text('Impressora, leitor e display'),
                onTap: () => Navigator.of(context).pop(AppRoutes.m10Poc),
              ),
              if (temItens) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Descartar esta venda'),
                  onTap: () => Navigator.of(context).pop('descartar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!mounted || destino == null) return;
    if (destino == 'vendedor') {
      await _trocarVendedor();
      return;
    }
    if (destino == 'descartar') {
      await _confirmDiscard();
      return;
    }
    if (destino == 'catalogo') {
      await _buscarNoCatalogo();
      return;
    }
    await navigator.pushNamed(destino);
  }

  /// Volta para a seleção de vendedor sem fechar o terminal.
  ///
  /// Quem selecionou o nome errado só tinha o SAIR, que derruba a autenticação
  /// do aparelho e obriga a digitar a senha do terminal de novo — voltar uma
  /// etapa custava reiniciar o fluxo (§19). Derruba só a sessão do vendedor,
  /// como o TROCAR do menu.
  ///
  /// A pilha é limpa de propósito: a sessão do vendedor já não existe quando a
  /// tela nova abre, e deixar esta venda embaixo seria deixar um rascunho sem
  /// dono ao alcance do botão do sistema.
  Future<void> _trocarVendedor() async {
    if (!_controller.draft.isEmpty) {
      final trocar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Trocar de vendedor com a venda aberta?'),
          content: const Text(
            'Os itens lançados serão perdidos. A venda ainda não foi registrada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continuar vendendo'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Trocar'),
            ),
          ],
        ),
      );
      if (!(trocar ?? false) || !mounted) return;
    }

    final deps = context.deps;
    final navigator = Navigator.of(context);
    await deps.session.clearSession();
    if (!mounted) return;
    await navigator.pushNamedAndRemoveUntil(
      AppRoutes.sellerSelection,
      (_) => false,
    );
  }

  /// Encerra o turno no aparelho: a próxima venda exige a senha do terminal.
  Future<void> _exit() async {
    if (!_controller.draft.isEmpty) {
      final sair = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sair com a venda aberta?'),
          content: const Text(
            'Os itens lançados serão perdidos. A venda ainda não foi registrada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continuar vendendo'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sair'),
            ),
          ],
        ),
      );
      if (!(sair ?? false) || !mounted) return;
    }

    final deps = context.deps;
    final navigator = Navigator.of(context);
    await deps.auth.logout();
    if (!mounted) return;
    await navigator.pushNamedAndRemoveUntil(AppRoutes.welcome, (_) => false);
  }

  /// Busca no catálogo — capacidade preservada, fora do caminho principal.
  ///
  /// O §6 do fluxo é explícito: na V1 a busca por produto não é o fluxo
  /// principal. Ela não foi removida, e o leitor de código continua ligado no
  /// controller: quem tiver catálogo cadastrado usa por aqui.
  Future<void> _buscarNoCatalogo() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: SafeArea(
          child: Column(
            children: [
              _SearchField(
                controller: _searchController,
                onChanged: _controller.searchDebounced,
                onSubmitted: _addTypedCode,
              ),
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _CategoryFilter(
                  categories: _controller.categories,
                  selected: _controller.categoryCode,
                  onSelect: _controller.selectCategory,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _ProductResults(
                    controller: _controller,
                    onAdd: (product) {
                      _controller.add(product);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomer() async {
    // A busca precisa saber se a venda exige cliente: na notinha não existe
    // "vender sem", e o atalho não deve nem aparecer (RF14).
    final exige = _controller.draft.paymentMethod.requiresCustomer;
    final escolha = await Navigator.of(context).push<CustomerSelection>(
      MaterialPageRoute(
        builder: (_) => CustomerPickerPage(exigeCliente: exige),
      ),
    );
    if (escolha != null) {
      _controller.setCustomer(
        escolha.customer,
        receivables: escolha.receivables,
      );
    }
  }

  Future<void> _editDiscount() async {
    final result = await showDialog<SaleDiscount>(
      context: context,
      builder: (_) => _DiscountDialog(
        inicial: _controller.draft.discount,
        subtotal: _controller.totals.gross,
      ),
    );
    if (result != null) _controller.setDiscount(result);
  }

  Future<void> _finish() async {
    final navigator = Navigator.of(context);

    // A espera é bloqueante de propósito: entre registrar e o papel sair há
    // uma ida à rede e uma à impressora, e sem isso o vendedor toca de novo
    // achando que não funcionou.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PrintingDialog(),
      ),
    );

    final result = await _controller.finish();

    if (!mounted) return;
    navigator.pop();

    switch (result) {
      case Ok(value: final SaleFinished finished):
        await navigator.pushReplacementNamed(
          AppRoutes.saleFinished,
          arguments: finished,
        );
      case Err(:final Failure failure):
        showFailure(context, failure);
    }
  }

  /// Sai da venda ou, quando não há para onde voltar, apenas a zera.
  ///
  /// Depois do §5 a seleção de vendedor entra direto aqui, então esta tela é a
  /// raiz do fluxo: `pop()` numa pilha vazia fecharia o aplicativo no meio do
  /// balcão. Quando ela foi empilhada por cima de outra — o menu, por exemplo —
  /// voltar continua sendo o certo.
  void _leaveOrReset() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _controller.discard();
      _searchController.clear();
      unawaited(_controller.search(''));
    }
  }

  Future<void> _confirmDiscard() async {
    if (_controller.draft.isEmpty) {
      _leaveOrReset();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar a venda?'),
        content: const Text(
          'Os itens lançados serão perdidos. A venda ainda não foi registrada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar vendendo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if ((discard ?? false) && mounted) _leaveOrReset();
  }
}

// ---------------------------------------------------------------------------
// Partes da tela
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          labelText: 'Produto, SKU ou código de barras',
          prefixIcon: Icon(Icons.search),
          helperText: 'Bipe a etiqueta ou digite e confirme.',
        ),
      ),
    );
  }
}

/// Espera entre o toque e o papel (§15 do fluxo).
///
/// Não é dispensável ao toque fora: fechar isto no meio daria ao vendedor a
/// impressão de que a venda não foi, e ele lançaria tudo de novo.
class _PrintingDialog extends StatelessWidget {
  const _PrintingDialog();

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'Aguarde a impressão da nota...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// O que o vendedor digitou para uma linha manual.
class _ManualEntry {
  const _ManualEntry({required this.price, required this.quantity});

  final Money price;
  final Quantity quantity;
}

/// Valor da linha, com quantidade opcional (§6 do fluxo).
///
/// A quantidade começa vazia porque o caso comum é "PEÇAS, R$ 120" — uma venda
/// inteira, sem contagem. Quem precisar de "2 pneus a R$ 350" informa, e o
/// total sai da multiplicação.
class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog({required this.category});

  final ProductCategory category;

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _confirm() {
    final Money price;
    try {
      price = Money.parse(_priceController.text);
    } on FormatException {
      setState(() => _error = 'Informe o valor, como 120,00.');
      return;
    }
    if (!price.isPositive) {
      setState(() => _error = 'O valor precisa ser maior que zero.');
      return;
    }

    var quantity = const Quantity.units(1);
    final digitada = _quantityController.text.trim();
    if (digitada.isNotEmpty) {
      try {
        quantity = Quantity.parse(digitada);
      } on FormatException {
        setState(() => _error = 'Quantidade inválida.');
        return;
      }
      if (!quantity.isPositive) {
        setState(() => _error = 'A quantidade precisa ser maior que zero.');
        return;
      }
    }

    Navigator.of(context).pop(_ManualEntry(price: price, quantity: quantity));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category.name.toUpperCase()),
      // Rolável: com o teclado aberto na tela de 5" do M10 sobra pouca altura,
      // e os dois campos passavam do espaço do diálogo.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _priceController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                errorText: _error,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantidade (opcional)',
                helperText: 'Em branco vale 1.',
              ),
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Lançar')),
      ],
    );
  }
}

/// Filtro por categoria da RF04 (§6 do fluxo).
///
/// Some quando o catálogo ainda não respondeu: uma fileira vazia de chips
/// ocupa altura na tela de 5" sem dizer nada.
class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<ProductCategory> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return ChoiceChip(
            label: Text(category.name),
            selected: selected == category.code,
            onSelected: (_) => onSelect(category.code),
          );
        },
      ),
    );
  }
}

class _ProductResults extends StatelessWidget {
  const _ProductResults({required this.controller, required this.onAdd});

  final NewSaleController controller;
  final ValueChanged<Product> onAdd;

  @override
  Widget build(BuildContext context) {
    if (controller.isSearching && controller.results.isEmpty) {
      return const LoadingView();
    }
    if (controller.searchFailure != null) {
      return FailureView(
        failure: controller.searchFailure!,
        onRetry: () => controller.search(''),
      );
    }
    if (controller.results.isEmpty) {
      return const EmptyView(
        icon: Icons.inventory_2_outlined,
        message: 'Nenhum produto encontrado no catálogo desta loja.',
      );
    }

    return ListView.separated(
      itemCount: controller.results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = controller.results[index];
        return ListTile(
          title: Text(product.name),
          subtitle: Text('${product.sku} · ${product.categoryName}'),
          trailing: Text(
            product.price.toDisplayString(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          onTap: () => onAdd(product),
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.controller,
    required this.onPickCustomer,
    required this.onEditDiscount,
    required this.onFinish,
    this.semItens = false,
  });

  /// No formato largo os itens têm painel próprio, e repeti-los aqui seria
  /// mostrar a mesma venda duas vezes na mesma tela.
  final bool semItens;

  final NewSaleController controller;
  final VoidCallback onPickCustomer;
  final VoidCallback onEditDiscount;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final totals = controller.totals;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (semItens)
                const SizedBox.shrink()
              else if (draft.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhum item lançado.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < draft.lines.length; i++)
                        _CartLine(
                          line: draft.lines[i],
                          lineTotal: totals.lineTotals[i],
                          onIncrement: () =>
                              controller.increment(draft.lines[i].id),
                          onDecrement: () =>
                              controller.decrement(draft.lines[i].id),
                          onRemove: () => controller.remove(draft.lines[i].id),
                        ),
                    ],
                  ),
                ),
              const Divider(),
              _PaymentSelector(
                selected: draft.paymentMethod,
                onChanged: controller.setPaymentMethod,
              ),
              if (draft.paymentMethod.requiresCustomer) ...[
                const SizedBox(height: 8),
                _NotinhaDetails(
                  customerName: draft.customer?.name,
                  itemCount: draft.lineCount,
                  total: totals.total,
                ),
              ],
              const SizedBox(height: 8),
              if (draft.customer != null) ...[
                _ClienteEscolhido(
                  customer: draft.customer!,
                  receivables: controller.customerReceivables,
                  onTrocar: onPickCustomer,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _BotaoDeCliente(
                      temCliente: draft.customer != null,
                      obrigatorio: draft.paymentMethod.requiresCustomer,
                      onPressed: onPickCustomer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BotaoDeDesconto(
                      percentual: draft.discountPercentHundredths,
                      onPressed: onEditDiscount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (totals.discount.isPositive) ...[
                _TotalRow(
                    label: 'Subtotal', value: totals.gross.toDisplayString()),
                _TotalRow(
                  label: 'Desconto',
                  value: '- ${totals.discount.toDisplayString()}',
                ),
              ],
              // Cartão do total, como na referência: rótulo, a forma escolhida
              // embaixo, e o valor grande à direita — é o número que o cliente
              // confere de longe.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: _Venda.cartao,
                  border: Border.all(color: _Venda.borda),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: _Venda.rotulo,
                          ),
                        ),
                        Text(
                          draft.paymentMethod.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _Venda.rotulo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          totals.total.toDisplayString(),
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: _Venda.painelEscuro,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final problem in controller.problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: scheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          problem.message,
                          style: TextStyle(color: scheme.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              // Aviso, não impedimento: o botão de finalizar segue ativo, e a
              // cor é outra de propósito — vermelho igual ao do problema faria
              // o vendedor achar que não pode registrar a venda.
              for (final warning in controller.warnings)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 18,
                        color: scheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning.message,
                          style: TextStyle(
                            color: scheme.onTertiaryContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: controller.canFinish
                    ? () => _conferirEFinalizar(context, controller, onFinish)
                    : null,
                icon: controller.isSubmitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: const Text('CONFERIR E FINALIZAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.line,
    required this.lineTotal,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final SaleDraftLine line;
  final Money lineTotal;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.label, overflow: TextOverflow.ellipsis),
              Text(
                '${line.quantity.toDisplayString()} x '
                '${line.unitPrice.toDisplayString()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Diminuir',
        ),
        IconButton(
          onPressed: onIncrement,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Aumentar',
        ),
        SizedBox(
          width: 88,
          child: Text(
            lineTotal.toDisplayString(),
            textAlign: TextAlign.right,
            style: AppTheme.monetaryStyle(context),
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remover',
        ),
      ],
    );
  }
}

/// Resumo da venda fiada (§11 do fluxo).
///
/// Repete cliente, data, composição e valor num bloco só porque a notinha é o
/// documento que vai com o cliente e volta na hora de pagar: conferir isso
/// antes de imprimir é mais barato que descobrir divergência depois.
///
/// Prazo e observação aparecem na referência visual, mas não existem no
/// contrato: `SaleCreateSerializer` aceita apenas uuid, customer_id,
/// payment_method, discount_percent, created_offline e items, e o `due_date`
/// do Receivable nasce nulo. Campo que não é enviado a lugar nenhum seria
/// promessa falsa ao operador, então não estão aqui.
class _NotinhaDetails extends StatelessWidget {
  const _NotinhaDetails({
    required this.customerName,
    required this.itemCount,
    required this.total,
  });

  final String? customerName;
  final int itemCount;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semCliente = customerName == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: semCliente
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DETALHES DA NOTINHA',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: semCliente ? theme.colorScheme.onErrorContainer : null,
            ),
          ),
          const SizedBox(height: 8),
          _NotinhaRow(
            label: 'Cliente',
            value: customerName ?? 'obrigatório — escolha abaixo',
            emphasis: semCliente,
          ),
          _NotinhaRow(label: 'Data', value: formatDate(DateTime.now())),
          _NotinhaRow(
            label: 'Composição',
            value: itemCount == 1 ? '1 item' : '$itemCount itens',
          ),
          _NotinhaRow(label: 'Valor', value: total.toDisplayString()),
        ],
      ),
    );
  }
}

class _NotinhaRow extends StatelessWidget {
  const _NotinhaRow({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = emphasis ? theme.colorScheme.onErrorContainer : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: cor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSelector extends StatelessWidget {
  const _PaymentSelector({required this.selected, required this.onChanged});

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    // Grade fixa, como na referência: as cinco formas visíveis de uma vez.
    // Forma de pagamento escondida atrás de rolagem é forma que o vendedor não
    // encontra com o cliente esperando.
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 460 ? 5 : 3;
        final espaco = 9.0;
        final largura =
            (constraints.maxWidth - espaco * (colunas - 1)) / colunas;

        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final method in PaymentMethod.values)
              SizedBox(
                width: largura,
                child: _BotaoDePagamento(
                  rotulo: method.label.toUpperCase(),
                  selecionado: selected == method,
                  onPressed: () => onChanged(method),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BotaoDePagamento extends StatelessWidget {
  const _BotaoDePagamento({
    required this.rotulo,
    required this.selecionado,
    required this.onPressed,
  });

  final String rotulo;
  final bool selecionado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final forma = RoundedRectangleBorder(
      side: BorderSide(
        color: selecionado ? Marca.azul : _Venda.borda,
        width: selecionado ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(_Toque.raio),
    );

    // A borda vai no `Material`, e não num `Container` por fora: assim o
    // `InkWell` ocupa os 56 inteiros em vez de nascer já descontado da borda —
    // dois pontos a menos de alvo de toque em cada forma de pagamento.
    return SizedBox(
      height: _Toque.altura,
      child: Material(
        color: selecionado ? Marca.azul : _Venda.cartao,
        shape: forma,
        child: InkWell(
          onTap: onPressed,
          customBorder: forma,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: _Toque.rotulo,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    color: selecionado ? Colors.white : _Venda.texto,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Mesmo cuidado do total: com a fonte ampliada, rótulo e valor disputam a
    // largura, e cortar um valor em dinheiro é pior que reduzi-lo.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Em que unidade o vendedor está digitando o desconto.
enum _ModoDoDesconto { percentual, valor }

/// Desconto negociado, com o teto do §13.3 aplicado na própria tela.
class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({required this.inicial, required this.subtotal});

  final SaleDiscount inicial;
  final Money subtotal;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

/// Desconto da venda (referência tela-desconto).
///
/// A referência oferece "DESCONTO RÁPIDO" de 5, 10, 15 e 20% e um campo de
/// valor em reais. Nenhum dos dois cabe aqui sem quebrar regra existente:
///
/// - o teto é 5% (13.3), e 10, 15 ou 20 produziriam uma venda que o servidor
///   recusa no envio — o vendedor descobriria só ao finalizar;
/// - `SaleCreateSerializer` aceita `discount_percent`, e não valor.
///
/// Mantive o desenho — cabeçalho laranja com subtotal e "fica em", atalhos,
/// teclado, "sem desconto" — e troquei o conteúdo: os atalhos ficam dentro do
/// teto.
///
/// Dá para digitar em % ou em R$, porque no balcão se negocia das duas formas
/// ("tira 5%" e "faz por 950"). O que muda é só a leitura do que se digita: o
/// modo valor converte para percentual em [discountPercentFromAmount] e daí
/// para baixo é o mesmo caminho de sempre, com o mesmo teto e sem campo novo
/// no backend.
class _DiscountDialogState extends State<_DiscountDialog> {
  static const _atalhos = [100, 200, 300, 500];

  /// Quantos dígitos cada modo aceita. Em percentual 99,99% já passa longe do
  /// teto; em reais o teto de uma venda grande precisa de mais casas.
  static const _limiteDeDigitos = {
    _ModoDoDesconto.percentual: 4,
    _ModoDoDesconto.valor: 8,
  };

  late _ModoDoDesconto _modo = widget.inicial.isAmount
      ? _ModoDoDesconto.valor
      : _ModoDoDesconto.percentual;

  late String _digitado = _doInicial();

  String _doInicial() {
    final valor = widget.inicial.amount;
    final bruto = valor?.cents ?? widget.inicial.hundredths;
    return bruto <= 0 ? '' : bruto.toString();
  }

  int get _numeroDigitado =>
      int.tryParse(_digitado.isEmpty ? '0' : _digitado) ?? 0;

  /// O que foi digitado lido como reais — só significa isso no modo valor.
  Money get _valorDigitado => Money.fromCents(_numeroDigitado);

  /// O desconto em negociação, na unidade em que está sendo digitado.
  ///
  /// É este objeto que sai do diálogo. O modo em reais não vira percentual no
  /// caminho: R$ 69,00 sobre R$ 1.387,93 não cabe em duas casas, e converter
  /// para calcular faria a venda receber R$ 68,98 — um número que ninguém
  /// combinou.
  SaleDiscount get _descontoNegociado => switch (_modo) {
        _ModoDoDesconto.percentual => SaleDiscount.percent(_numeroDigitado),
        _ModoDoDesconto.valor => SaleDiscount.amount(_valorDigitado),
      };

  /// Percentual equivalente, só para mostrar ao lado do valor.
  int get _hundredths => _descontoNegociado.percentOn(widget.subtotal);

  /// Teto de 5% medido na unidade negociada — o mesmo centavo que o backend
  /// confere, e não um percentual arredondado no meio do caminho.
  bool get _acimaDoTeto => _descontoNegociado.exceedsCapOn(widget.subtotal);

  /// O desconto que a venda vai receber, exatamente como vai receber.
  Money get _desconto => _acimaDoTeto
      ? const Money.zero()
      : _descontoNegociado.amountOn(widget.subtotal);

  void _trocarModo(_ModoDoDesconto modo) {
    if (modo == _modo) return;
    // Converte o que já está na tela em vez de zerar: sem isto o mesmo "500"
    // significaria 5% ou R$ 5,00 conforme o modo, que é exatamente a
    // ambiguidade que o seletor existe para evitar. A conversão parte do
    // desconto em reais, então ir de % para R$ não move o valor.
    final convertido = switch (modo) {
      _ModoDoDesconto.valor =>
        _descontoNegociado.amountOn(widget.subtotal).cents,
      _ModoDoDesconto.percentual => _hundredths,
    };
    setState(() {
      _modo = modo;
      _digitado = convertido <= 0 ? '' : convertido.toString();
    });
  }


  /// Atalho é sempre percentual; no modo valor entra o equivalente em reais.
  void _aplicarAtalho(int hundredths) {
    final valor = switch (_modo) {
      _ModoDoDesconto.percentual => hundredths,
      _ModoDoDesconto.valor => widget.subtotal.percent(hundredths).cents,
    };
    setState(() => _digitado = valor == 0 ? '' : valor.toString());
  }

  void _digitar(String digito) {
    if (_digitado.length + digito.length > _limiteDeDigitos[_modo]!) return;
    setState(() {
      _digitado = (_digitado + digito).replaceFirst(RegExp(r'^0+(?=\d)'), '');
    });
  }

  void _apagar() {
    if (_digitado.isEmpty) return;
    setState(() => _digitado = _digitado.substring(0, _digitado.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final fica = widget.subtotal - _desconto;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFD97B06),
              padding: const EdgeInsets.fromLTRB(26, 16, 26, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DESCONTO DA VENDA',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Colors.white.withValues(alpha: .85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Subtotal ${widget.subtotal.toDisplayString()}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Divide a largura com o subtotal e encolhe a fonte junto,
                  // como o lado esquerdo já fazia. Sem isto uma venda de
                  // R$ 10.000,00 empurrava o cabeçalho para fora do M10 — e
                  // quanto a venda fica é o número que não pode faltar aqui.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            'FICA EM',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
                              color: Colors.white.withValues(alpha: .85),
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            fica.toDisplayString(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _RotuloDoDesconto('DESCONTO RÁPIDO'),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        for (final (i, atalho) in _atalhos.indexed) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _AtalhoDeDesconto(
                              hundredths: atalho,
                              selecionado: _hundredths == atalho,
                              onPressed: () => _aplicarAtalho(atalho),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _RotuloDoDesconto('OU DIGITE EM'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _SeletorDeModo(modo: _modo, onTrocar: _trocarModo),
                      ],
                    ),
                    const SizedBox(height: 9),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final teclado = _TecladoDoDesconto(
                          onDigito: _digitar,
                          onApagar: _apagar,
                        );
                        final mostrador = _MostradorDoDesconto(
                          modo: _modo,
                          digitado: _valorDigitado,
                          hundredths: _hundredths,
                          desconto: _desconto,
                          acimaDoTeto: _acimaDoTeto,
                          onSemDesconto: () => Navigator.of(context)
                              .pop(const SaleDiscount.none()),
                        );

                        if (constraints.maxWidth < 520) {
                          return Column(
                            children: [
                              mostrador,
                              const SizedBox(height: 12),
                              teclado,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: mostrador),
                            const SizedBox(width: 18),
                            SizedBox(width: 276, child: teclado),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(66),
                        side: const BorderSide(color: _Venda.borda, width: 2),
                      ),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _Venda.texto,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      // Acima do teto o botão fica inativo em vez de recusar
                      // depois: o vendedor vê o limite antes de tentar.
                      onPressed: _acimaDoTeto || _descontoNegociado.isZero
                          ? null
                          : () =>
                              Navigator.of(context).pop(_descontoNegociado),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(66),
                        backgroundColor: const Color(0xFFD97B06),
                      ),
                      child: const Text(
                        'APLICAR DESCONTO',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RotuloDoDesconto extends StatelessWidget {
  const _RotuloDoDesconto(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
          color: _Venda.rotulo,
        ),
      );
}

class _AtalhoDeDesconto extends StatelessWidget {
  const _AtalhoDeDesconto({
    required this.hundredths,
    required this.selecionado,
    required this.onPressed,
  });

  final int hundredths;
  final bool selecionado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor:
              selecionado ? const Color(0xFFD97B06) : const Color(0xFFF7F9FD),
          foregroundColor: selecionado ? Colors.white : _Venda.painelEscuro,
          side: BorderSide(
            color: selecionado ? const Color(0xFFD97B06) : _Venda.borda,
          ),
          padding: EdgeInsets.zero,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatPercentDisplay(hundredths),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// Troca entre digitar o desconto em % e em R$.
///
/// Os dois rótulos ficam sempre visíveis, em vez de um botão que alterna: o
/// vendedor precisa ver em que unidade está antes de digitar, não descobrir
/// depois de errar a conta.
class _SeletorDeModo extends StatelessWidget {
  const _SeletorDeModo({required this.modo, required this.onTrocar});

  final _ModoDoDesconto modo;
  final ValueChanged<_ModoDoDesconto> onTrocar;

  @override
  Widget build(BuildContext context) {
    Widget opcao(_ModoDoDesconto alvo, String rotulo) {
      final ativo = modo == alvo;
      return SizedBox(
        height: 56,
        width: 58,
        child: FilledButton(
          onPressed: () => onTrocar(alvo),
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor:
                ativo ? const Color(0xFFD97B06) : const Color(0xFFF7F9FD),
            foregroundColor: ativo ? Colors.white : _Venda.painelEscuro,
            side: BorderSide(
              color: ativo ? const Color(0xFFD97B06) : _Venda.borda,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              rotulo,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        opcao(_ModoDoDesconto.percentual, '%'),
        const SizedBox(width: 8),
        opcao(_ModoDoDesconto.valor, 'R\$'),
      ],
    );
  }
}

/// Uma das duas leituras do desconto: rótulo pequeno, valor embaixo.
class _LeituraDoDesconto extends StatelessWidget {
  const _LeituraDoDesconto({
    required this.rotulo,
    required this.valor,
    this.alerta = false,
  });

  final String rotulo;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        border: Border.all(color: _Venda.borda),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: _Venda.rotulo,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: alerta
                    ? Theme.of(context).colorScheme.error
                    : _Venda.texto,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O desconto em construção: o número grande na unidade que se está digitando
/// e, embaixo, as duas leituras dele.
///
/// As duas aparecem sempre, nos dois modos. Quem digita 5% quer saber quanto
/// sai do caixa; quem digita R$ 50,00 precisa do percentual, porque o teto é
/// percentual. Mostrar só a unidade digitada deixaria a conta para a cabeça do
/// vendedor justamente na hora de negociar.
class _MostradorDoDesconto extends StatelessWidget {
  const _MostradorDoDesconto({
    required this.modo,
    required this.digitado,
    required this.hundredths,
    required this.desconto,
    required this.acimaDoTeto,
    required this.onSemDesconto,
  });

  final _ModoDoDesconto modo;
  final Money digitado;
  final int hundredths;
  final Money desconto;
  final bool acimaDoTeto;
  final VoidCallback onSemDesconto;

  @override
  Widget build(BuildContext context) {
    final emReais = modo == _ModoDoDesconto.valor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _Venda.painelEscuro,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    emReais
                        ? digitado.toDisplayString()
                        : formatPercentDisplay(hundredths),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Container(width: 3, height: 32, color: Marca.amarelo),
            ],
          ),
        ),
        const SizedBox(height: 9),
        // O par que o vendedor confere antes de aplicar; o cabeçalho completa
        // com o subtotal e com quanto a venda fica.
        Row(
          children: [
            Expanded(
              child: _LeituraDoDesconto(
                rotulo: 'DESCONTO',
                valor: acimaDoTeto ? '—' : '- ${desconto.toDisplayString()}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LeituraDoDesconto(
                rotulo: 'EQUIVALE A',
                valor: formatPercentDisplay(hundredths),
                alerta: acimaDoTeto,
              ),
            ),
          ],
        ),
        if (acimaDoTeto) ...[
          const SizedBox(height: 8),
          Text(
            'O desconto máximo é de 5%.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: onSemDesconto,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            side: const BorderSide(color: _Venda.borda, width: 2),
          ),
          icon: const Icon(Icons.close, size: 20, color: _Venda.texto),
          label: const Text(
            'SEM DESCONTO',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _Venda.texto,
            ),
          ),
        ),
      ],
    );
  }
}

class _TecladoDoDesconto extends StatelessWidget {
  const _TecladoDoDesconto({required this.onDigito, required this.onApagar});

  final ValueChanged<String> onDigito;
  final VoidCallback onApagar;

  @override
  Widget build(BuildContext context) {
    Widget tecla(String rotulo) => Expanded(
          child: _TeclaDoDesconto(
              rotulo: rotulo, onPressed: () => onDigito(rotulo)),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final linha in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ]) ...[
          SizedBox(
            height: 62,
            child: Row(
              children: [
                for (final (i, d) in linha.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  tecla(d),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 62,
          child: Row(
            children: [
              tecla('0'),
              const SizedBox(width: 8),
              tecla('00'),
              const SizedBox(width: 8),
              Expanded(
                child: _TeclaDoDesconto(
                  icone: Icons.backspace_outlined,
                  onPressed: onApagar,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TeclaDoDesconto extends StatelessWidget {
  const _TeclaDoDesconto({
    this.rotulo,
    this.icone,
    required this.onPressed,
  });

  final String? rotulo;
  final IconData? icone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        border: Border.all(color: _Venda.borda),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: icone != null
                ? Icon(icone, size: 22, color: _Venda.texto)
                : Text(
                    rotulo!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _Venda.painelEscuro,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Medidas dos controles que o vendedor toca nesta tela.
///
/// Uma fonte só para altura, raio e tipografia: teclas do teclado, formas de
/// pagamento, CLIENTE e DESCONTO. Cada um tinha a sua antes — o DESCONTO vinha
/// com o `OutlinedButton` do tema, que é pílula verde de raio 20, e destoava do
/// CLIENTE ao lado.
class _Toque {
  const _Toque._();

  /// Altura mínima de qualquer alvo de toque. O M10 é operado com o dedo, em
  /// pé, e alvo curto aqui custa venda lançada errada.
  static const double altura = 56;

  /// Raio único, o das teclas da referência.
  static const double raio = 14;

  /// Rótulo dos botões de ação e de pagamento.
  static const double rotulo = 18;

  /// Dígitos do teclado — o que se lê de relance enquanto se digita.
  static const double digito = 26;

  /// Casca comum de CLIENTE e DESCONTO: mesma altura, mesmo raio, mesma borda.
  static ButtonStyle acao({required bool alerta, required ColorScheme cores}) =>
      OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(altura),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: BorderSide(color: alerta ? cores.error : _Venda.borda),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(raio),
        ),
      );
}

class _BotaoDeCliente extends StatelessWidget {
  const _BotaoDeCliente({
    required this.temCliente,
    required this.obrigatorio,
    required this.onPressed,
  });

  final bool temCliente;
  final bool obrigatorio;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faltando = obrigatorio && !temCliente;

    final cor = faltando ? theme.colorScheme.error : _Venda.texto;

    return OutlinedButton(
      onPressed: onPressed,
      style: _Toque.acao(alerta: faltando, cores: theme.colorScheme),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 22, color: cor),
            const SizedBox(width: 10),
            Text(
              temCliente ? 'TROCAR' : 'CLIENTE',
              style: TextStyle(
                fontSize: _Toque.rotulo,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: cor,
              ),
            ),
            if (!temCliente) ...[
              const SizedBox(width: 6),
              Text(
                obrigatorio ? '(obrigatório)' : '(opcional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: faltando ? theme.colorScheme.error : _Venda.rotulo,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Desconto da venda, gêmeo do botão de cliente.
///
/// Mesma casca do CLIENTE ao lado — altura, raio, borda, caixa e peso do texto.
/// Com desconto aplicado, ícone e rótulo vão para o azul da marca; era o verde
/// do tema do Material que aparecia aqui, que não é cor deste PDV.
class _BotaoDeDesconto extends StatelessWidget {
  const _BotaoDeDesconto({required this.percentual, required this.onPressed});

  /// Desconto em centésimos de ponto percentual, como no rascunho da venda.
  final int percentual;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final aplicado = percentual != 0;
    final cor = aplicado ? Marca.azul : _Venda.texto;

    return OutlinedButton(
      onPressed: onPressed,
      style: _Toque.acao(alerta: false, cores: Theme.of(context).colorScheme),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.percent, size: 22, color: cor),
            const SizedBox(width: 10),
            Text(
              aplicado ? formatPercentDisplay(percentual) : 'DESCONTO',
              style: TextStyle(
                fontSize: _Toque.rotulo,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O cliente da venda, com o que ele já deve na loja (§7, D4, RF15).
///
/// O total em aberto aparece aqui, e não só na tela de busca, porque a decisão
/// de fiar acontece na composição da venda — depois que o vendedor já escolheu
/// e seguiu montando. Ver o número só uma vez, três telas atrás, não ajuda.
class _ClienteEscolhido extends StatelessWidget {
  const _ClienteEscolhido({
    required this.customer,
    required this.receivables,
    required this.onTrocar,
  });

  final Customer customer;
  final List<Receivable>? receivables;
  final VoidCallback onTrocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lista = receivables;
    final devendo = lista?.totalOutstanding;
    final vencida = lista != null && lista.hasOverdue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: vencida
            ? theme.colorScheme.errorContainer
            : const Color(0xFFF2F4FA),
        border: Border.all(
          color: vencida ? theme.colorScheme.error : const Color(0xFFDFE4F1),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            vencida ? Icons.warning_amber : Icons.person,
            color: vencida
                ? theme.colorScheme.onErrorContainer
                : const Color(0xFF0E1B52),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E1B52),
                  ),
                ),
                if (customer.phone case final String telefone
                    when telefone.isNotEmpty)
                  Text(
                    telefone,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5B6480),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  switch (devendo) {
                    // Sem consulta é diferente de sem dívida: dizer "nada em
                    // aberto" quando a rede caiu seria mentir num ponto que
                    // decide se a venda sai fiada.
                    null => 'Pendências não consultadas',
                    final valor when valor.isPositive =>
                      'Total em aberto: ${valor.toDisplayString()}'
                          '${vencida ? ' · VENCIDA' : ''}',
                    _ => 'Nada em aberto',
                  },
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: vencida
                        ? theme.colorScheme.onErrorContainer
                        : const Color(0xFF5B6480),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Trocar cliente',
            onPressed: onTrocar,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Tons da tela de venda, vindos da referência.
class _Venda {
  const _Venda._();

  static const Color cartao = Colors.white;
  static const Color borda = Color(0xFFDFE4F1);
  static const Color painelEscuro = Color(0xFF0E1B52);
  static const Color rotulo = Color(0xFF5B6480);
  static const Color texto = Color(0xFF3C4257);
  static const Color teclaSombra = Color(0xFFDBE1EF);
  static const Color auxFundo = Color(0xFFE3E8F5);
  static const Color auxBorda = Color(0xFFCFD7EA);
  static const Color auxSombra = Color(0xFFC3CBE0);
  static const Color desarmadoFundo = Color(0xFFF3F5FB);
  static const Color desarmadoTexto = Color(0xFF8189A1);
  static const Color desarmadoBorda = Color(0xFFCFD7EA);

  /// Cores por categoria, como na referência. O que não estiver mapeado cai no
  /// azul da marca — categoria nova no catálogo não pode quebrar a tela.
  /// Ícone e exemplos por categoria, como na referência. São texto de tela,
  /// não dado do catálogo — o backend guarda só código e nome.
  static IconData iconeDaCategoria(String code) => switch (code) {
        'PECAS' => Icons.settings,
        'PNEUS' => Icons.trip_origin,
        'OLEOS' => Icons.water_drop,
        _ => Icons.sell_outlined,
      };

  static String exemploDaCategoria(String code) => switch (code) {
        'PECAS' => 'freios, câmaras, correntes',
        'PNEUS' => 'aro 26, 29, moto',
        'OLEOS' => 'lubrificantes, aditivos',
        _ => '',
      };

  static Color corDaCategoria(String code) => switch (code) {
        'PECAS' => const Color(0xFF0020AD),
        'PNEUS' => const Color(0xFF1D1D2E),
        'OLEOS' => const Color(0xFFD97B06),
        _ => Marca.azul,
      };
}

/// Cabeçalho azul: menu, título, vendedor e a saída (§6 do fluxo).
class _CabecalhoDaVenda extends StatelessWidget {
  const _CabecalhoDaVenda({
    required this.vendedor,
    required this.conectividade,
    required this.compacto,
    required this.onMenu,
    required this.onSair,
  });

  final String? vendedor;
  final ConnectivityChannel conectividade;
  final bool compacto;
  final VoidCallback onMenu;
  final VoidCallback onSair;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compacto ? 56 : 66,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF132A9E), Marca.azul],
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onMenu,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: compacto ? 40 : 44,
              height: compacto ? 40 : 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.menu, color: Colors.white, size: 22),
            ),
          ),
          SizedBox(width: compacto ? 10 : 16),
          // Título e pílula do vendedor disputam a largura no retrato; os
          // O título toma a esquerda inteira; é ele que empurra o vendedor e o
          // SAIR para o canto direito. Antes o espaço livre era dividido entre
          // título, `Spacer` e pílula, e a pílula ficava parada no começo da
          // fatia dela — daí o vendedor e o SAIR aparecerem no meio da barra.
          Expanded(
            child: Text(
              'NOVA VENDA',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compacto ? 17 : 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Vendedor e rede na mesma pílula: é o que a barra do terminal
          // mostrava, no lugar que a referência reserva para o vendedor.
          ListenableBuilder(
            listenable: conectividade,
            builder: (context, _) => Container(
              padding: EdgeInsets.only(
                left: 6,
                right: compacto ? 10 : 16,
                top: 5,
                bottom: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Marca.amarelo,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 17,
                      color: Marca.azul,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Teto de largura no nome: sem ele um nome comprido
                  // esticaria a pílula e empurraria o SAIR para fora da
                  // barra, já que o grupo da direita tem largura própria.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compacto ? 104 : 190,
                    ),
                    child: Text(
                      (vendedor ?? 'VENDEDOR').toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 13 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    conectividade.isOnline ? Icons.cloud_done : Icons.cloud_off,
                    size: 16,
                    color:
                        conectividade.isOnline ? Colors.white : Marca.amarelo,
                  ),
                ],
              ),
            ),
          ),
          // Vendedor e SAIR são um grupo só, colado no canto, com o respiro da
          // referência entre os dois.
          const SizedBox(width: 16),
          InkWell(
            onTap: onSair,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compacto ? 8 : 14,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.logout, color: Colors.white, size: 20),
                  if (!compacto) ...[
                    const SizedBox(width: 9),
                    const Text(
                      'SAIR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Passo 1: o valor digitado e a quantidade.
class _PainelDoValor extends StatelessWidget {
  const _PainelDoValor({required this.controller, required this.compacto});

  final NewSaleController controller;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(compacto ? 14 : 20, 12, compacto ? 14 : 20, 14),
      decoration: BoxDecoration(
        color: _Venda.painelEscuro,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PASSO 1 · DIGITE O VALOR',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compacto ? 11 : 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: Colors.white.withValues(alpha: .85),
                  ),
                ),
              ),
              _BotaoDeQuantidade(
                rotulo: '−',
                onPressed: () => controller.mudarQuantidade(-1),
                compacto: compacto,
              ),
              SizedBox(
                width: compacto ? 56 : 62,
                child: Text(
                  'QTD ${controller.quantidade}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compacto ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              _BotaoDeQuantidade(
                rotulo: '+',
                onPressed: () => controller.mudarQuantidade(1),
                compacto: compacto,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'R\$',
                style: TextStyle(
                  fontSize: compacto ? 17 : 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: .8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    controller.valorDigitado.toDisplayString(symbol: false),
                    style: TextStyle(
                      fontSize: compacto ? 36 : 50,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Container(
                width: 3,
                height: compacto ? 30 : 40,
                color: Marca.amarelo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotaoDeQuantidade extends StatelessWidget {
  const _BotaoDeQuantidade({
    required this.rotulo,
    required this.onPressed,
    required this.compacto,
  });

  final String rotulo;
  final VoidCallback onPressed;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final lado = compacto ? 40.0 : 48.0;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: lado,
        height: lado,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          rotulo,
          style: TextStyle(
            fontSize: compacto ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Teclado do valor: dígitos, 00 e apagar.
class _TecladoDoValor extends StatelessWidget {
  const _TecladoDoValor({required this.controller, required this.compacto});

  final NewSaleController controller;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final espaco = compacto ? 8.0 : 10.0;

    Widget tecla(String rotulo) => Expanded(
          child: _Tecla(
            rotulo: rotulo,
            compacto: compacto,
            onPressed: () => controller.digitar(rotulo),
          ),
        );

    return Column(
      children: [
        for (final linha in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ]) ...[
          Expanded(
            child: Row(
              children: [
                for (final (i, d) in linha.indexed) ...[
                  if (i > 0) SizedBox(width: espaco),
                  tecla(d),
                ],
              ],
            ),
          ),
          SizedBox(height: espaco),
        ],
        Expanded(
          child: Row(
            children: [
              tecla('0'),
              SizedBox(width: espaco),
              tecla('00'),
              SizedBox(width: espaco),
              Expanded(
                child: _Tecla(
                  icone: Icons.backspace_outlined,
                  compacto: compacto,
                  auxiliar: true,
                  onPressed: controller.apagarDigito,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla({
    this.rotulo,
    this.icone,
    required this.compacto,
    required this.onPressed,
    this.auxiliar = false,
  });

  final String? rotulo;
  final IconData? icone;
  final bool compacto;
  final bool auxiliar;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: auxiliar ? _Venda.auxFundo : _Venda.cartao,
        border: Border.all(
          color: auxiliar ? _Venda.auxBorda : _Venda.borda,
        ),
        borderRadius: BorderRadius.circular(_Toque.raio),
        boxShadow: [
          BoxShadow(
            color: auxiliar ? _Venda.auxSombra : _Venda.teclaSombra,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_Toque.raio),
          child: Center(
            child: icone != null
                ? Icon(icone, size: compacto ? 22 : 26, color: _Venda.texto)
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      rotulo!,
                      style: TextStyle(
                        fontSize: compacto ? _Toque.digito : 32,
                        fontWeight: FontWeight.w800,
                        color: _Venda.painelEscuro,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Passo 2: em que categoria entra o valor digitado.
///
/// As categorias ficam apagadas enquanto não há valor. É a ordem da
/// referência, e ela resolve sozinha um problema real: sem valor, tocar a
/// categoria não teria o que lançar.
class _PassoDaCategoria extends StatelessWidget {
  const _PassoDaCategoria({
    required this.controller,
    required this.compacto,
    required this.onLancar,
  });

  final NewSaleController controller;
  final bool compacto;
  final ValueChanged<ProductCategory> onLancar;

  @override
  Widget build(BuildContext context) {
    final armado = controller.podeLancar;
    final valor = controller.valorDigitado.toDisplayString();
    final quantidade = controller.quantidade;

    if (!controller.categoriesLoaded) {
      return const SizedBox(
        height: 120,
        child: LoadingView(label: 'Carregando categorias...'),
      );
    }
    if (controller.categories.isEmpty) {
      return _SemCategorias(onRetry: controller.loadCategories);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          armado
              ? 'PASSO 2 · $valor${quantidade > 1 ? ' × $quantidade' : ''} — O QUE É ESTE VALOR?'
              : 'PASSO 2 · DIGITE UM VALOR PARA ESCOLHER O TIPO',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compacto ? 11 : 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: armado ? Marca.azul : _Venda.rotulo,
          ),
        ),
        SizedBox(height: compacto ? 8 : 12),
        Row(
          children: [
            for (final (i, categoria) in controller.categories.indexed) ...[
              if (i > 0) SizedBox(width: compacto ? 8 : 12),
              Expanded(
                child: _CartaoDeCategoria(
                  categoria: categoria,
                  armado: armado,
                  compacto: compacto,
                  onPressed: () => onLancar(categoria),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CartaoDeCategoria extends StatelessWidget {
  const _CartaoDeCategoria({
    required this.categoria,
    required this.armado,
    required this.compacto,
    required this.onPressed,
  });

  final ProductCategory categoria;
  final bool armado;
  final bool compacto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cor = _Venda.corDaCategoria(categoria.code);

    return Container(
      // No retrato o cartão cede um pouco de altura para o teclado; o conteúdo
      // é escalado pelo `FittedBox` abaixo, então a caixa menor não corta nem
      // ícone nem texto, e 72 segue muito acima do alvo de toque.
      height: compacto ? 72 : 126,
      decoration: BoxDecoration(
        color: armado ? cor : _Venda.desarmadoFundo,
        border: Border.all(
          color: armado ? cor : _Venda.desarmadoBorda,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: armado
            ? const [
                BoxShadow(color: Color(0x38000000), offset: Offset(0, 7)),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: armado ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _Venda.iconeDaCategoria(categoria.code),
                      size: compacto ? 20 : 26,
                      color: armado ? Marca.amarelo : const Color(0xFFA8B0C6),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      categoria.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compacto ? 18 : 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        height: 1,
                        color: armado ? Colors.white : _Venda.desarmadoTexto,
                      ),
                    ),
                    if (_Venda.exemploDaCategoria(categoria.code)
                        .isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        _Venda.exemploDaCategoria(categoria.code),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compacto ? 11 : 14,
                          fontWeight: FontWeight.w600,
                          color: armado
                              ? Colors.white.withValues(alpha: .88)
                              : _Venda.rotulo,
                        ),
                      ),
                    ],
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

class _SemCategorias extends StatelessWidget {
  const _SemCategorias({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Venda.cartao,
        border: Border.all(color: _Venda.borda),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Nenhuma categoria disponível.\nSem elas não há como lançar a venda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _Venda.rotulo),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

/// Corpo em duas colunas, como na referência de 1280x800.
class _CorpoLargo extends StatelessWidget {
  const _CorpoLargo({
    required this.controller,
    required this.onLancar,
    required this.onPickCustomer,
    required this.onEditDiscount,
    required this.onFinish,
  });

  final NewSaleController controller;
  final ValueChanged<ProductCategory> onLancar;
  final VoidCallback onPickCustomer;
  final VoidCallback onEditDiscount;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 452,
            child: Column(
              children: [
                _PainelDoValor(controller: controller, compacto: false),
                const SizedBox(height: 12),
                Expanded(
                  child:
                      _TecladoDoValor(controller: controller, compacto: false),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PassoDaCategoria(
                  controller: controller,
                  compacto: false,
                  onLancar: onLancar,
                ),
                const SizedBox(height: 12),
                Expanded(
                  flex: 2,
                  child: _ListaDeItens(controller: controller, compacto: false),
                ),
                const SizedBox(height: 12),
                // `Flexible`: o painel cresce com o que a venda exige — notinha,
                // avisos, desconto — e sem limite ele engolia a lista de itens
                // acima dele.
                // Três para dois: o painel precisa caber inteiro, com o
                // total e o botão de finalizar visíveis sem rolar — a lista de
                // itens é que rola quando a venda cresce.
                Expanded(
                  flex: 3,
                  child: _CartPanel(
                    controller: controller,
                    onPickCustomer: onPickCustomer,
                    onEditDiscount: onEditDiscount,
                    onFinish: onFinish,
                    semItens: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Corpo em coluna única, para o retrato do M10.
///
/// A referência é de uma tela larga, com o teclado ao lado da venda. Em
/// retrato os dois não cabem lado a lado, então a ordem vira a do gesto:
/// valor, categoria, e a venda logo abaixo, rolando.
class _CorpoEstreito extends StatelessWidget {
  const _CorpoEstreito({
    required this.controller,
    required this.onLancar,
    required this.onPickCustomer,
    required this.onEditDiscount,
    required this.onFinish,
  });

  final NewSaleController controller;
  final ValueChanged<ProductCategory> onLancar;
  final VoidCallback onPickCustomer;
  final VoidCallback onEditDiscount;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              _PainelDoValor(controller: controller, compacto: true),
              const SizedBox(height: 10),
              _PassoDaCategoria(
                controller: controller,
                compacto: true,
                onLancar: onLancar,
              ),
              if (controller.ultimaLinha != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _BarraDeDesfazer(
                    linha: controller.ultimaLinha,
                    onDesfazer: controller.desfazerUltimo,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Sete para três, e não cinco para quatro: com a divisão antiga as
        // quatro fileiras do teclado ficavam com ~45 de altura e a última saía
        // cortada pelo painel da venda — que é rolável e não perde nada com a
        // fatia menor, enquanto tecla curta custa toque errado. O respiro de
        // cima separa as teclas da sombra dura dos cartões de categoria, que
        // encostava na primeira fileira.
        Expanded(
          flex: 7,
          child: Padding(
            // Respiro embaixo também: sem ele a sombra dura da última fileira
            // morria por baixo do painel da venda, e a fileira parecia cortada.
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: _TecladoDoValor(controller: controller, compacto: true),
          ),
        ),
        Flexible(
          flex: 3,
          child: _CartPanel(
            controller: controller,
            onPickCustomer: onPickCustomer,
            onEditDiscount: onEditDiscount,
            onFinish: onFinish,
          ),
        ),
      ],
    );
  }
}

/// Os itens já lançados, com a etiqueta da categoria (§6 — composição).
class _ListaDeItens extends StatelessWidget {
  const _ListaDeItens({required this.controller, required this.compacto});

  final NewSaleController controller;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final totais = controller.totals;

    return Container(
      decoration: BoxDecoration(
        color: _Venda.cartao,
        border: Border.all(color: _Venda.borda),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 11, 12, 11),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFEEF1F8)),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'ITENS DA VENDA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: _Venda.rotulo,
                  ),
                ),
                const Spacer(),
                for (final entrada in _contagemPorCategoria(draft.lines))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _Venda.corDaCategoria(entrada.$1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${entrada.$3} ${entrada.$2}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: draft.isEmpty
                // Rolável: com a fonte do sistema ampliada, ícone mais duas
                // linhas passam da altura da lista vazia.
                ? const Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 42,
                            color: Color(0xFFC3CADD),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Nenhum item lançado',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _Venda.rotulo,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Digite o valor e escolha o tipo do produto',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: _Venda.rotulo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: draft.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, indice) {
                      // De trás para a frente: o que acabou de ser lançado é o
                      // que o vendedor quer conferir.
                      final posicao = draft.lines.length - 1 - indice;
                      return _LinhaDoItem(
                        line: draft.lines[posicao],
                        total: totais.lineTotals[posicao],
                        onRemove: () =>
                            controller.remove(draft.lines[posicao].id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Quantas linhas por categoria, na ordem em que apareceram.
  ///
  /// Devolve código, contagem e rótulo — o rótulo sai da própria linha, e não
  /// de uma tabela à parte que poderia divergir do que foi vendido.
  List<(String, int, String)> _contagemPorCategoria(
      List<SaleDraftLine> linhas) {
    final contagem = <String, int>{};
    final rotulos = <String, String>{};
    for (final linha in linhas) {
      contagem[linha.categoryCode] = (contagem[linha.categoryCode] ?? 0) + 1;
      rotulos[linha.categoryCode] = linha.label.toUpperCase();
    }
    return [
      for (final e in contagem.entries) (e.key, e.value, rotulos[e.key] ?? ''),
    ];
  }
}

class _LinhaDoItem extends StatelessWidget {
  const _LinhaDoItem({
    required this.line,
    required this.total,
    required this.onRemove,
  });

  final SaleDraftLine line;
  final Money total;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cor = _Venda.corDaCategoria(line.categoryCode);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        border: Border.all(color: const Color(0xFFE6EAF4), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              line.label.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              line.quantity == const Quantity.units(1)
                  ? 'quantidade 1'
                  : '${line.quantity.toDisplayString()} × '
                      '${line.unitPrice.toDisplayString()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _Venda.rotulo,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            total.toDisplayString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _Venda.painelEscuro,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Remover',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20),
            color: const Color(0xFFC0392B),
          ),
        ],
      ),
    );
  }
}

/// Desfazer o último lançamento, por alguns segundos (referência).
///
/// Existe pelo erro mais comum do balcão: digitar o valor e tocar na categoria
/// errada. Sem isto, a saída é achar a linha na lista e removê-la — o que dá
/// certo, mas custa atenção num momento em que o cliente está esperando.
class _BarraDeDesfazer extends StatelessWidget {
  const _BarraDeDesfazer({required this.linha, required this.onDesfazer});

  final SaleDraftLine? linha;
  final VoidCallback onDesfazer;

  @override
  Widget build(BuildContext context) {
    final atual = linha;
    if (atual == null) return const SizedBox.shrink();

    return Material(
      color: _Venda.painelEscuro,
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '${atual.label.toUpperCase()} '
                '${atual.grossAmount.toDisplayString()} lançado',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Material(
              color: Marca.amarelo,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: onDesfazer,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.undo, size: 18, color: _Venda.painelEscuro),
                      SizedBox(width: 8),
                      Text(
                        'DESFAZER',
                        style: TextStyle(
                          color: _Venda.painelEscuro,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confere a venda antes de imprimir (referência: CONFERIR E FINALIZAR).
///
/// O documento 1 sai impresso e vai com o cliente até o caixa: corrigir depois
/// custa alteração aprovada por gerente (§3.4.5). Uma conferência antes é mais
/// barata que isso, e é o que a referência coloca entre montar e imprimir.
Future<void> _conferirEFinalizar(
  BuildContext context,
  NewSaleController controller,
  VoidCallback onFinish,
) async {
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (_) => _ConferenciaDaVenda(controller: controller),
  );
  if (confirmou ?? false) onFinish();
}

class _ConferenciaDaVenda extends StatelessWidget {
  const _ConferenciaDaVenda({required this.controller});

  final NewSaleController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final totais = controller.totals;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: _Venda.painelEscuro,
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CONFIRA ANTES DE IMPRIMIR',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: .75),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    draft.paymentMethod.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < draft.lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LinhaDaConferencia(
                          line: draft.lines[i],
                          total: totais.lineTotals[i],
                        ),
                      ),
                    if (totais.discount.isPositive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF0DE),
                          border: Border.all(color: const Color(0xFFF3D7A8)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'DESCONTO',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8A4B00),
                                ),
                              ),
                            ),
                            Text(
                              '- ${totais.discount.toDisplayString()}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF8A4B00),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (draft.customer case final cliente?) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cliente.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF1F8))),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: _Venda.rotulo,
                        ),
                      ),
                      Text(
                        draft.lineCount == 1
                            ? '1 item'
                            : '${draft.lineCount} itens',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _Venda.rotulo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        totais.total.toDisplayString(),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: _Venda.painelEscuro,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 22),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(66),
                        side: const BorderSide(color: _Venda.borda, width: 2),
                      ),
                      child: const Text(
                        'VOLTAR E CORRIGIR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _Venda.texto,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(66),
                        backgroundColor: Marca.laranja,
                      ),
                      icon: const Icon(Icons.print),
                      label: const Text(
                        'CONFIRMAR E IMPRIMIR',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaDaConferencia extends StatelessWidget {
  const _LinhaDaConferencia({required this.line, required this.total});

  final SaleDraftLine line;
  final Money total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _Venda.corDaCategoria(line.categoryCode),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            line.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _Venda.painelEscuro,
            ),
          ),
        ),
        if (line.quantity != const Quantity.units(1))
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              '${line.quantity.toDisplayString()} × '
              '${line.unitPrice.toDisplayString()}',
              style: const TextStyle(fontSize: 14, color: _Venda.rotulo),
            ),
          ),
        Text(
          total.toDisplayString(),
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: _Venda.painelEscuro,
          ),
        ),
      ],
    );
  }
}
