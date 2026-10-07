/// Diagnóstico da impressora térmica (§4 e §11 da integração com o M10 Pro).
///
/// Existe para a instalação e para o dia em que o papel não sai. As três ações
/// são as que resolvem sozinhas a maioria dos chamados: ver o estado, avançar o
/// papel depois de trocar a bobina e imprimir uma página de teste.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/ports/document_printer.dart';
import '../shared/feedback.dart';

class PrinterDiagnosticsPage extends StatefulWidget {
  const PrinterDiagnosticsPage({super.key});

  @override
  State<PrinterDiagnosticsPage> createState() => _PrinterDiagnosticsPageState();
}

class _PrinterDiagnosticsPageState extends State<PrinterDiagnosticsPage> {
  PrinterStatus? _status;
  Failure? _failure;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    final result = await context.deps.printer.status();
    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (result) {
        case Ok(:final value):
          _status = value;
        case Err(:final failure):
          _failure = failure;
      }
    });
  }

  Future<void> _feed() async {
    final result = await context.deps.printer.feed();
    if (!mounted) return;

    switch (result) {
      case Ok():
        showMessage(context, 'Papel avançado.');
      case Err(:final failure):
        showFailure(context, failure);
    }
  }

  Future<void> _testPage() async {
    final deps = context.deps;
    final terminalName =
        'Loja ${deps.session.storeCode ?? deps.session.storeId} · '
        '${deps.session.deviceId ?? 'terminal'}';

    setState(() => _busy = true);
    final result = await deps.printer.printTestPage(terminalName: terminalName);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok():
        showMessage(context, 'Página de teste enviada à impressora.');
      case Err(:final failure):
        showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impressora'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar estado',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_failure != null)
            FailureView(failure: _failure!, onRetry: _refresh)
          else
            _StatusCard(status: _status, loading: _busy),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _feed,
            icon: const Icon(Icons.vertical_align_bottom),
            label: const Text('Avançar papel'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _testPage,
            icon: const Icon(Icons.print),
            label: const Text('Imprimir página de teste'),
          ),
          const SizedBox(height: 24),
          Text(
            'A impressora é a integrada do Elgin M10 Pro, bobina de 2". '
            'Falta de papel e impressora indisponível são tratadas como falhas '
            'distintas: a primeira tem solução no balcão, a segunda não.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.loading});

  final PrinterStatus? status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading && status == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: LoadingView(label: 'Consultando a impressora...'),
        ),
      );
    }

    final current = status;
    final scheme = Theme.of(context).colorScheme;
    final ok = current?.canPrint ?? false;

    return Card(
      color: ok ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.report_problem,
              size: 48,
              color: ok ? scheme.primary : scheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              _title(current),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if ((current?.detail ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(current!.detail, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  String _title(PrinterStatus? status) {
    if (status == null) return 'Estado desconhecido';
    if (status.outOfPaper) return 'Sem papel';
    if (!status.available) return 'Impressora indisponível';
    return 'Impressora pronta';
  }
}
