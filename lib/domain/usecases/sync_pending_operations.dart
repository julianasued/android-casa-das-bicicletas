/// Manda ao servidor o que foi feito offline (RF35, §13.10).
///
/// Lê a fila, envia o lote e aplica o desfecho de cada operação. Nada aqui
/// decide regra de negócio: o servidor é a fonte de verdade (13.11), e este caso
/// de uso só registra o que ele respondeu.
///
/// **Uma tentativa por vez.** Duas sincronizações simultâneas enviariam o mesmo
/// lote duas vezes; a idempotência do servidor impediria a duplicata, mas o
/// segundo retorno sobrescreveria o primeiro e a contagem de tentativas ficaria
/// errada. O guarda é local porque o gatilho é um evento de rede, que pode
/// disparar duas vezes em sequência quando o sinal oscila.
library;

import '../../core/result.dart';
import '../entities/pending_operation.dart';
import '../entities/sync_outcome.dart';
import '../repositories/sync_repository.dart';

/// O que a fila precisa expor para ser sincronizada.
///
/// Mais que a `SyncQueue` que o `CreateSale` usa: ali só se escreve, aqui se lê
/// e se atualiza.
abstract interface class SyncableQueue {
  Future<List<PendingOperation>> nextBatch({int limit});
  Future<void> markSynced(String operationId, {int? serverId});
  Future<void> markFailed(String operationId, String error);
  Future<void> markConflicting(
    String operationId, {
    String? conflictId,
    String? error,
  });

  /// Apaga o que já foi sincronizado há mais de [keepFor].
  Future<int> pruneSynced({Duration keepFor});
}

class SyncPendingOperations {
  SyncPendingOperations({
    required SyncableQueue queue,
    required SyncRepository sync,
    int batchSize = 50,
    Duration retencao = const Duration(days: 7),
  })  : _queue = queue,
        _sync = sync,
        _batchSize = batchSize,
        _retencao = retencao;

  final SyncableQueue _queue;
  final SyncRepository _sync;
  final int _batchSize;

  /// Quanto tempo a operação sincronizada fica guardada antes da faxina.
  final Duration _retencao;

  bool _running = false;

  /// Está sincronizando agora.
  bool get isRunning => _running;

  Future<Result<SyncReport>> call() async {
    if (_running) return const Ok(SyncReport.nothingToDo());
    _running = true;

    try {
      final lote = await _queue.nextBatch(limit: _batchSize);
      if (lote.isEmpty) return const Ok(SyncReport.nothingToDo());

      final enviado = await _sync.push(lote);
      if (enviado case Err(:final failure)) {
        // Falha do lote inteiro — rede caiu no meio, servidor fora. As operações
        // ficam como estão e serão tentadas de novo; marcar cada uma como erro
        // aqui inflaria a contagem de tentativas por um problema que não é delas.
        return Err(failure);
      }

      final desfechos = (enviado as Ok<List<SyncOutcome>>).value;
      final relatorio = await _apply(lote, desfechos);
      await _limpar();
      return Ok(relatorio);
    } finally {
      _running = false;
    }
  }

  /// Tira da fila o que já cumpriu seu papel.
  ///
  /// Sem isto a tabela só cresce: nada apagava operação sincronizada, e o
  /// aparelho tem 64 GB para durar anos de balcão. A limpeza fica **depois** do
  /// envio, nunca antes, e nunca falha a sincronização — perder a faxina é
  /// irrelevante; perder o lote não.
  ///
  /// A janela de uma semana não é cautela vaga: operação recém-sincronizada
  /// ainda serve para explicar ao operador o que aconteceu com aquela venda.
  Future<void> _limpar() async {
    try {
      await _queue.pruneSynced(keepFor: _retencao);
    } catch (_) {
      // Fila cheia de histórico é problema de disco; lote não enviado é
      // problema de dinheiro. Este erro não sobe.
    }
  }

  Future<SyncReport> _apply(
    List<PendingOperation> lote,
    List<SyncOutcome> desfechos,
  ) async {
    final porId = {for (final desfecho in desfechos) desfecho.operationId: desfecho};

    var aceitas = 0;
    var falhas = 0;
    var conflitos = 0;

    for (final operacao in lote) {
      final desfecho = porId[operacao.operationId];

      if (desfecho == null) {
        // O servidor não falou desta operação. Não é "aceita": continua na fila
        // para a próxima rodada, que é o desfecho seguro — a idempotência
        // impede duplicata se ela tiver sido processada.
        await _queue.markFailed(
          operacao.operationId,
          'O servidor não respondeu sobre esta operação.',
        );
        falhas++;
        continue;
      }

      switch (desfecho.status) {
        case SyncStatus.sincronizado:
          await _queue.markSynced(
            operacao.operationId,
            serverId: desfecho.serverId,
          );
          aceitas++;

        case SyncStatus.conflitante:
          await _queue.markConflicting(
            operacao.operationId,
            conflictId: desfecho.conflictId,
            error: desfecho.message ??
                'Divergência com o servidor. Precisa de decisão do gerente.',
          );
          conflitos++;

        case SyncStatus.erro:
        case SyncStatus.pendente:
          await _queue.markFailed(
            operacao.operationId,
            desfecho.message ?? 'O servidor recusou a operação.',
          );
          falhas++;
      }
    }

    return SyncReport(
      sent: lote.length,
      accepted: aceitas,
      failed: falhas,
      conflicting: conflitos,
    );
  }
}
