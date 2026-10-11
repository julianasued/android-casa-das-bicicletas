/// OFF-011/OFF-005 — o terminal passa a baixar os dados de referência.
///
/// Antes, o cache só se enchia das buscas que o vendedor fazia online, e essas
/// buscas filtram ativos. A consequência era o cache nunca se corrigir: produto
/// desativado no servidor ficava na vitrine do terminal para sempre, porque
/// nenhuma busca o traria de volta marcado como inativo.
///
/// O que estes testes cobram: a desativação chega e é aplicada; o `?since=` sai
/// do que o servidor disse na vez anterior; e falhar não estraga o que o cache
/// já tinha.
library;

import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/local/local_database.dart';
import 'package:casa_das_bicicletas/data/local/reference_cache.dart';
import 'package:casa_das_bicicletas/domain/entities/customer.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/entities/reference_snapshot.dart';
import 'package:casa_das_bicicletas/domain/entities/store.dart';
import 'package:casa_das_bicicletas/domain/entities/sync_outcome.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_repository.dart';
import 'package:casa_das_bicicletas/domain/usecases/pull_reference_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Product _pneu({int id = 1, String nome = 'Pneu 26', bool ativo = true}) => Product(
      id: id,
      sku: 'PN-$id',
      name: nome,
      categoryCode: 'PNEUS',
      categoryName: 'Pneus',
      price: const Money.fromCents(12000),
      barcode: '789$id',
      isActive: ativo,
    );

/// Servidor de mentira: guarda o `since` que recebeu e devolve o que foi dito.
class _PullFalso implements SyncRepository {
  _PullFalso(this.respostas);

  final List<Result<ReferenceSnapshot>> respostas;
  final List<DateTime?> desdes = [];

  /// Os cursores que o terminal devolveu, na ordem — é o que prova que ele
  /// percorreu as páginas em vez de parar na primeira.
  final List<String?> cursores = [];
  int chamadas = 0;

  @override
  Future<Result<ReferenceSnapshot>> pull({DateTime? since, String? cursor}) async {
    desdes.add(since);
    cursores.add(cursor);
    final resposta = respostas[chamadas.clamp(0, respostas.length - 1)];
    chamadas++;
    return resposta;
  }

  @override
  Future<Result<List<SyncOutcome>>> push(List<PendingOperation> operations) =>
      throw UnimplementedError();
}

