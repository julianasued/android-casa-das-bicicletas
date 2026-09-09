/// Tela de prova de integração com o Elgin M10.
///
/// Independente do fluxo de venda de propósito: aqui não há cliente, produto,
/// comissão nem servidor. Cada botão dispara **uma** chamada de hardware e a
/// tela mostra o que voltou. É o que permite responder, no aparelho, as
/// perguntas que a documentação da Elgin deixa em aberto — o significado dos
/// valores de `StatusImpressora`, qual broadcast o leitor emite, e se o display
/// do cliente aparece para o Android.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../core/formatters.dart';
import 'm10_poc_controller.dart';

class M10PocPage extends StatefulWidget {
  const M10PocPage({super.key});

  @override
  State<M10PocPage> createState() => _M10PocPageState();
}

class _M10PocPageState extends State<M10PocPage> {
  final TextEditingController _imagePathController = TextEditingController();
  final TextEditingController _displayMessageController = TextEditingController();
  final TextEditingController _manualCodeController = TextEditingController();

  M10PocController? _controllerOrNull;

  M10PocController get _controller => _controllerOrNull!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controllerOrNull != null) return;

    final deps = context.deps;
    _controllerOrNull = M10PocController(
      printer: deps.printerDiagnostics,
      scanner: deps.scanner,
      display: deps.customerDisplay,
    );
    unawaited(_controller.refreshAll());
  }

  @override
  void dispose() {
    _controllerOrNull?.dispose();
    _imagePathController.dispose();
    _displayMessageController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teste Elgin M10'),
        actions: [
          IconButton(
            tooltip: 'Rever diagnóstico',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.refreshAll(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusPanel(controller: _controller),
            const SizedBox(height: 16),
            _Section(
              title: 'Impressora',
              children: [
                _PocButton(
                  label: 'Imprimir texto',
                  icon: Icons.text_fields,
                  onPressed: _controller.printText,
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Imprimir código de barras',
                  icon: Icons.barcode_reader,
                  onPressed: _controller.printBarcodes,
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Imprimir QR Code',
                  icon: Icons.qr_code_2,
                  onPressed: _controller.printQrCode,
                  busy: _controller.busy,
                ),
                TextField(
                  controller: _imagePathController,
                  decoration: const InputDecoration(
                    labelText: 'Caminho da imagem no aparelho',
                    helperText: 'Ex.: /sdcard/Download/logo.png',
                  ),
                ),
                const SizedBox(height: 8),
                _PocButton(
                  label: 'Imprimir imagem',
                  icon: Icons.image,
                  onPressed: () => _controller.printImage(_imagePathController.text),
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Avançar papel',
                  icon: Icons.vertical_align_bottom,
                  onPressed: _controller.feedPaper,
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Cortar papel',
                  icon: Icons.content_cut,
                  onPressed: _controller.cutPaper,
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Consultar status',
                  icon: Icons.info_outline,
                  onPressed: _controller.checkPrinter,
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Fechar e reabrir conexão',
                  icon: Icons.restart_alt,
                  onPressed: _controller.reconnectPrinter,
                  busy: _controller.busy,
                ),
              ],
            ),
            _Section(
              title: 'Scanner',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PocButton(
                        label: 'Iniciar',
                        icon: Icons.play_arrow,
                        onPressed: _controller.startScanner,
                        busy: _controller.busy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PocButton(
                        label: 'Parar',
                        icon: Icons.stop,
                        onPressed: _controller.stopScanner,
                        busy: _controller.busy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _manualCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Código manual (sem hardware)',
                  ),
                  onSubmitted: (value) {
                    _controller.registerManualRead(value);
                    _manualCodeController.clear();
                  },
                ),
                const SizedBox(height: 12),
                _LastRead(controller: _controller),
                const SizedBox(height: 8),
                _ScannerProbe(controller: _controller),
              ],
            ),
            _Section(
              title: 'Display do cliente',
              children: [
                TextField(
                  controller: _displayMessageController,
                  decoration: const InputDecoration(labelText: 'Mensagem'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _PocButton(
                        label: 'Enviar',
                        icon: Icons.send,
                        onPressed: () =>
                            _controller.showOnDisplay(_displayMessageController.text),
                        busy: _controller.busy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PocButton(
                        label: 'Limpar',
                        icon: Icons.clear,
                        onPressed: _controller.clearDisplay,
                        busy: _controller.busy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Este POC valida apenas a comunicação com o hardware. Nenhuma '
              'venda, pagamento ou sincronização acontece aqui.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Partes da tela
// ---------------------------------------------------------------------------

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final M10PocController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final printer = controller.printerStatus;
    final display = controller.displayStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            _StatusLine(
              label: 'Impressora',
              value: printer == null
                  ? 'não consultada'
                  : printer.available
                      ? 'disponível'
                      : 'indisponível',
              detail: printer?.detail,
              ok: printer?.available ?? false,
            ),
            if (printer != null && printer.rawStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  'StatusImpressora bruto: ${printer.rawStatus}\n'
                  'A Elgin não publica o significado destes valores — '
                  'anote-os aqui, no M10, para fechar o mapeamento.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            _StatusLine(
              label: 'Scanner',
              value: controller.scannerRunning ? 'escutando' : 'parado',
              detail: controller.scannerProbe['detail']?.toString(),
              ok: controller.scannerRunning,
            ),
            _StatusLine(
              label: 'Display',
              value: display == null
                  ? 'não consultado'
                  : display.hasSecondaryDisplay
                      ? 'tela secundária detectada'
                      : 'sem tela secundária',
              detail: display?.detail,
              ok: display?.hasSecondaryDisplay ?? false,
            ),
            if (display != null && display.secondaryDisplays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  display.secondaryDisplays.join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(),
            if (controller.lastError case final String error)
              Text(
                error,
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              )
            else if (controller.lastSuccess case final String success)
              Text(success, style: TextStyle(color: scheme.primary))
            else
              const Text('Último resultado: nenhum'),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.ok,
    this.detail,
  });

  final String label;
  final String value;
  final bool ok;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.help_outline,
                size: 18,
                color: ok ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
              Expanded(child: Text(value)),
            ],
          ),
          if (detail != null && detail!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(detail!, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _LastRead extends StatelessWidget {
  const _LastRead({required this.controller});

  final M10PocController controller;

  @override
  Widget build(BuildContext context) {
    final read = controller.lastRead;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Última leitura', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Código: ${read?.code ?? '—'}'),
            Text('Tipo: ${read?.symbology ?? '—'}'),
            Text('Origem: ${read?.source.label ?? '—'}'),
            Text('Horário: ${read == null ? '—' : formatTime(read.readAt)}'),
          ],
        ),
      ),
    );
  }
}

class _ScannerProbe extends StatelessWidget {
  const _ScannerProbe({required this.controller});

  final M10PocController controller;

  @override
  Widget build(BuildContext context) {
    final probe = controller.scannerProbe;
    if (probe.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnóstico do leitor',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text('Ações escutadas: ${probe['actions'] ?? '—'}'),
            Text('Pacotes encontrados: ${probe['scanner_packages_found'] ?? '—'}'),
            Text(
              'Classe do scanner SmartPOS presente: '
              '${probe['smartpos_scanner_class_present'] ?? '—'}',
            ),
            const SizedBox(height: 4),
            Text(
              'A Elgin documenta scanner apenas para o SmartPOS. Para o M10 não '
              'há API publicada — as ações acima são candidatas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _PocButton extends StatelessWidget {
  const _PocButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.busy,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
