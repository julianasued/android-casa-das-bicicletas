/// A fila de sincronização, vista por quem está no balcão — OFF-008.
///
/// Antes desta tela o terminal tinha tudo e mostrava nada: `syncNow()` existia
/// documentado como "a tela precisa disto" e nenhuma tela o chamava;
/// `needingAttention()` nunca foi chamado; e o menu somava pendente, recusada e
/// conflitante num número único — "3 operações esperando envio" —, que é a
/// forma mais rápida de transformar três problemas diferentes em nenhuma ação.
///
/// Os três estados não se parecem:
///
///   - **esperando envio** é normal, e resolve sozinho quando a rede volta;
///   - **recusada** vai ser tentada de novo, e o motivo do servidor diz se
///     adianta esperar (produto reativado, permissão concedida) ou se alguém
///     precisa agir;
///   - **em conflito** não resolve sozinho nunca: espera decisão de gerente ou
///     dono na retaguarda (13.11).
///
/// Mostrar o motivo só passou a valer a pena depois do OFF-007 — até então a
/// fila guardava a frase genérica "O servidor recusou a operação", porque o
/// mapeador lia o campo errado da resposta.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../domain/entities/pending_operation.dart';
import '../shared/feedback.dart';

class FilaDeSincronizacaoPage extends StatefulWidget {
  const FilaDeSincronizacaoPage({super.key});

  @override
  State<FilaDeSincronizacaoPage> createState() => _FilaDeSincronizacaoPageState();
}

class _FilaDeSincronizacaoPageState extends State<FilaDeSincronizacaoPage> {
  QueueSummary? _resumo;
  List<PendingOperation> _travadas = const [];
  bool _carregando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ler());
  }

  Future<void> _ler() async {
    final fila = context.deps.syncQueue;
    if (fila == null) {
      setState(() => _carregando = false);
      return;
    }

    setState(() => _carregando = true);
    final resumo = await fila.summary();
    final travadas = await fila.needingAttention();
    if (!mounted) return;

    setState(() {
      _resumo = resumo;
      _travadas = travadas;
      _carregando = false;
    });
  }

  /// Envia agora, a pedido de quem está no balcão.
  ///
  /// O botão existe porque o gatilho automático depende de um evento que o
  /// vendedor não controla: a volta da rede. Quem está olhando "2 vendas
  /// esperando" com o wi-fi funcionando merece poder insistir.
  Future<void> _sincronizarAgora() async {
    final agendador = context.deps.syncScheduler;
    if (agendador == null) return;

    setState(() => _enviando = true);
    final resultado = await agendador.syncNow();
    if (!mounted) return;
    setState(() => _enviando = false);

    switch (resultado) {
      case Ok(:final value) when value.isEmpty:
        showMessage(context, 'Nada na fila para enviar.');
      case Ok(:final value):
        showMessage(
          context,
          'Enviadas ${value.sent}: ${value.accepted} aceitas'
          '${value.failed > 0 ? ', ${value.failed} recusadas' : ''}'
          '${value.conflicting > 0 ? ', ${value.conflicting} em conflito' : ''}.',
        );
      case Err(:final failure):
        showFailure(context, failure);
    }

    await _ler();
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronização'),
        actions: [
          IconButton(
            onPressed: _carregando ? null : _ler,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: deps.connectivity,
        builder: (context, _) {
          final online = deps.connectivity.isOnline;
          final resumo = _resumo;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (deps.syncQueue == null)
                const _Aviso(
                  texto: 'Este terminal não tem fila local configurada.',
                )
              else ...[
                _Contadores(resumo: resumo, carregando: _carregando),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (!online || _enviando || deps.syncScheduler == null)
                      ? null
                      : _sincronizarAgora,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_enviando ? 'ENVIANDO…' : 'SINCRONIZAR AGORA'),
                ),
                if (!online)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Sem rede agora. A fila sobe sozinha quando a conexão voltar.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'PRECISA DE ATENÇÃO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                if (_carregando)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_travadas.isEmpty)
                  const _Aviso(
                    texto: 'Nada travado. O que está na fila sobe sozinho.',
                  )
                else
                  for (final operacao in _travadas) _LinhaDaOperacao(operacao: operacao),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Contadores extends StatelessWidget {
  const _Contadores({required this.resumo, required this.carregando});

  final QueueSummary? resumo;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    final fila = resumo;
    if (carregando || fila == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Lendo a fila…'),
        ),
      );
    }

    final esquema = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Separados de propósito: um número só não diz se dá para esperar.
            Row(
              children: [
                _Contador(
                  rotulo: 'ESPERANDO ENVIO',
                  valor: fila.pending,
                  cor: esquema.primary,
                ),
                _Contador(
                  rotulo: 'RECUSADAS',
                  valor: fila.failed,
                  cor: esquema.error,
                ),
                _Contador(
                  rotulo: 'EM CONFLITO',
                  valor: fila.conflicting,
                  cor: esquema.tertiary,
                ),
              ],
            ),
            if (fila.oldestPendingAt case final DateTime desde) ...[
              const SizedBox(height: 12),
              Text(
                // A mais antiga mede o tamanho do problema: dez minutos é
                // rotina, três dias é alguém precisando saber.
                'A mais antiga esperando é de ${formatDateTime(desde)}.',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({required this.rotulo, required this.valor, required this.cor});

  final String rotulo;
  final int valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$valor',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cor),
          ),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaDaOperacao extends StatelessWidget {
  const _LinhaDaOperacao({required this.operacao});

  final PendingOperation operacao;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final emConflito = operacao.status == SyncStatus.conflitante;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  emConflito ? Icons.gavel_outlined : Icons.error_outline,
                  size: 18,
                  color: emConflito ? esquema.tertiary : esquema.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${operacao.type.label} · ${formatDateTime(operacao.occurredAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              // A frase é do servidor (OFF-007). Dizer "erro" aqui seria
              // esconder o que já se sabe.
              operacao.lastError ?? operacao.status.label,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              emConflito
                  // Não insiste: insistir produziria o mesmo conflito e
                  // encheria a auditoria (13.11).
                  ? 'Espera decisão do gerente ou do dono na retaguarda.'
                  : 'Será tentada de novo no próximo envio.'
                      '${operacao.attempts > 1 ? ' ${operacao.attempts} tentativas até agora.' : ''}',
              style: TextStyle(fontSize: 12, color: esquema.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(texto, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
