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
          title: const Text('Nova venda'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmDiscard,
          ),
        ),
        body: Column(
          children: [
            TerminalBar(session: deps.session, connectivity: deps.connectivity),
            _SearchField(
              controller: _searchController,
              onChanged: _controller.searchDebounced,
              onSubmitted: _addTypedCode,
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
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => _CartPanel(
                controller: _controller,
                onPickCustomer: _pickCustomer,
                onEditDiscount: _editDiscount,
                onFinish: _finish,
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

  Future<void> _confirmDiscard() async {
    if (_controller.draft.isEmpty) {
      Navigator.of(context).pop();
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

    if ((discard ?? false) && mounted) Navigator.of(context).pop();
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
        child: Padding(
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

class _PaymentSelector extends StatelessWidget {
  const _PaymentSelector({required this.selected, required this.onChanged});

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final method in PaymentMethod.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(method.label),
                selected: selected == method,
                onSelected: (_) => onChanged(method),
              ),
            ),
        ],
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
