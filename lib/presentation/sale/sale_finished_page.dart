/// Desfecho da venda: o que foi registrado e o que saiu na impressora.
///
/// A tela existe por causa de um caso concreto: a venda é registrada e o papel
/// **não** sai — acabou a bobina. A venda continua válida, o cliente está no
/// balcão, e o que resolve é reimprimir, não refazer. Por isso o estado da
/// impressão aparece em destaque, separado do estado da venda, e a reimpressão
/// é o botão principal quando a impressão falhou.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/entities/sale.dart';
import '../../domain/usecases/create_sale.dart';
import '../shared/feedback.dart';

class SaleFinishedPage extends StatefulWidget {
  const SaleFinishedPage({required this.finished, super.key});

  final SaleFinished finished;

  @override
  State<SaleFinishedPage> createState() => _SaleFinishedPageState();
}

class _SaleFinishedPageState extends State<SaleFinishedPage> {
  bool _reprinting = false;
  late bool _printed = widget.finished.printed;

  Sale get _sale => widget.finished.result.sale;

  Future<void> _reprint() async {
    setState(() => _reprinting = true);

    final result = await context.deps.reprintDocument(_sale.id, DocumentType.doc1);

    if (!mounted) return;
    setState(() => _reprinting = false);

    switch (result) {
      case Ok(:final value):
        setState(() => _printed = true);
        showMessage(
          context,
          'Documento reimpresso (via ${value.sequence}): ${value.reference}',
        );
      case Err(:final failure):
        showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      // Voltar para a tela de montagem depois da venda registrada só levaria a
      // um carrinho já enviado. A saída é "nova venda" ou "início".
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Venda registrada'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, size: 48, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Venda #${_sale.id}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      _sale.barcode,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _sale.totalAmount.toDisplayString(),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(_sale.status.label),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _PrintStatusCard(
              printed: _printed,
              message: widget.finished.printFailure?.message,
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    title: const Text('Vendedor'),
                    trailing: Text(_sale.sellerName),
                  ),
                  if (_sale.customerName != null)
                    ListTile(
                      dense: true,
                      title: const Text('Cliente'),
                      trailing: Text(_sale.customerName!),
                    ),
                  ListTile(
                    dense: true,
                    title: const Text('Pagamento'),
                    trailing: Text(_sale.paymentMethod.label),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Horário'),
                    trailing: Text(formatDateTime(_sale.occurredAt)),
                  ),
                  const Divider(height: 1),
                  for (final item in _sale.items)
                    ListTile(
                      dense: true,
                      title: Text(item.productName),
                      subtitle: Text(
                        '${item.quantity.toDisplayString()} x '
                        '${item.unitPrice.toDisplayString()}',
                      ),
                      trailing: Text(item.lineTotal.toDisplayString()),
                    ),
                  if (_sale.hasDiscount)
                    ListTile(
                      dense: true,
                      title: const Text('Desconto'),
                      trailing: Text('- ${_sale.discountAmount.toDisplayString()}'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _reprinting ? null : _reprint,
              icon: _reprinting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: const Text('Reimprimir documento 1'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed(AppRoutes.newSale),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nova venda'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrintStatusCard extends StatelessWidget {
  const _PrintStatusCard({required this.printed, this.message});

  final bool printed;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: printed ? null : scheme.errorContainer,
      child: ListTile(
        leading: Icon(
          printed ? Icons.print : Icons.print_disabled,
          color: printed ? scheme.primary : scheme.onErrorContainer,
        ),
        title: Text(
          printed
              ? 'Documento de encaminhamento impresso'
              : 'O documento não foi impresso',
          style: TextStyle(
            color: printed ? null : scheme.onErrorContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          message ??
              (printed
                  ? 'Entregue ao cliente para levar ao caixa.'
                  : 'A venda está registrada. Resolva a impressora e reimprima.'),
          style: TextStyle(color: printed ? null : scheme.onErrorContainer),
        ),
      ),
    );
  }
}
