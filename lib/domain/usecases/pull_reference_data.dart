/// Traz do servidor o que o terminal precisa para vender sem rede (RF34).
///
/// Até existir, o cache só se enchia das buscas que o vendedor fazia online — e
/// essas buscas filtram ativos. A consequência: **produto desativado no
/// servidor ficava no cache para sempre**, porque nenhuma busca o traria de
/// volta para ser corrigido, e a venda offline saía com ele (OFF-005). O `pull`
/// manda a desativação como atualização (`is_active: false`), e aplicar o
/// retrato tira o produto da vitrine.
///
/// É incremental: guarda o `synced_at` que o servidor devolveu e manda de volta
/// em `?since=`. A primeira chamada traz o retrato inteiro da loja; as
/// seguintes, no dia em que nada mudou, não trazem nada.
///
/// Falhar aqui **não atrapalha ninguém**: o cache continua com o que já tinha, e
/// a venda offline continua possível com o catálogo de antes — que é melhor do
/// que não vender. Quem avisa o vendedor de que o catálogo está velho é a faixa
/// da tela de venda.
library;

import '../../core/result.dart';
import '../entities/reference_snapshot.dart';
import '../repositories/reference_store.dart';
import '../repositories/sync_repository.dart';

/// O que a chamada trouxe, para a tela e para quem depura.
class PullReport {
  const PullReport({
    required this.syncedAt,
    required this.products,
    required this.customers,
    required this.categories,
  });

  final DateTime syncedAt;
  final int products;
  final int customers;
  final int categories;

  bool get isEmpty => products == 0 && customers == 0 && categories == 0;
}

class PullReferenceData {
  const PullReferenceData({
    required SyncRepository sync,
    required ReferenceStore cache,
  })  : _sync = sync,
        _cache = cache;

  final SyncRepository _sync;
  final ReferenceStore _cache;

  Future<Result<PullReport>> call() async {
    final desde = await _cache.lastReferenceSync();
    final resultado = await _sync.pull(since: desde);

    if (resultado case Err(:final failure)) return Err(failure);

    final retrato = (resultado as Ok<ReferenceSnapshot>).value;
    await _aplicar(retrato);

    return Ok(
      PullReport(
        syncedAt: retrato.syncedAt,
        products: retrato.products.length,
        customers: retrato.customers.length,
        categories: retrato.categories.length,
      ),
    );
  }

  Future<void> _aplicar(ReferenceSnapshot retrato) async {
    // A ordem não importa para o resultado, mas o marcador vem **por último**:
    // se a gravação falhar no meio, a próxima chamada pede desde o mesmo
    // instante e refaz o trabalho, em vez de pular a mudança que faltou.
    await _cache.saveCategories(retrato.categories);
    await _cache.saveProducts(retrato.products);
    await _cache.saveCustomers(retrato.customers);
    if (retrato.store case final loja?) await _cache.learnStore(loja);
    await _cache.saveReferenceSync(retrato.syncedAt);
  }
}
