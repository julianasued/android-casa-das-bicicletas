/// Envio do que ficou pendente (API §3.9).
library;

import '../../core/result.dart';
import '../entities/pending_operation.dart';
import '../entities/sync_outcome.dart';

abstract interface class SyncRepository {
  /// Manda o lote e devolve um desfecho por operação.
  ///
  /// Uma `Err` aqui é falha do lote inteiro — rede caiu no meio, servidor fora.
  /// Recusa de operação individual não é erro: vem dentro da lista, porque uma
  /// venda pode entrar enquanto a seguinte conflita.
  Future<Result<List<SyncOutcome>>> push(List<PendingOperation> operations);
}
