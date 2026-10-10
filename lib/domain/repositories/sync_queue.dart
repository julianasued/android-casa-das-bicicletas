/// A fila de operações, vista pelo domínio (RF35).
///
/// O caso de uso precisa poder guardar uma venda que não foi enviada, e ler o
/// que o terminal ainda deve ao servidor. Como isso é gravado — SQLite, hoje —
/// é assunto da camada de dados.
library;

import '../entities/pending_operation.dart';

abstract interface class SyncQueue {
  /// Põe na fila. Repetir a mesma operação não duplica (RF36).
  Future<void> enqueue(PendingOperation operation);

  /// O que ainda não chegou ao servidor, para a tela avisar o operador.
  Future<QueueSummary> summary();

  /// O que não vai sair da fila sozinho: conflito e recusa.
  ///
  /// O resumo diz **quantas**; isto diz **quais**, com o motivo que o servidor
  /// deu. Sem a lista, "2 operações travadas" é um número que não leva a lugar
  /// nenhum — e a venda que ficou de fora existe no papel que o cliente levou.
  Future<List<PendingOperation>> needingAttention();
}