void main() {
  sqfliteFfiInit();

  late LocalDatabase db;
  late ReferenceCache cache;

  setUp(() {
    db = LocalDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    cache = ReferenceCache(db, lojaAtual: () => 1);
  });

  tearDown(() => db.close());

  test('produto desativado no servidor sai da vitrine do terminal', () async {
    // O cache tem o produto ativo, como uma busca online o deixou.
    await cache.saveProducts([_pneu()]);
    expect(await cache.searchProducts(), hasLength(1));

    // O servidor manda a desativação como atualização, não como ausência.
    final servidor = _PullFalso([
      Ok(ReferenceSnapshot(
        syncedAt: DateTime.utc(2026, 10, 9, 12),
        products: [_pneu(ativo: false)],
      )),
    ]);

    final resultado = await PullReferenceData(sync: servidor, cache: cache)();

    expect(resultado, isA<Ok<PullReport>>());
    expect(
      await cache.searchProducts(),
      isEmpty,
      reason: 'o produto desativado continuou vendável offline',
    );
    expect(await cache.findProductByBarcode('7891'), isNull);
  });

  test('a primeira chamada não manda `since`; a seguinte manda o do servidor', () async {
    final servidor = _PullFalso([
      Ok(ReferenceSnapshot(syncedAt: DateTime.utc(2026, 10, 9, 12), products: [_pneu()])),
      Ok(ReferenceSnapshot(syncedAt: DateTime.utc(2026, 10, 9, 18))),
    ]);
    final usecase = PullReferenceData(sync: servidor, cache: cache);

    await usecase();
    await usecase();

    expect(servidor.desdes.first, isNull, reason: 'a primeira vez traz o retrato inteiro');
    expect(servidor.desdes.last, DateTime.utc(2026, 10, 9, 12));
    expect(await cache.lastReferenceSync(), DateTime.utc(2026, 10, 9, 18));
  });

  group('carga em páginas (OFF-011)', () {
    test('percorre as páginas até o cursor acabar', () async {
      // A carga de uma loja grande não cabe numa resposta: o terminal desiste
      // em 20 segundos. Quem percorre é ele, devolvendo o cursor do servidor.
      final servidor = _PullFalso([
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          categories: const [ProductCategory(id: 1, code: 'PNEUS', name: 'Pneus')],
          nextCursor: 'pagina-2',
        )),
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          products: [_pneu()],
          nextCursor: 'pagina-3',
        )),
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          customers: const [Customer(id: 77, name: 'Maria Souza')],
        )),
      ]);

      final resultado = await PullReferenceData(sync: servidor, cache: cache)();

      expect(servidor.chamadas, 3);
      expect(servidor.cursores, [null, 'pagina-2', 'pagina-3']);

      // O relatório soma as páginas, não conta só a última.
      final relatorio = (resultado as Ok<PullReport>).value;
      expect(relatorio.categories, 1);
      expect(relatorio.products, 1);
      expect(relatorio.customers, 1);

      expect(await cache.searchProducts(), hasLength(1));
      expect(await cache.searchCustomers(query: 'Maria'), hasLength(1));
    });

    test('o marcador só avança depois da última página', () async {
      // É aqui que a carga em páginas pode perder dado: gravar o marcador a
      // cada página faria a chamada seguinte pedir `?since=` daquele instante,
      // e as páginas que faltavam nunca seriam pedidas de novo.
      final servidor = _PullFalso([
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          products: [_pneu()],
          nextCursor: 'pagina-2',
        )),
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          products: [_pneu(id: 2, nome: 'Câmara 26')],
        )),
      ]);

      await PullReferenceData(sync: servidor, cache: cache)();

      expect(await cache.lastReferenceSync(), DateTime.utc(2026, 10, 9, 12));
      expect(await cache.searchProducts(), hasLength(2));
    });

    test('carga interrompida no meio não avança o marcador', () async {
      // A interrupção que importa: a primeira página entrou, a segunda falhou.
      // O cache fica com o que chegou — melhor que nada —, mas o marcador não
      // se move, então a próxima chamada **refaz** a carga inteira. Interromper
      // custa refazer; nunca perder.
      final servidor = _PullFalso([
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          products: [_pneu()],
          nextCursor: 'pagina-2',
        )),
        const Err(NetworkFailure()),
      ]);

      final resultado = await PullReferenceData(sync: servidor, cache: cache)();

      expect(resultado, isA<Err<PullReport>>());
      expect(await cache.lastReferenceSync(), isNull);
      expect(
        await cache.searchProducts(),
        hasLength(1),
        reason: 'o que chegou antes da falha vale: o cache não é tudo-ou-nada',
      );
    });

    test('depois de interromper, a carga recomeça do mesmo lugar', () async {
      final servidor = _PullFalso([
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 12),
          products: [_pneu()],
          nextCursor: 'pagina-2',
        )),
        const Err(NetworkFailure()),
        Ok(ReferenceSnapshot(
          syncedAt: DateTime.utc(2026, 10, 9, 18),
          products: [_pneu(), _pneu(id: 2, nome: 'Câmara 26')],
        )),
      ]);
      final usecase = PullReferenceData(sync: servidor, cache: cache);

      await usecase();
      await usecase();

      // Sem `since` nas duas vezes: o marcador não avançou na interrompida.
      expect(servidor.desdes, [null, null, null]);
      expect(await cache.lastReferenceSync(), DateTime.utc(2026, 10, 9, 18));
      expect(await cache.searchProducts(), hasLength(2));
    });

    test('a mesma página aplicada duas vezes não duplica no cache', () async {
      // O que garante que repetir é inofensivo: o cache é upsert. É por isso
      // que o servidor pode entregar um registro duas vezes — numa retomada,
      // por exemplo — sem estragar nada.
      final pagina = ReferenceSnapshot(
        syncedAt: DateTime.utc(2026, 10, 9, 12),
        products: [_pneu()],
        customers: const [Customer(id: 77, name: 'Maria Souza')],
      );
      final servidor = _PullFalso([Ok(pagina), Ok(pagina)]);
      final usecase = PullReferenceData(sync: servidor, cache: cache);

      await usecase();
      await usecase();

      expect(await cache.searchProducts(), hasLength(1));
      expect(await cache.searchCustomers(query: 'Maria'), hasLength(1));
    });

    test('servidor sem paginação continua funcionando', () async {
      // `next_cursor` ausente vira nulo no mapeador: uma página só, como antes.
      final servidor = _PullFalso([
        Ok(ReferenceSnapshot(syncedAt: DateTime.utc(2026, 10, 9, 12), products: [_pneu()])),
      ]);

      await PullReferenceData(sync: servidor, cache: cache)();

      expect(servidor.chamadas, 1);
      expect(await cache.lastReferenceSync(), DateTime.utc(2026, 10, 9, 12));
    });
  });

  test('o retrato enche catálogo, clientes, categorias e a loja', () async {
    final servidor = _PullFalso([
      Ok(ReferenceSnapshot(
        syncedAt: DateTime.utc(2026, 10, 9, 12),
        store: const Store(id: 1, code: 'L1', name: 'Casa das Bicicletas Centro'),
        products: [_pneu(), _pneu(id: 2, nome: 'Câmara 26')],
        customers: const [Customer(id: 77, name: 'Maria Souza')],
        categories: const [ProductCategory(id: 1, code: 'PNEUS', name: 'Pneus')],
      )),
    ]);

    final resultado = await PullReferenceData(sync: servidor, cache: cache)();

    final relatorio = (resultado as Ok<PullReport>).value;
    expect(relatorio.products, 2);
    expect(relatorio.customers, 1);
    expect(relatorio.categories, 1);
    expect(await cache.searchProducts(), hasLength(2));
    expect(await cache.searchCustomers(), hasLength(1));
    expect(await cache.listCategories(), hasLength(1));
    // A loja alimenta o cabeçalho do documento impresso sem rede.
    expect((await cache.identity())?.storeName, 'Casa das Bicicletas Centro');
  });

  test('falhar não estraga o que o cache já tinha', () async {
    await cache.saveProducts([_pneu()]);
    final servidor = _PullFalso([const Err(NetworkFailure())]);

    final resultado = await PullReferenceData(sync: servidor, cache: cache)();

    expect(resultado, isA<Err<PullReport>>());
    expect(await cache.searchProducts(), hasLength(1), reason: 'o cache foi esvaziado na falha');
    expect(await cache.lastReferenceSync(), isNull, reason: 'marcou sync que não aconteceu');
  });

  test('retrato vazio é desfecho normal, e avança o marcador', () async {
    // Dia em que nada mudou: o servidor responde só com `synced_at`.
    final servidor = _PullFalso([
      Ok(ReferenceSnapshot(syncedAt: DateTime.utc(2026, 10, 9, 20))),
    ]);

    final resultado = await PullReferenceData(sync: servidor, cache: cache)();

    expect((resultado as Ok<PullReport>).value.isEmpty, isTrue);
    expect(await cache.lastReferenceSync(), DateTime.utc(2026, 10, 9, 20));
  });

  test('o marcador é por loja: trocar de loja pede tudo de novo', () async {
    var loja = 1;
    final porLoja = ReferenceCache(db, lojaAtual: () => loja);
    final servidor = _PullFalso([
      Ok(ReferenceSnapshot(syncedAt: DateTime.utc(2026, 10, 9, 12), products: [_pneu()])),
      Ok(ReferenceSnapshot(syncedAt: DateTime.utc(2026, 10, 9, 13), products: [_pneu()])),
    ]);
    final usecase = PullReferenceData(sync: servidor, cache: porLoja);

    await usecase();
    loja = 2;
    await usecase();

    expect(
      servidor.desdes.last,
      isNull,
      reason: 'pediu só o que mudou desde um instante que vale para outro catálogo',
    );
  });
}
