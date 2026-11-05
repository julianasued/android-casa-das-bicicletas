/// Envio do que ficou pendente (API §3.9).
library;

import '../../core/result.dart';
import '../entities/pending_operation.dart';
import '../entities/reference_snapshot.dart';
import '../entities/sync_outcome.dart';

abstract interface class SyncRepository {
  /// Manda o lote e devolve um desfecho por operação.
  ///
  /// Uma `Err` aqui é falha do lote inteiro — rede caiu no meio, servidor fora.
  /// Recusa de operação individual não é erro: vem dentro da lista, porque uma
  /// venda pode entrar enquanto a seguinte conflita.
  Future<Result<List<SyncOutcome>>> push(List<PendingOperation> operations);

  /// Baixa o que mudou no servidor desde [since] (RF34).
  ///
  /// Sem [since], traz o retrato inteiro da loja — é a primeira vez do
  /// terminal, ou a primeira depois de ele mudar de loja.
  Future<Result<ReferenceSnapshot>> pull({DateTime? since, String? cursor});
}
