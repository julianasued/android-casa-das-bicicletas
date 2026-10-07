/// Tela de prova de integração com o Elgin M10 Pro.
///
/// Independente do fluxo de venda de propósito: aqui não há cliente, produto,
/// comissão nem servidor. Cada botão dispara **uma** operação de hardware pelo
/// plugin `elgin_m10` e a tela mostra o que voltou.
///
/// Nada disto funciona em emulador: o serviço `net.nyx.printerservice` só
/// existe no aparelho, e a abertura de conexão falha sem ele. O erro aparece
/// como tal, em vez de sumir.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import 'm10_poc_controller.dart';

class M10PocPage extends StatefulWidget {
  const M10PocPage({super.key});

  @override
  State<M10PocPage> createState() => _M10PocPageState();
}

class _M10PocPageState extends State<M10PocPage> {
  final M10PocController _controller = M10PocController();
  final TextEditingController _displayMessage = TextEditingController();
  late final TextEditingController _connectionType =
      TextEditingController(text: _controller.connectionType.toString());
  late final TextEditingController _connectionModel =
      TextEditingController(text: _controller.connectionModel);

  @override
  void dispose() {
    _controller.dispose();
    _displayMessage.dispose();
    _connectionType.dispose();
    _connectionModel.dispose();
    super.dispose();
  }

  void _applyConnection() {
    _controller
      ..connectionType =
          int.tryParse(_connectionType.text.trim()) ?? _controller.connectionType
      ..connectionModel = _connectionModel.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teste Elgin M10')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusPanel(controller: _controller),
            const SizedBox(height: 16),
            _Section(
              title: 'Conexão da impressora',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _connectionType,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _applyConnection(),
                        decoration: const InputDecoration(
                          labelText: 'tipo',
                          helperText: '6 (02.34.04) ou 5 (doc pública)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _connectionModel,
                        onChanged: (_) => _applyConnection(),
                        decoration: const InputDecoration(
                          labelText: 'modelo',
                          helperText: '"M8" ou vazio',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PocButton(
                        label: 'Abrir',
                        icon: Icons.power_settings_new,
                        onPressed: _controller.openPrinter,
                        busy: _controller.busy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PocButton(
                        label: 'Fechar',
                        icon: Icons.power_off,
                        onPressed: _controller.closePrinter,
                        busy: _controller.busy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
                _PocButton(
                  label: 'Imprimir imagem',
                  icon: Icons.image,
                  onPressed: _controller.printImage,
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
                  label: 'Sinal sonoro',
                  icon: Icons.volume_up,
                  onPressed: _controller.beep,
                  busy: _controller.busy,
                ),
                _PocButton(
                  label: 'Fechar e reabrir',
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
                const SizedBox(height: 12),
                _LastRead(controller: _controller),
              ],
            ),
            _Section(
              title: 'Display do cliente',
              children: [
                TextField(
                  controller: _displayMessage,
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
                            _controller.showOnDisplay(_displayMessage.text),
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
                _PocButton(
                  label: 'Fechar display',
                  icon: Icons.power_off,
                  onPressed: _controller.closeDisplay,
                  busy: _controller.busy,
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
    final status = controller.printerStatus;

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
              value: controller.printerOpen ? 'conectada' : 'fechada',
              ok: controller.printerOpen,
            ),
            if (controller.printerInfo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 6),
                child: Text(
                  'SDK ${controller.printerInfo['sdk_version'] ?? '—'} · '
                  'série ${controller.printerInfo['serial'] ?? '—'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 6),
                child: Text(
                  'StatusImpressora bruto: ${status.toMap()}\n'
                  'A Elgin não publica o significado destes valores — anote-os '
                  'aqui, no M10, com bobina cheia, vazia e tampa aberta.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            _StatusLine(
              label: 'Scanner',
              value: controller.scannerRunning
                  ? 'ligado (${controller.readCount} leituras)'
                  : 'parado',
              ok: controller.scannerRunning,
            ),
            _StatusLine(
              label: 'Display',
              value: controller.displayOpen ? 'conectado' : 'fechado',
              ok: controller.displayOpen,
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
  const _StatusLine({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
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
            Text('Horário: ${read == null ? '—' : formatTime(read.at)}'),
            Text('Total lido: ${controller.readCount}'),
            const SizedBox(height: 4),
            Text(
              'A E1 devolve apenas o código; a simbologia não vem no callback '
              'do SDK.',
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
  final FutureOr<void> Function() onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: busy ? null : () => onPressed(),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
