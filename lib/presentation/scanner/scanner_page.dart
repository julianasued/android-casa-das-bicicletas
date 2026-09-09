/// Leitor de código de barras: validação do hardware e localização da venda.
///
/// Duas coisas ao mesmo tempo, de propósito. A primeira é o teste do leitor
/// integrado exigido pela Sprint 4 — cada leitura aparece com origem e horário,
/// que é o que se olha quando alguém diz "o leitor não está pegando". A segunda
/// é o caminho da RF09: código de venda lido, venda localizada na tela, sem
/// digitar número nenhum.
///
/// A conferência e a confirmação do recebimento são da Sprint 5; aqui a venda é
/// só exibida.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../domain/entities/barcode_read.dart';
import '../../domain/entities/sale.dart';
import '../../domain/ports/barcode_scanner.dart';
import '../../platform/scanner/keyboard_wedge.dart';
import '../../platform/scanner/scanner_channel.dart';
import '../shared/feedback.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final TextEditingController _manualController = TextEditingController();
  final List<BarcodeRead> _history = <BarcodeRead>[];

  StreamSubscription<BarcodeRead>? _subscription;

  /// Guardado ao entrar na tela: `dispose` não pode consultar o
  /// `InheritedWidget` das dependências para desligar o leitor.
  BarcodeScanner? _scanner;

  bool _scannerAvailable = false;
  bool _looking = false;
  Sale? _sale;
  Failure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scanner != null) return;

    _scanner = context.deps.scanner;
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_scanner?.stop());
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final scanner = _scanner!;

    final available = await scanner.isAvailable();
    _subscription = scanner.reads.listen(
      _handleRead,
      onError: (Object error) {
        if (error is Failure && mounted) showFailure(context, error);
      },
    );
    await scanner.start();

    if (!mounted) return;
    setState(() => _scannerAvailable = available);
  }

  void _handleRead(BarcodeRead read) {
    setState(() {
      _history.insert(0, read);
      if (_history.length > 20) _history.removeLast();
    });
    unawaited(_lookup(read));
  }

  Future<void> _lookup(BarcodeRead read) async {
    if (!read.looksLikeSaleBarcode) {
      // Etiqueta de produto, código de outro sistema: registrar a leitura e não
      // ir à rede é o comportamento certo, não um erro a mostrar.
      setState(() {
        _sale = null;
        _failure = null;
      });
      return;
    }

    setState(() {
      _looking = true;
      _failure = null;
    });

    final result = await context.deps.findSaleByBarcode(read);
    if (!mounted) return;

    setState(() {
      _looking = false;
      switch (result) {
        case Ok(:final value):
          _sale = value;
        case Err(:final failure):
          _sale = null;
          _failure = failure;
      }
    });
  }

  void _submitManual() {
    final code = _manualController.text.trim();
    if (code.isEmpty) return;

    _manualController.clear();
    _handleRead(
      BarcodeRead(
        code: code,
        readAt: DateTime.now(),
        source: BarcodeSource.manual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanner = _scanner;

    return KeyboardWedgeListener(
      // Leitor em modo teclado: o código chega como digitação, e não pelo canal
      // nativo. Entra no mesmo stream para a tela não ter dois caminhos.
      onRead: (read) {
        if (scanner is ScannerChannel) scanner.emitExternalRead(read);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Leitor de código')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ScannerStatusCard(available: _scannerAvailable),
            const SizedBox(height: 12),
            TextField(
              controller: _manualController,
              onSubmitted: (_) => _submitManual(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Código (bipe ou digite)',
                prefixIcon: const Icon(Icons.qr_code),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _submitManual,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_looking) const LoadingView(label: 'Localizando a venda...'),
            if (_failure != null)
              FailureView(failure: _failure!, onRetry: _retryLast),
            if (_sale != null) _SaleCard(sale: _sale!),
            const SizedBox(height: 24),
            Text('Leituras', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const EmptyView(
                icon: Icons.qr_code_scanner,
                message: 'Nenhuma leitura ainda. Aponte o leitor para o código.',
              )
            else
              for (final read in _history)
                ListTile(
                  dense: true,
                  leading: Icon(
                    read.looksLikeSaleBarcode ? Icons.receipt_long : Icons.label,
                  ),
                  title: Text(read.code),
                  subtitle: Text(
                    '${read.source.label} · ${formatTime(read.readAt)}'
                    '${read.symbology == null ? '' : ' · ${read.symbology}'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  void _retryLast() {
    if (_history.isEmpty) return;
    unawaited(_lookup(_history.first));
  }
}

class _ScannerStatusCard extends StatelessWidget {
  const _ScannerStatusCard({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(available ? Icons.check_circle : Icons.info_outline),
        title: Text(
          available ? 'Leitor integrado ativo' : 'Leitor integrado não detectado',
        ),
        subtitle: Text(
          available
              ? 'Aponte e dispare: a leitura aparece automaticamente.'
              : 'O aparelho pode estar com o leitor em modo teclado — '
                  'a digitação e o bipe pelo teclado também funcionam aqui.',
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Venda #${sale.id}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(label: Text(sale.status.label)),
              ],
            ),
            Text(sale.barcode),
            const Divider(),
            Text('Vendedor: ${sale.sellerName}'),
            if (sale.customerName != null) Text('Cliente: ${sale.customerName}'),
            Text('Pagamento: ${sale.paymentMethod.label}'),
            Text('Em ${formatDateTime(sale.occurredAt)}'),
            const SizedBox(height: 8),
            for (final item in sale.items)
              Text(
                '${item.quantity.toDisplayString()} x ${item.productName} — '
                '${item.lineTotal.toDisplayString()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  sale.totalAmount.toDisplayString(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A conferência e a confirmação do recebimento são feitas na tela '
              'de caixa (Sprint 5).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
