/// O contrato do `GET /sync/pull/` (API §3.9, RF34).
///
/// É a fronteira com o servidor: se a leitura do payload estiver errada, o
/// cache do terminal se enche de nada e ninguém percebe até a venda offline
/// falhar. Por isso o corpo usado aqui é o que a rota devolve de verdade —
/// `synced_at`, `since`, `store`, `product_categories`, `products`,
/// `customers`.
library;

import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/repositories/sync_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/reference_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Map<String, Object?> _corpoDoServidor() => {
      'synced_at': '2026-10-09T15:00:00Z',
      'since': null,
      'store': {
        'id': 1,
        'code': 'L1',
        'name': 'Casa das Bicicletas Centro',
        'document': '12345678000190',
        'address': 'Rua das Flores, 100',
      },
      'product_categories': [
        {'id': 1, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
      ],
      'products': [
        {
          'id': 10,
          'sku': 'PN-10',
          'name': 'Pneu 26 Cravado',
          'category': 'PNEUS',
          'category_name': 'Pneus',
          'price': '120.00',
          'barcode': '78910',
          'is_active': true,
        },
        {
          'id': 11,
          'sku': 'PN-11',
          'name': 'Pneu que saiu de linha',
          'category': 'PNEUS',
          'category_name': 'Pneus',
          'price': '90.00',
          'barcode': '78911',
          // A desativação chega como atualização, não como ausência — é o que
          // permite ao cache tirar o produto da vitrine.
          'is_active': false,
        },
      ],
      'customers': [
        {
          'id': 77,
          'name': 'Maria Souza',
          'document': '12345678901',
          'phone': '11999990000',
          'address': 'Rua A, 1',
          'is_active': true,
        },
      ],
    };

void main() {
  late RecordingTransport transport;
  late SyncRepositoryImpl repository;

  Future<void> preparar(RecordingTransport http) async {
    transport = http;
    final deps = buildTestDependencies(transport: http);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    repository = SyncRepositoryImpl(deps.apiClient);
  }

  test('lê o retrato inteiro que o servidor devolve', () async {
    await preparar(RecordingTransport((_) => jsonResponse(_corpoDoServidor())));

    final resultado = await repository.pull();

    final retrato = (resultado as Ok<ReferenceSnapshot>).value;
    expect(retrato.syncedAt, DateTime.utc(2026, 10, 9, 15));
    expect(retrato.products, hasLength(2));
    expect(retrato.products.last.isActive, isFalse);
    expect(retrato.customers.single.name, 'Maria Souza');
    expect(retrato.categories.single.code, 'PNEUS');
    expect(retrato.store?.name, 'Casa das Bicicletas Centro');
    expect(retrato.total, 4);
  });

  test('sem `since`, pede o endereço limpo', () async {
    await preparar(RecordingTransport((_) => jsonResponse(_corpoDoServidor())));

    await repository.pull();

    expect(transport.lastRequest.url.path, endsWith('/sync/pull/'));
    expect(transport.lastRequest.url.queryParameters.containsKey('since'), isFalse);
  });

  test('com `since`, manda o instante em ISO 8601 UTC', () async {
    await preparar(RecordingTransport((_) => jsonResponse(_corpoDoServidor())));

    await repository.pull(since: DateTime.utc(2026, 10, 8, 12, 30));

    expect(
      transport.lastRequest.url.queryParameters['since'],
      '2026-10-08T12:30:00.000Z',
    );
  });

  test('pede paginação: é o `page_size` que a liga no servidor', () async {
    // Sem `page_size` o servidor manda a carga inteira — o contrato de antes,
    // que o APK já instalado depende. Este terminal sabe percorrer páginas,
    // então pede (§3.9.3, OFF-011).
    await preparar(RecordingTransport((_) => jsonResponse(_corpoDoServidor())));

    await repository.pull();

    expect(transport.lastRequest.url.queryParameters['page_size'], '200');
  });

  test('o cursor da página anterior vai na querystring', () async {
    await preparar(RecordingTransport((_) => jsonResponse(_corpoDoServidor())));

    await repository.pull(cursor: 'eyJjIjoicHJvZHVjdHMifQ');

    expect(
      transport.lastRequest.url.queryParameters['cursor'],
      'eyJjIjoicHJvZHVjdHMifQ',
    );
  });

  test('lê o `next_cursor` que o servidor devolveu', () async {
    final corpo = {..._corpoDoServidor(), 'next_cursor': 'proxima-pagina'};
    await preparar(RecordingTransport((_) => jsonResponse(corpo)));

    final resultado = await repository.pull();

    final retrato = (resultado as Ok<ReferenceSnapshot>).value;
    expect(retrato.nextCursor, 'proxima-pagina');
    expect(retrato.hasMore, isTrue);
  });

  test('sem `next_cursor` no corpo, a carga acabou', () async {
    // Servidor que ainda não pagina responde sem o campo: nulo é 'acabou', e
    // não 'não sei'.
    await preparar(RecordingTransport((_) => jsonResponse(_corpoDoServidor())));

    final resultado = await repository.pull();

    final retrato = (resultado as Ok<ReferenceSnapshot>).value;
    expect(retrato.nextCursor, isNull);
    expect(retrato.hasMore, isFalse);
  });

  test('listas ausentes são listas vazias, não erro', () async {
    // O dia em que nada mudou: o servidor responde só com o instante.
    await preparar(
      RecordingTransport(
        (_) => jsonResponse(const {'synced_at': '2026-10-09T20:00:00Z'}),
      ),
    );

    final resultado = await repository.pull(since: DateTime.utc(2026, 10, 9, 15));

    final retrato = (resultado as Ok<ReferenceSnapshot>).value;
    expect(retrato.isEmpty, isTrue);
    expect(retrato.store, isNull);
    expect(retrato.syncedAt, DateTime.utc(2026, 10, 9, 20));
  });
}
