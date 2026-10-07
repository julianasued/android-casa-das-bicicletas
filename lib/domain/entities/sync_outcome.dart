/// O que o servidor respondeu sobre cada operação do lote (§3.9).
///
/// O `POST /sync/push/` devolve um desfecho por operação, e não um sucesso do
/// lote: uma venda pode entrar enquanto a seguinte conflita. Tratar o lote como
/// unidade faria uma operação recusada arrastar as outras de volta para a fila.
library;

import 'pending_operation.dart';

class SyncOutcome {
  const SyncOutcome({
    required this.operationId,
    required this.status,
    this.serverId,
    this.conflictId,
    this.message,
  });

  final String operationId;

  /// `SINCRONIZADO`, `ERRO_SINCRONIZACAO` ou `CONFLITANTE` (§13.9).
  final SyncStatus status;

  /// O `id` que o servidor atribuiu, quando aceitou.
  final int? serverId;

  /// O conflito aberto para decisão de gerente ou dono (13.11).
  final String? conflictId;

  /// O que dizer ao operador quando não deu.
  final String? message;

  bool get accepted => status == SyncStatus.sincronizado;
}

/// O resultado de uma tentativa de sincronizar.
class SyncReport {
  const SyncReport({
    required this.sent,
    required this.accepted,
    required this.failed,
    required this.conflicting,
  });

  const SyncReport.nothingToDo()
      : sent = 0,
        accepted = 0,
        failed = 0,
        conflicting = 0;

  final int sent;
  final int accepted;
  final int failed;
  final int conflicting;

  bool get isEmpty => sent == 0;

  /// Vale avisar o operador: alguma coisa exige atenção dele ou do gerente.
  bool get needsAttention => failed > 0 || conflicting > 0;
}
