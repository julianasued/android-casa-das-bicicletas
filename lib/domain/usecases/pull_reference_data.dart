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

  /// Teto de páginas numa carga, para o laço não ser infinito.
  ///
  /// Com 200 por página, cobre 100 mil registros — muito além de uma loja de
  /// bicicletas. Existe porque laço que depende do servidor dizer "acabou" é
  /// laço que trava se o servidor disser errado, e travar aqui é travar o
  /// agendador que também envia a fila.
  static const int _tetoDePaginas = 500;

  Future<Result<PullReport>> call() async {
    final desde = await _cache.lastReferenceSync();

    var produtos = 0;
    var clientes = 0;
    var categorias = 0;
    DateTime? instante;
    String? cursor;

    // Percorre as páginas aplicando cada uma; o marcador fica para o fim.
    for (var pagina = 0; pagina < _tetoDePaginas; pagina++) {
      final resultado = await _sync.pull(since: desde, cursor: cursor);
      if (resultado case Err(:final failure)) return Err(failure);

      final retrato = (resultado as Ok<ReferenceSnapshot>).value;
      await _aplicar(retrato);

      produtos += retrato.products.length;
      clientes += retrato.customers.length;
      categorias += retrato.categories.length;
      instante = retrato.syncedAt;

      cursor = retrato.nextCursor;
      if (cursor == null) break;
    }

    // O marcador por último, e só depois da **última** página: gravá-lo a cada
    // página faria uma carga interrompida dar-se por completa, e a próxima
    // chamada pediria `?since=` daquele instante — as páginas que faltavam
    // nunca seriam pedidas de novo. Interromper tem de custar refazer, nunca
    // perder.
    if (instante case final quando?) {
      await _cache.saveReferenceSync(quando);
    }

    return Ok(
      PullReport(
        syncedAt: instante ?? DateTime.now(),
        products: produtos,
        customers: clientes,
        categories: categorias,
      ),
    );
  }

  /// Grava uma página no cache. **Sem tocar no marcador.**
  ///
  /// Reaplicar a mesma página não causa dano: o cache é upsert, e o registro
  /// que chegar duas vezes é gravado duas vezes com o mesmo valor. É o que
  /// torna o reenvio de uma página seguro depois de uma interrupção.
  Future<void> _aplicar(ReferenceSnapshot retrato) async {
    await _cache.saveCategories(retrato.categories);
    await _cache.saveProducts(retrato.products);
    await _cache.saveCustomers(retrato.customers);
    if (retrato.store case final loja?) await _cache.learnStore(loja);
  }
}
