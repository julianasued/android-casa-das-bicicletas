/// Quando sincronizar (§13.10).
///
/// A fila enche sozinha, mas não esvazia sozinha. Este é o gatilho: assina o
/// `ConnectivityChannel` — que existe desde a Sprint 4 justamente para isto — e
/// manda sincronizar quando a rede volta.
///
/// **Só na subida.** Um `ChangeNotifier` avisa a cada mudança, e a conexão de um
/// terminal no balcão oscila: avisar de novo a cada notificação faria o
/// aplicativo tentar sincronizar quando a rede acabou de cair, que é o pior
/// momento. O gatilho é a transição de "sem rede" para "com rede".
///
/// **Sobe e desce no mesmo gatilho.** Depois de enviar a fila, o agendador
/// também busca os dados de referência (`pull`): é a mesma janela de rede, e é
/// ela que corrige o cache — produto desativado no servidor só sai da vitrine
/// do terminal quando chega por aqui, porque a busca online filtra ativos e
/// nunca o traria de volta (RF34, OFF-005).
///
/// O envio vem primeiro de propósito: o que já aconteceu no balcão tem
/// prioridade sobre o que o terminal vai saber. E o `pull` falhar não desfaz o
/// `push` — são dois resultados independentes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import '../../domain/entities/sync_outcome.dart';
import '../../domain/usecases/pull_reference_data.dart';
import '../../domain/usecases/sync_pending_operations.dart';
import 'connectivity_channel.dart';

class SyncScheduler {
  SyncScheduler({
    required ConnectivityChannel connectivity,
    required SyncPendingOperations sync,
    PullReferenceData? pull,
    Duration retryInterval = const Duration(minutes: 5),
  })  : _connectivity = connectivity,
        _sync = sync,
        _pull = pull,
        _retryInterval = retryInterval;

  final ConnectivityChannel _connectivity;
  final SyncPendingOperations _sync;

  /// Opcional: sem ele o agendador se comporta como antes, só enviando.
  final PullReferenceData? _pull;

  /// Com rede e fila cheia, tenta de novo de tempo em tempo.
  ///
  /// Existe porque uma falha de servidor não muda o estado da conexão: sem isto
  /// uma venda recusada por um `500` esperaria a próxima oscilação de rede para
  /// ser tentada outra vez, o que pode não acontecer no mesmo dia.
  final Duration _retryInterval;

  Timer? _timer;
  bool _wasOnline = true;
  bool _started = false;

  /// O último desfecho, para a tela poder mostrar.
  final ValueNotifier<SyncReport?> lastReport = ValueNotifier<SyncReport?>(null);

  void start() {
    if (_started) return;
    _started = true;

    _wasOnline = _connectivity.isOnline;
    _connectivity.addListener(_onConnectivityChanged);
    _timer = Timer.periodic(_retryInterval, (_) => _syncIfOnline());

    // Subir o aplicativo com fila pendente é caso comum: o terminal foi
    // reiniciado depois de um dia sem rede.
    _syncIfOnline();
  }

  void _onConnectivityChanged() {
    final online = _connectivity.isOnline;
    final voltou = online && !_wasOnline;
    _wasOnline = online;

    if (voltou) _syncIfOnline();
  }

  Future<void> _syncIfOnline() async {
    if (!_connectivity.isOnline || _sync.isRunning) return;

    final resultado = await _sync();
    if (resultado case Ok(:final value)) {
      if (!value.isEmpty) lastReport.value = value;
    }

    await _atualizarReferencia();
  }

  /// Busca o que mudou no catálogo e nos clientes.
  ///
  /// Sem barulho e sem travar nada: falhar aqui deixa o cache como estava, e o
  /// terminal segue vendendo com o catálogo de antes — que é melhor do que não
  /// vender. Quem avisa que ele está velho é a tela de venda.
  Future<void> _atualizarReferencia() async {
    final pull = _pull;
    if (pull == null || !_connectivity.isOnline) return;

    final resultado = await pull();
    if (resultado case Ok(:final value)) {
      if (!value.isEmpty) lastPull.value = value;
    }
  }

  /// O último retrato recebido, para a tela poder mostrar.
  final ValueNotifier<PullReport?> lastPull = ValueNotifier<PullReport?>(null);

  /// Sincroniza agora, a pedido do operador.
  ///
  /// A tela precisa disto: quem está no balcão vendo "3 vendas aguardando"
  /// merece um botão, em vez de esperar um evento que ele não controla.
  Future<Result<SyncReport>> syncNow() async {
    final resultado = await _sync();
    if (resultado case Ok(:final value)) {
      if (!value.isEmpty) lastReport.value = value;
    }
    await _atualizarReferencia();
    return resultado;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _connectivity.removeListener(_onConnectivityChanged);
    lastReport.dispose();
    lastPull.dispose();
    _started = false;
  }
}
