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
import '../shared/brand.dart';
import '../shared/feedback.dart';

/// O que a busca devolve para a venda.
///
/// Leva as pendências junto porque a folha de confirmação já as consultou: sem
/// isto a tela da venda faria a mesma chamada de novo para mostrar o mesmo
/// número.
class CustomerSelection {
  const CustomerSelection({required this.customer, this.receivables});

  final Customer customer;

  /// `null` quando não deu para consultar — que é diferente de não dever nada.
  final List<Receivable>? receivables;
}

class CustomerPickerPage extends StatefulWidget {
  const CustomerPickerPage({this.exigeCliente = false, super.key});

  /// Quando a forma de pagamento é notinha, sair sem cliente não é opção
  /// (RF14) — e a referência marca isso no próprio botão.
  final bool exigeCliente;

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
    if (created != null && mounted) {
      // Cadastrado agora: não há venda anterior, então a lista é vazia — e
      // isso é diferente de "não consultei".
      Navigator.of(context).pop(
        CustomerSelection(customer: created, receivables: const []),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // O mesmo cabeçalho azul do resto do fluxo: voltar, o que a tela é,
            // e a saída sem cliente — que a referência põe aqui porque vender à
            // vista não deveria custar uma busca.
            _CabecalhoDaBusca(
              exigeCliente: widget.exigeCliente,
              onVoltar: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _CampoDeBusca(
                controller: _queryController,
                onBuscar: _search,
              ),
            ),
            Expanded(child: _body()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: _BotaoCadastrar(onPressed: _create),
            ),
          ],
        ),
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
        message: 'BUSCA SEM RESULTADO\n'
            'Cadastre o cliente no botão abaixo.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 6),
          child: Text(
            _customers.length == 1
                ? '1 CLIENTE ENCONTRADO'
                : '${_customers.length} CLIENTES ENCONTRADOS',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF4A5474),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            itemCount: _customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final customer = _customers[index];
              final detalhes = [
                if (customer.phone != null) customer.phone!,
                if (customer.document != null)
                  formatDocument(customer.document),
              ].join(' · ');

              return _CustomerButton(
                name: customer.name,
                details: detalhes,
                onTap: () => _open(customer),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Abre o cliente com as pendências antes de confirmar (§7).
  ///
  /// O vendedor vê **todas** as pendências do cliente na loja (D4, RF15): fiar
  /// para quem já deve é decisão dele, mas não pode ser decisão às cegas.
  Future<void> _open(Customer customer) async {
    final escolha = await showModalBottomSheet<CustomerSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerSheet(customer: customer),
    );

    if (escolha != null && mounted) {
      Navigator.of(context).pop(escolha);
    }
  }
}

/// Resultado da busca como botão inteiro, no mesmo alvo da lista de vendedores.
class _CustomerButton extends StatelessWidget {
  const _CustomerButton({
    required this.name,
    required this.details,
    required this.onTap,
  });

  final String name;
  final String details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person_outline,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 28),
        ],
      ),
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
  final _phoneController = TextEditingController();
  final _documentController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _documentController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final result = await context.deps.customers.create(
      name: _nameController.text,
      phone: _phoneController.text,
      document: _documentController.text,
      address: _addressController.text,
      notes: _notesController.text,
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
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: Marca.azul,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'CADASTRAR CLIENTE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'SÓ O NOME É OBRIGATÓRIO',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: Marca.amarelo.withValues(alpha: .95),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CampoDoCadastro(
                        controller: _nameController,
                        rotulo: 'NOME',
                        dica: 'Nome completo do cliente',
                        autofocus: true,
                        capitalizar: true,
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Informe o nome.'
                            : null,
                      ),
                      // Telefone é opcional: o contrato o declara `blank=True`,
                      // e exigir aqui travaria o cadastro de quem compra à
                      // vista e não quer deixar contato.
                      _CampoDoCadastro(
                        controller: _phoneController,
                        rotulo: 'TELEFONE',
                        dica: 'DDD + número',
                        teclado: TextInputType.phone,
                      ),
                      _CampoDoCadastro(
                        controller: _documentController,
                        rotulo: 'CPF / CNPJ',
                        dica: 'Somente se o cliente informar',
                        teclado: TextInputType.number,
                      ),
                      _CampoDoCadastro(
                        controller: _addressController,
                        rotulo: 'ENDEREÇO',
                        dica: 'Rua, número e bairro',
                        capitalizar: true,
                      ),
                      _CampoDoCadastro(
                        controller: _notesController,
                        rotulo: 'OBSERVAÇÃO',
                        dica: 'Referência, apelido, ponto de entrega',
                        capitalizar: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(64),
                      ),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(64),
                      ),
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'SALVAR E USAR NA VENDA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
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

/// Um campo do cadastro, com rótulo em caixa alta e a dica da referência.
class _CampoDoCadastro extends StatelessWidget {
  const _CampoDoCadastro({
    required this.controller,
    required this.rotulo,
    required this.dica,
    this.teclado,
    this.autofocus = false,
    this.capitalizar = false,
    this.validator,
  });

