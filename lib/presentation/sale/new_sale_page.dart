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
import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/product.dart';
import '../../domain/rules/sale_draft.dart';
import '../../domain/rules/sale_pricing.dart';
import '../../domain/usecases/create_sale.dart';
import '../shared/feedback.dart';
import '../shared/terminal_bar.dart';
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
        appBar: AppBar(
          title: const Text('NOVA VENDA'),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: _openMenu,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sair',
              onPressed: _exit,
            ),
          ],
        ),
        body: Column(
          children: [
            TerminalBar(session: deps.session, connectivity: deps.connectivity),
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
                  onAdd: _controller.add,
                ),
              ),
            ),
            // `Flexible` e não altura livre: o painel cresce com o que a venda
            // exige — a composição, o painel da notinha, a lista de problemas —
            // e na tela de 5" do M10 isso passa do que sobra. Encolhendo, o
            // conteúdo rola por dentro em vez de sair pela borda.
            Flexible(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _CartPanel(
                  controller: _controller,
                  onPickCustomer: _pickCustomer,
                  onEditDiscount: _editDiscount,
                  onFinish: _finish,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Leitor de código'),
              subtitle: const Text('Localiza a venda pelo código do documento'),
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
    );

    if (!mounted || destino == null) return;
    if (destino == 'descartar') {
      await _confirmDiscard();
      return;
    }
    await navigator.pushNamed(destino);
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

  Future<void> _pickCustomer() async {
    final customer = await Navigator.of(context).push<Customer>(
      MaterialPageRoute(builder: (_) => const CustomerPickerPage()),
    );
    if (customer != null) _controller.setCustomer(customer);
  }

  Future<void> _editDiscount() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _DiscountDialog(
        initialHundredths: _controller.draft.discountPercentHundredths,
      ),
    );
    if (result != null) _controller.setDiscountPercent(result);
  }

  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    final result = await _controller.finish();

    if (!mounted) return;

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
  });

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
              if (draft.isEmpty)
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
                              controller.increment(draft.lines[i].product.id),
                          onDecrement: () =>
                              controller.decrement(draft.lines[i].product.id),
                          onRemove: () => controller.remove(draft.lines[i].product.id),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickCustomer,
                      icon: const Icon(Icons.person_outline),
                      label: Text(
                        draft.customer?.name ?? 'Cliente',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEditDiscount,
                      icon: const Icon(Icons.percent),
                      label: Text(
                        draft.discountPercentHundredths == 0
                            ? 'Desconto'
                            : formatPercentDisplay(draft.discountPercentHundredths),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (totals.discount.isPositive) ...[
                _TotalRow(label: 'Subtotal', value: totals.gross.toDisplayString()),
                _TotalRow(
                  label: 'Desconto',
                  value: '- ${totals.discount.toDisplayString()}',
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(totals.total.toDisplayString(), style: AppTheme.totalStyle(context)),
                ],
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
                onPressed: controller.canFinish ? onFinish : null,
                icon: controller.isSubmitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: const Text('Finalizar e imprimir'),
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
              Text(line.product.name, overflow: TextOverflow.ellipsis),
              Text(
                '${line.quantity.toDisplayString()} x '
                '${line.product.price.toDisplayString()}',
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
    // `Wrap` e não fileira rolável: as cinco formas cabem em duas linhas na
    // largura do M10, e forma de pagamento escondida atrás de rolagem
    // horizontal é forma que o vendedor não encontra com o cliente esperando.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final method in PaymentMethod.values)
          ChoiceChip(
            label: Text(method.label),
            selected: selected == method,
            onSelected: (_) => onChanged(method),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Desconto negociado, com o teto do §13.3 aplicado na própria tela.
class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({required this.initialHundredths});

  final int initialHundredths;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialHundredths == 0
        ? ''
        : formatPercentApi(widget.initialHundredths),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final parsed = parsePercentHundredths(_controller.text);
    if (parsed == null) {
      setState(() => _error = 'Percentual inválido.');
      return;
    }
    if (parsed > maxDiscountPercentHundredths) {
      // O backend também recusa (13.3); barrar aqui evita a viagem à rede e a
      // explicação atravessada de um 400 no meio do atendimento.
      setState(() => _error = 'O desconto máximo é de 5%.');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Desconto da venda'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Percentual',
              suffixText: '%',
              errorText: _error,
              helperText: 'Máximo de 5% sobre o total da venda.',
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(0),
          child: const Text('Sem desconto'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Aplicar')),
      ],
    );
  }
}
