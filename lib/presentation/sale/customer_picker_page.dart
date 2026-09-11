/// Escolha do cliente da venda (RF05, obrigatório na notinha — RF14).
///
/// Busca e cadastro na mesma tela porque no balcão as duas coisas são o mesmo
/// gesto: o vendedor procura o nome, não acha, e cadastra ali mesmo com o
/// cliente na frente. Mandá-lo a outra tela para voltar depois é onde a venda
/// em notinha costuma travar.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/receivable.dart';
import '../shared/feedback.dart';

class CustomerPickerPage extends StatefulWidget {
  const CustomerPickerPage({super.key});

  @override
  State<CustomerPickerPage> createState() => _CustomerPickerPageState();
}

class _CustomerPickerPageState extends State<CustomerPickerPage> {
  final TextEditingController _queryController = TextEditingController();

  List<Customer> _customers = const <Customer>[];
  bool _loading = true;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final result = await context.deps.customers.search(query: query);
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _customers = value;
        case Err(:final failure):
          _failure = failure;
          _customers = const <Customer>[];
      }
    });
  }

  Future<void> _create() async {
    final created = await showDialog<Customer>(
      context: context,
      builder: (_) => const _NewCustomerDialog(),
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cliente')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _queryController,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Nome, documento ou telefone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_queryController.text),
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_failure case final Failure failure) {
      return FailureView(
        failure: failure,
        onRetry: () => _search(_queryController.text),
      );
    }
    if (_customers.isEmpty) {
      return const EmptyView(
        icon: Icons.person_search,
        message: 'Nenhum cliente encontrado.\nCadastre pelo botão abaixo.',
      );
    }

    return ListView.separated(
      itemCount: _customers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final customer = _customers[index];
        return ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(customer.name),
          subtitle: Text(
            [
              if (customer.document != null) formatDocument(customer.document),
              if (customer.phone != null) customer.phone!,
            ].join(' · '),
          ),
          // A consulta fica num botão próprio, e não no toque da linha: quem
          // vende à vista escolhe o cliente e segue, sem passar por uma tela a
          // mais. Quem vai fiar é que precisa do número (RF15).
          trailing: IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Pendências',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ReceivablesDialog(customer: customer),
            ),
          ),
          onTap: () => Navigator.of(context).pop(customer),
        );
      },
    );
  }
}

class _NewCustomerDialog extends StatefulWidget {
  const _NewCustomerDialog();

  @override
  State<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends State<_NewCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _documentController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _documentController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final result = await context.deps.customers.create(
      name: _nameController.text,
      document: _documentController.text,
      phone: _phoneController.text,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo cliente'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Informe o nome.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CPF/CNPJ (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cadastrar'),
        ),
      ],
    );
  }
}

/// Pendências do cliente (RF15).
///
/// A pergunta do balcão não é "quais são as pendências" e sim "posso vender
/// fiado para esta pessoa", então o total devido vem primeiro e grande; a lista
/// fica abaixo, para quando o vendedor precisa saber de qual venda veio.
class _ReceivablesDialog extends StatefulWidget {
  const _ReceivablesDialog({required this.customer});

  final Customer customer;

  @override
  State<_ReceivablesDialog> createState() => _ReceivablesDialogState();
}

class _ReceivablesDialogState extends State<_ReceivablesDialog> {
  List<Receivable>? _receivables;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _receivables = null;
      _failure = null;
    });

    final result = await context.deps.customers.receivables(widget.customer.id);
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        setState(() => _receivables = value);
      case Err(:final failure):
        setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer.name),
      content: SizedBox(width: 420, child: _content(context)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    if (_failure case final Failure failure) {
      return FailureView(failure: failure, onRetry: _load);
    }

    if (_receivables case final List<Receivable> receivables) {
      if (receivables.isEmpty) {
        return const EmptyView(
          icon: Icons.check_circle_outline,
          message: 'Nenhuma pendência. O cliente não deve nada.',
        );
      }
      return _list(context, receivables);
    }

    return const SizedBox(
      height: 120,
      child: LoadingView(label: 'Consultando pendências...'),
    );
  }

  Widget _list(BuildContext context, List<Receivable> receivables) {
    final scheme = Theme.of(context).colorScheme;
    final devendo = receivables.totalOutstanding;
    final vencida = receivables.hasOverdue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // O número que decide a venda.
        Card(
          color: vencida ? scheme.errorContainer : scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  vencida ? Icons.warning_amber : Icons.account_balance_wallet_outlined,
                  color: vencida ? scheme.onErrorContainer : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Devendo ${devendo.toDisplayString()}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: vencida ? scheme.onErrorContainer : null,
                            ),
                      ),
                      if (vencida)
                        Text(
                          'Há pendência vencida.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onErrorContainer,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: receivables.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final receivable = receivables[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Venda ${receivable.saleId} · ${receivable.status.label}',
                ),
                subtitle: Text(
                  receivable.isPartiallyPaid
                      // Mostrar o pago junto: sem isso, um saldo menor que o
                      // valor da venda parece erro de cálculo.
                      ? '${formatDate(receivable.createdAt)} · '
                          'de ${receivable.originalAmount.toDisplayString()} '
                          'pagou ${receivable.paidAmount.toDisplayString()}'
                      : '${formatDate(receivable.createdAt)} · '
                          'de ${receivable.originalAmount.toDisplayString()}',
                ),
                trailing: Text(
                  receivable.pendingAmount.toDisplayString(),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