  final TextEditingController controller;
  final String rotulo;
  final String dica;
  final TextInputType? teclado;
  final bool autofocus;
  final bool capitalizar;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: teclado,
        textCapitalization:
            capitalizar ? TextCapitalization.words : TextCapitalization.none,
        validator: validator,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: validator == null ? '$rotulo (opcional)' : rotulo,
          helperText: dica,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// Pendências do cliente (RF15).
///
/// A pergunta do balcão não é "quais são as pendências" e sim "posso vender
/// fiado para esta pessoa", então o total devido vem primeiro e grande; a lista
/// fica abaixo, para quando o vendedor precisa saber de qual venda veio.
class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({required this.customer});

  final Customer customer;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
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
    final customer = widget.customer;

    // Rolável: a folha cresce com os dados do cliente e com as pendências, e
    // numa tela baixa isso passa da altura disponível.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Marca.azul,
                    border: Border.all(color: Marca.amarelo, width: 4),
                  ),
                  child: Text(
                    _iniciais(customer.name),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Marca.amarelo,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                          color: Marca.tinta,
                        ),
                      ),
                      if (customer.phone case final telefone?
                          when telefone.isNotEmpty)
                        Text(
                          telefone,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4A5474),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DadoDoCliente(
                    rotulo: 'DOCUMENTO',
                    valor: customer.document == null
                        ? 'não informado'
                        : formatDocument(customer.document),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DadoDoCliente(
                    rotulo: 'ENDEREÇO',
                    valor: (customer.address ?? '').isEmpty
                        ? 'não informado'
                        : customer.address!,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Limite de altura para a folha não cobrir a tela quando o cliente
            // tem muitas pendências; a lista de dentro rola.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: _content(context),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                CustomerSelection(
                  customer: customer,
                  receivables: _receivables,
                ),
              ),
              icon: const Icon(Icons.check),
              label: const Text('USAR ESTE CLIENTE'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Escolher outro'),
            ),
          ],
        ),
      ),
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
          color:
              vencida ? scheme.errorContainer : scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  vencida
                      ? Icons.warning_amber
                      : Icons.account_balance_wallet_outlined,
                  color: vencida ? scheme.onErrorContainer : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total em aberto: ${devendo.toDisplayString()}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: vencida ? scheme.onErrorContainer : null,
                            ),
                      ),
                      if (vencida)
                        Text(
                          'Há pendência vencida.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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

/// Cabeçalho azul da busca (referência tela-buscar-cliente).
class _CabecalhoDaBusca extends StatelessWidget {
  const _CabecalhoDaBusca({
    required this.exigeCliente,
    required this.onVoltar,
  });

  final bool exigeCliente;
  final VoidCallback onVoltar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Em tela estreita os três elementos não cabem lado a lado. O que sai é
        // o atalho de vender sem cliente — voltar já faz isso, e o título é o
        // que diz onde se está.
        final estreito = constraints.maxWidth < 620;

        return Container(
          color: Marca.azul,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: onVoltar,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: Colors.white.withValues(alpha: .14),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: .34),
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.chevron_left, color: Marca.amarelo),
                label: const Text(
                  'VOLTAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'BUSCAR CLIENTE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      'PESQUISE POR NOME OU TELEFONE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Marca.amarelo,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Some na notinha em vez de aparecer desabilitado: botão apagado numa
              // tela de balcão é botão que alguém tenta tocar assim mesmo.
              if (!exigeCliente && !estreito)
                OutlinedButton(
                  onPressed: onVoltar,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Marca.amarelo, width: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'VENDA SEM CLIENTE',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Marca.tinta,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Campo de busca grande, com o limpar ao lado.
class _CampoDeBusca extends StatelessWidget {
  const _CampoDeBusca({required this.controller, required this.onBuscar});

  final TextEditingController controller;
  final ValueChanged<String> onBuscar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Marca.azul, width: 3),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0xFFD9DCEA), offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 28, color: Marca.azul),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onBuscar,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Marca.tinta,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Nome ou telefone',
                hintStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA8B0C6),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () {
                      controller.clear();
                      onBuscar('');
                    },
                    child: const Text(
                      'LIMPAR',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: Color(0xFF3A4260),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// O botão amarelo de cadastrar, como na referência.
class _BotaoCadastrar extends StatelessWidget {
  const _BotaoCadastrar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE272), Marca.amarelo, Color(0xFFF0C40C)],
          stops: [0, .6, 1],
        ),
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0xFFC9A209), offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 32, color: Marca.azul),
                  SizedBox(width: 14),
                  Text(
                    'CADASTRAR CLIENTE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: Marca.azul,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Iniciais para o medalhão, como na referência.
String _iniciais(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+'));
  if (partes.isEmpty || partes.first.isEmpty) return '?';
  if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
  return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
}

/// Um dado do cliente em caixinha, como na referência.
class _DadoDoCliente extends StatelessWidget {
  const _DadoDoCliente({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Color(0xFF4A5474),
            ),
          ),
          Text(
            valor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Marca.tinta,
            ),
          ),
        ],
      ),
    );
  }
}
