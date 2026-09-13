/// Envio do lote de operações pendentes (API §3.9).
library;

import '../../core/result.dart';
import '../../domain/entities/pending_operation.dart';
import '../../domain/entities/sync_outcome.dart';
import '../../domain/repositories/sync_repository.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';

class SyncRepositoryImpl implements SyncRepository {
  const SyncRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<SyncOutcome>>> push(
    List<PendingOperation> operations,
  ) async {
    final response = await _api.post(
      ApiEndpoints.syncPush,
      body: {
        'operations': [for (final op in operations) op.toSyncJson()],
      },
      // O lote inteiro também é idempotente: se a resposta se perder no caminho,
      // reenviar o mesmo conjunto não duplica nada (§1.5). Cada operação já
      // carrega o próprio `operation_id`, mas a chave do lote evita o
      // reprocessamento no servidor.
      idempotencyKey: ApiClient.newIdempotencyKey(),
    );

    return mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) syncOutcomeFromJson(item),
      ],
    );
  }
}
