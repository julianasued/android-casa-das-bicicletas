/// Envio do lote de operações pendentes (API §3.9).
library;

import '../../core/result.dart';
import '../../domain/entities/pending_operation.dart';
import '../../domain/entities/reference_snapshot.dart';
import '../../domain/entities/sync_outcome.dart';
import '../../domain/repositories/sync_repository.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';

/// Quantos registros por página do `pull`.
///
/// Dois limites se encontram aqui: a resposta precisa chegar dentro dos 20
/// segundos do `API_TIMEOUT_SECONDS`, e cada ida à rede custa tempo de balcão.
/// 200 é o padrão do servidor, cujo teto é 500.
const int paginaDoPull = 200;

class SyncRepositoryImpl implements SyncRepository {
  const SyncRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<SyncOutcome>>> push(
    List<PendingOperation> operations,
  ) async {
    // **Sem chave de idempotência de lote, de propósito.**
    //
    // Antes ia uma, nova a cada envio, com um comentário afirmando que ela
    // "evita o reprocessamento no servidor". Duas coisas estavam erradas: chave
    // nova nunca casa com nada, e `POST /sync/push/` não é decorada com
    // `@idempotent` — o cabeçalho era ignorado do outro lado. Era promessa
    // dupla de uma proteção inexistente.
    //
    // Quem protege é o `operation_id` de cada operação (RF36), e a proteção é
    // melhor do que a do lote seria: se a resposta se perder, o reenvio pode
    // trazer um conjunto **diferente** — a fila andou, outra venda entrou — e
    // mesmo assim nada duplica, porque a dedução é operação por operação. Uma
    // chave de lote estável, pelo conjunto, faria o servidor devolver a
    // resposta guardada de um conjunto que já não é o atual.
    final response = await _api.post(
      ApiEndpoints.syncPush,
      body: {
        'operations': [for (final op in operations) op.toSyncJson()],
      },
    );

    return mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) syncOutcomeFromJson(item),
      ],
    );
  }

  @override
  Future<Result<ReferenceSnapshot>> pull({DateTime? since, String? cursor}) async {
    final response = await _api.get(
      ApiEndpoints.syncPull,
      query: {
        // `page_size` é o que **liga** a paginação no servidor: sem ele, a
        // carga vem inteira, que é o contrato de antes (§3.9.3). Este terminal
        // sabe percorrer páginas, então pede.
        'page_size': '$paginaDoPull',
        // Com cursor, o servidor ignora o `since` da querystring e usa o que
        // está dentro do cursor — mandá-lo junto é informação, não contradição.
        if (cursor != null) 'cursor': cursor,
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );

    return mapApiResponse(
      response,
      (result) => referenceSnapshotFromJson(result.data),
    );
  }
}
