/// O que o vendedor vê quando a rede cai (§13.9).
///
/// O cache só tem valor se a queda de rede virar "catálogo de ontem" em vez de
/// tela de erro. E só é seguro se erro do servidor **não** virar isso: um 403
/// disfarçado de sucesso esconderia problema de permissão, e um 422 esconderia
/// contrato quebrado.
library;

import 'dart:io';

import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/local/local_database.dart';
import 'package:casa_das_bicicletas/data/local/reference_cache.dart';
import 'package:casa_das_bicicletas/data/repositories/catalog_repository_impl.dart';
import 'package:casa_das_bicicletas/data/repositories/customer_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase db;
  late ReferenceCache cache;

  setUp(() {
    db = LocalDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    cache = ReferenceCache(db);
  });

  tearDown(() => db.close());

  Map<String, Object?> produtoJson({
    int id = 10,
    String name = 'Pneu Aro 15',
    String price = '250.00',
  }) =>
      {
        'id': id,
        'sku': 'PNEU-A15-001',
        'name': name,
        'category': 'PNEUS',
        'category_name': 'Pneus',
        'price': price,
        'barcode': '7891234567895',
        'is_active': true,
      };

  Future<CatalogRepositoryImpl> catalogo(RecordingTransport transport) async {
    final deps = buildTestDependencies(transport: transport);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    return CatalogRepositoryImpl(deps.apiClient, cache: cache);
  }

  group('catálogo', () {
    test('a busca online enche o cache no caminho de volta', () async {
      final online = await catalogo(
        RecordingTransport((_) => jsonResponse({'results': [produtoJson()]})),
      );

      await online.searchProducts(query: 'Pneu');

      // O que o vendedor consulta é o que ele vende: o cache se enche do
      // catálogo que importa, sem baixar a loja inteira.
      expect(await cache.hasProducts, isTrue);
    });

    test('sem rede responde o que está no cache', () async {
      await cache.saveProducts([
        Product(
          id: 10,
          sku: 'PNEU-A15-001',
          name: 'Pneu Aro 15',
          categoryCode: 'PNEUS',
          categoryName: 'Pneus',
          price: const Money.fromCents(25000),
          barcode: '7891234567895',
        ),
      ]);

      final offline = await catalogo(
        RecordingTransport((_) => throw const SocketException('sem rede')),
      );

      final resultado = await offline.searchProducts(query: 'Pneu');

      expect(resultado, isA<Ok<List<Product>>>());
      expect((resultado as Ok<List<Product>>).value.single.name, 'Pneu Aro 15');
    });

    test('sem rede e sem cache continua sendo falha, não lista vazia', () async {
      // Dizer "nenhum produto" quando não se sabe é pior que dizer "sem rede":
      // o vendedor procuraria o produto no estoque achando que saiu da linha.
      final offline = await catalogo(
        RecordingTransport((_) => throw const SocketException('sem rede')),
      );

      final resultado = await offline.searchProducts(query: 'Pneu');
      expect(resultado, isA<Err<List<Product>>>());
      expect((resultado as Err<List<Product>>).failure, isA<NetworkFailure>());
    });

    test('erro do servidor não cai para o cache', () async {
      await cache.saveProducts([
        Product(
          id: 10,
          sku: 'X',
          name: 'Do cache',
          categoryCode: 'PNEUS',
          categoryName: 'Pneus',
          price: const Money.fromCents(100),
        ),
      ]);

      final comErro = await catalogo(
        RecordingTransport(
          (_) => errorResponse(statusCode: 403, code: 'PERMISSION_DENIED'),
        ),
      );

      final resultado = await comErro.searchProducts();

      // 403 é resposta legítima e precisa chegar a quem chamou.
      expect(resultado, isA<Err<List<Product>>>());
    });

    test('o preço do cache é o da última vez que o servidor respondeu',
        () async {
      final online = await catalogo(
        RecordingTransport(
          (_) => jsonResponse({'results': [produtoJson(price: '275.00')]}),
        ),
      );
      await online.searchProducts();

      final offline = await catalogo(
        RecordingTransport((_) => throw const SocketException('sem rede')),
      );
      final resultado = await offline.searchProducts();

      final produto = (resultado as Ok<List<Product>>).value.single;
      expect(produto.price, const Money.fromCents(27500));
    });
  });

  group('clientes', () {
    test('sem rede responde o cliente já conhecido', () async {
      final deps = buildTestDependencies(
        transport: RecordingTransport(
          (_) => jsonResponse({
            'results': [
              {'id': 77, 'name': 'João Silva', 'is_active': true},
            ],
          }),
        ),
      );
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

      final online = CustomerRepositoryImpl(deps.apiClient, cache: cache);
      await online.search();

      final offlineDeps = buildTestDependencies(
        transport: RecordingTransport((_) => throw const SocketException('sem rede')),
      );
      await offlineDeps.session
          .saveConfiguration(deviceId: 'M10-0001', storeId: 1);
      final offline =
          CustomerRepositoryImpl(offlineDeps.apiClient, cache: cache);

      final resultado = await offline.search(query: 'João');
      expect(resultado.valueOrNull?.single.name, 'João Silva');
    });
  });
}
