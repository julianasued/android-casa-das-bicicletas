/// O cache local de referência (RF34), contra SQLite de verdade.
///
/// Roda sobre `sqflite_common_ffi` em memória, e não sobre um dublê: o que se
/// quer conferir aqui é justamente o SQL — `LIKE`, índice, `REPLACE` e o que
/// acontece com acento e com aspas no nome do cliente. Um fake de banco
/// responderia o que eu programasse, e passaria por cima disso.
library;

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/data/local/local_database.dart';
import 'package:casa_das_bicicletas/data/local/reference_cache.dart';
import 'package:casa_das_bicicletas/domain/entities/customer.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Product _produto({
  int id = 10,
  String sku = 'PNEU-A15-001',
  String name = 'Pneu Aro 15',
  String categoryCode = 'PNEUS',
  int priceCents = 25000,
  String? barcode = '7891234567895',
  bool isActive = true,
}) =>
    Product(
      id: id,
      sku: sku,
      name: name,
      categoryCode: categoryCode,
      categoryName: 'Pneus',
      price: Money.fromCents(priceCents),
      barcode: barcode,
      isActive: isActive,
    );

void main() {
  sqfliteFfiInit();

  late LocalDatabase db;
  late ReferenceCache cache;

  setUp(() {
    db = LocalDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    cache = ReferenceCache(db);
  });

  tearDown(() => db.close());

  group('produtos', () {
    test('guarda e devolve o que a busca online trouxe', () async {
      await cache.saveProducts([_produto()]);

      final encontrados = await cache.searchProducts();
      expect(encontrados, hasLength(1));
      expect(encontrados.single.sku, 'PNEU-A15-001');
      expect(encontrados.single.price, const Money.fromCents(25000));
    });

    test('preço não perde centavo na ida e volta', () async {
      // Guardar em centavos é o que garante isto; `REAL` daria 1000.0000001.
      await cache.saveProducts([_produto(priceCents: 100001)]);

      final encontrado = (await cache.searchProducts()).single;
      expect(encontrado.price, const Money.fromCents(100001));
      expect(encontrado.price.toDisplayString(), r'R$ 1.000,01');
    });

    test('busca por nome, SKU e código de barras', () async {
      await cache.saveProducts([
        _produto(id: 1, name: 'Pneu Aro 15', sku: 'PNEU-15', barcode: '111'),
        _produto(id: 2, name: 'Câmara de ar', sku: 'CAM-26', barcode: '222'),
      ]);

      expect(await cache.searchProducts(query: 'Pneu'), hasLength(1));
      expect(await cache.searchProducts(query: 'CAM-26'), hasLength(1));
      expect(await cache.searchProducts(query: '222'), hasLength(1));
      expect(await cache.searchProducts(query: 'nada disso'), isEmpty);
    });

    test('busca acha o termo no meio do nome', () async {
      await cache.saveProducts([_produto(name: 'Pneu Aro 15 reforçado')]);
      expect(await cache.searchProducts(query: 'Aro'), hasLength(1));
      expect(await cache.searchProducts(query: 'reforçado'), hasLength(1));
    });

    test('filtra por categoria', () async {
      await cache.saveProducts([
        _produto(id: 1, categoryCode: 'PNEUS'),
        _produto(id: 2, categoryCode: 'PECAS'),
      ]);

      final pneus = await cache.searchProducts(categoryCode: 'PNEUS');
      expect(pneus, hasLength(1));
      expect(pneus.single.categoryCode, 'PNEUS');
    });

    test('produto inativo não aparece na busca', () async {
      await cache.saveProducts([_produto(isActive: false)]);
      expect(await cache.searchProducts(), isEmpty);
    });

    test('regravar o mesmo id atualiza em vez de duplicar', () async {
      // O servidor é a fonte de verdade: se o preço mudou, vale o novo.
      await cache.saveProducts([_produto(priceCents: 25000)]);
      await cache.saveProducts([_produto(priceCents: 27500)]);

      final encontrados = await cache.searchProducts();
      expect(encontrados, hasLength(1));
      expect(encontrados.single.price, const Money.fromCents(27500));
    });

    test('nome com apóstrofo não quebra a busca', () async {
      // Se algum dia alguém montar o SQL com interpolação, este teste cai.
      await cache.saveProducts([_produto(name: "Guidão D'Ouro")]);
      expect(await cache.searchProducts(query: "D'Ouro"), hasLength(1));
    });

    test('acha pelo código de barras do leitor', () async {
      await cache.saveProducts([_produto(barcode: '7891234567895')]);

      expect(await cache.findProductByBarcode('7891234567895'), isNotNull);
      expect(await cache.findProductByBarcode('  7891234567895  '), isNotNull);
      // Não ter no cache é diferente de não existir: quem chama tenta o servidor.
      expect(await cache.findProductByBarcode('000'), isNull);
    });

    test('produto sem código de barras não responde por código vazio', () async {
      await cache.saveProducts([_produto(barcode: null)]);
      expect(await cache.findProductByBarcode(''), isNull);
    });
  });

  group('clientes', () {
    test('guarda e busca por nome, documento e telefone', () async {
      await cache.saveCustomers([
        const Customer(
          id: 77,
          name: 'João Silva',
          document: '12345678901',
          phone: '11999990000',
        ),
      ]);

      expect(await cache.searchCustomers(query: 'João'), hasLength(1));
      expect(await cache.searchCustomers(query: '123456'), hasLength(1));
      expect(await cache.searchCustomers(query: '99999'), hasLength(1));
      expect(await cache.searchCustomers(query: 'Maria'), isEmpty);
    });

    test('busca vazia lista todos os ativos', () async {
      await cache.saveCustomers([
        const Customer(id: 1, name: 'Ana'),
        const Customer(id: 2, name: 'Bruno', isActive: false),
      ]);

      final todos = await cache.searchCustomers();
      expect(todos, hasLength(1));
      expect(todos.single.name, 'Ana');
    });

    test('ordena por nome, que é como o vendedor procura', () async {
      await cache.saveCustomers([
        const Customer(id: 1, name: 'Zeca'),
        const Customer(id: 2, name: 'Ana'),
      ]);

      expect(
        (await cache.searchCustomers()).map((c) => c.name),
        ['Ana', 'Zeca'],
      );
    });
  });

  group('categorias', () {
    test('guarda e devolve as ativas', () async {
      await cache.saveCategories(const [
        ProductCategory(id: 1, code: 'PNEUS', name: 'Pneus'),
        ProductCategory(id: 2, code: 'VELHO', name: 'Antigo', isActive: false),
      ]);

      final ativas = await cache.listCategories();
      expect(ativas, hasLength(1));
      expect(ativas.single.code, 'PNEUS');
    });
  });

  group('idade do cache', () {
    test('sem nada guardado não há data nem produto', () async {
      expect(await cache.lastProductSync(), isNull);
      expect(await cache.hasProducts, isFalse);
    });

    test('depois de gravar, diz quando foi', () async {
      final antes = DateTime.now().toUtc();
      await cache.saveProducts([_produto()]);

      final quando = await cache.lastProductSync();
      expect(quando, isNotNull);
      expect(
        quando!.isBefore(antes.subtract(const Duration(seconds: 5))),
        isFalse,
      );
      expect(await cache.hasProducts, isTrue);
    });
  });

  group('esquema', () {
    test('lista vazia não abre transação nem erra', () async {
      await cache.saveProducts(const []);
      await cache.saveCustomers(const []);
      await cache.saveCategories(const []);
      expect(await cache.hasProducts, isFalse);
    });
  });
}
