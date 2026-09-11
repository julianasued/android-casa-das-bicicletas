/// Cópia local do que o servidor já sabe (RF34, §13.9).
///
/// Guarda catálogo, categorias e clientes para que consulta de produto e de
/// cliente continue funcionando sem rede. Nada nasce aqui: os identificadores
/// são os do servidor, e o cache é sempre substituível. Perder este banco custa
/// um download, não uma venda — o que nasce no terminal é a venda, e isso é da
/// Fase 2.
///
/// **Por que gravar o que a busca online já devolveu**, em vez de esperar uma
/// rota de sincronização: o `/sync/pull/` da API ainda não tem payload
/// especificado — a própria especificação lista a paginação dele como pendência.
/// Aproveitar as buscas que o vendedor já faz enche o cache sem inventar
/// contrato, e no balcão o catálogo consultado é justamente o que se vende.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/store.dart';
import 'local_database.dart';

class ReferenceCache {
  const ReferenceCache(this._db);

  final LocalDatabase _db;

  // ---------------------------------------------------------------------------
  // Escrita
  // ---------------------------------------------------------------------------

  /// Guarda o que a busca online devolveu.
  ///
  /// `ConflictAlgorithm.replace` porque o servidor é a fonte de verdade
  /// (§13.11): se o preço mudou, o que vale é o que acabou de chegar.
  Future<void> saveProducts(Iterable<Product> products) async {
    if (products.isEmpty) return;
    final agora = DateTime.now().toUtc().toIso8601String();
    final db = await _db.open();

    await db.transaction((txn) async {
      final lote = txn.batch();
      for (final product in products) {
        lote.insert(
          'cached_product',
          {
            'id': product.id,
            'sku': product.sku,
            'name': product.name,
            'category_code': product.categoryCode,
            'category_name': product.categoryName,
            'price_cents': product.price.cents,
            'barcode': product.barcode,
            'is_active': product.isActive ? 1 : 0,
            'cached_at': agora,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await lote.commit(noResult: true);
    });
  }

  Future<void> saveCustomers(Iterable<Customer> customers) async {
    if (customers.isEmpty) return;
    final agora = DateTime.now().toUtc().toIso8601String();
    final db = await _db.open();

    await db.transaction((txn) async {
      final lote = txn.batch();
      for (final customer in customers) {
        lote.insert(
          'cached_customer',
          {
            'id': customer.id,
            'name': customer.name,
            'document': customer.document,
            'phone': customer.phone,
            'address': customer.address,
            'is_active': customer.isActive ? 1 : 0,
            'cached_at': agora,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await lote.commit(noResult: true);
    });
  }

  Future<void> saveCategories(Iterable<ProductCategory> categories) async {
    if (categories.isEmpty) return;
    final agora = DateTime.now().toUtc().toIso8601String();
    final db = await _db.open();

    await db.transaction((txn) async {
      final lote = txn.batch();
      for (final category in categories) {
        lote.insert(
          'cached_category',
          {
            'id': category.id,
            'code': category.code,
            'name': category.name,
            'is_active': category.isActive ? 1 : 0,
            'cached_at': agora,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await lote.commit(noResult: true);
    });
  }

  // ---------------------------------------------------------------------------
  // Leitura
  // ---------------------------------------------------------------------------

  /// Busca por nome, SKU ou código de barras — os mesmos campos do `?q=`.
  Future<List<Product>> searchProducts({
    String query = '',
    String? categoryCode,
  }) async {
    final db = await _db.open();
    final termo = query.trim();

    final where = <String>['is_active = 1'];
    final args = <Object?>[];

    if (termo.isNotEmpty) {
      where.add('(name LIKE ?1 OR sku LIKE ?1 OR barcode LIKE ?1)');
      args.add('%$termo%');
    }
    if (categoryCode != null && categoryCode.isNotEmpty) {
      where.add('category_code = ?${args.length + 1}');
      args.add(categoryCode);
    }

    final linhas = await db.query(
      'cached_product',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'name',
      limit: 50,
    );

    return linhas.map(_productFromRow).toList();
  }

  /// Produto pelo código lido no leitor.
  ///
  /// Devolve `null` quando não há nesse cache — e "não tenho" é diferente de
  /// "não existe": quem chama decide se tenta o servidor.
  Future<Product?> findProductByBarcode(String barcode) async {
    final db = await _db.open();
    final linhas = await db.query(
      'cached_product',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [barcode.trim()],
      limit: 1,
    );

    return linhas.isEmpty ? null : _productFromRow(linhas.single);
  }

  Future<List<Customer>> searchCustomers({String query = ''}) async {
    final db = await _db.open();
    final termo = query.trim();

    final linhas = await db.query(
      'cached_customer',
      where: termo.isEmpty
          ? 'is_active = 1'
          : 'is_active = 1 AND (name LIKE ?1 OR document LIKE ?1 OR phone LIKE ?1)',
      whereArgs: termo.isEmpty ? null : ['%$termo%'],
      orderBy: 'name',
      limit: 50,
    );

    return linhas.map(_customerFromRow).toList();
  }

  Future<List<ProductCategory>> listCategories() async {
    final db = await _db.open();
    final linhas = await db.query(
      'cached_category',
      where: 'is_active = 1',
      orderBy: 'name',
    );

    return [
      for (final linha in linhas)
        ProductCategory(
          id: linha['id']! as int,
          code: linha['code']! as String,
          name: linha['name']! as String,
          isActive: linha['is_active'] == 1,
        ),
    ];
  }

  /// Quando o cache foi alimentado pela última vez.
  ///
  /// Serve para dizer ao operador de quando é o preço que ele está vendo — um
  /// catálogo de duas semanas atrás merece aviso na tela.
  Future<DateTime?> lastProductSync() async {
    final db = await _db.open();
    final linhas = await db.rawQuery(
      'SELECT MAX(cached_at) AS ultimo FROM cached_product',
    );

    final valor = linhas.single['ultimo'] as String?;
    return valor == null ? null : DateTime.parse(valor);
  }

  Future<bool> get hasProducts async {
    final db = await _db.open();
    final linhas = await db.rawQuery('SELECT 1 FROM cached_product LIMIT 1');
    return linhas.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Identidade do terminal
  // ---------------------------------------------------------------------------

  /// Aprende com o documento que o servidor mandou pronto.
  ///
  /// O cabeçalho da notinha — nome, CNPJ e endereço da loja, e o nome do
  /// terminal — não está no `SaleDraft` nem na sessão: só chega dentro do
  /// documento do `POST /sales/`. Guardar o que já veio é o que permite montar
  /// o documento offline depois, sem endpoint novo e sem o operador digitar
  /// nada.
  ///
  /// Campos vazios não sobrescrevem o que já se sabia: um documento que veio
  /// sem endereço não deve apagar o endereço aprendido ontem.
  Future<void> learnIdentity(PrintedDocument document) => _saveIdentity(
        storeCode: document.storeCode,
        storeName: document.storeName,
        storeDocument: document.storeDocument,
        storeAddress: document.storeAddress,
        terminalName: document.terminalName,
      );

  /// Aprende com `GET /stores/{id}/`, que roda na seleção do vendedor.
  ///
  /// Cobre o terminal que ainda não imprimiu nada online — só não traz o nome
  /// do terminal, que a rota de loja não conhece.
  Future<void> learnStore(Store store) => _saveIdentity(
        storeCode: store.code,
        storeName: store.name,
        storeDocument: store.document,
        storeAddress: store.address,
      );

  Future<void> _saveIdentity({
    String? storeCode,
    String? storeName,
    String? storeDocument,
    String? storeAddress,
    String? terminalName,
  }) async {
    final db = await _db.open();
    final atual = await identity();

    String? manter(String? novo, String? antigo) {
      final limpo = novo?.trim();
      return limpo == null || limpo.isEmpty ? antigo : limpo;
    }

    await db.insert(
      'terminal_identity',
      {
        'id': 1,
        'store_code': manter(storeCode, atual?.storeCode),
        'store_name': manter(storeName, atual?.storeName),
        'store_document': manter(storeDocument, atual?.storeDocument),
        'store_address': manter(storeAddress, atual?.storeAddress),
        'terminal_name': manter(terminalName, atual?.terminalName),
        'learned_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TerminalIdentity?> identity() async {
    final db = await _db.open();
    final linhas = await db.query('terminal_identity', where: 'id = 1', limit: 1);
    if (linhas.isEmpty) return null;

    final linha = linhas.single;
    return TerminalIdentity(
      storeCode: linha['store_code'] as String?,
      storeName: linha['store_name'] as String?,
      storeDocument: linha['store_document'] as String?,
      storeAddress: linha['store_address'] as String?,
      terminalName: linha['terminal_name'] as String?,
      learnedAt: DateTime.parse(linha['learned_at']! as String),
    );
  }

  // ---------------------------------------------------------------------------

  Product _productFromRow(Map<String, Object?> row) => Product(
        id: row['id']! as int,
        sku: row['sku']! as String,
        name: row['name']! as String,
        categoryCode: row['category_code']! as String,
        categoryName: row['category_name']! as String,
        price: Money.fromCents(row['price_cents']! as int),
        barcode: row['barcode'] as String?,
        isActive: row['is_active'] == 1,
      );

  Customer _customerFromRow(Map<String, Object?> row) => Customer(
        id: row['id']! as int,
        name: row['name']! as String,
        document: row['document'] as String?,
        phone: row['phone'] as String?,
        address: row['address'] as String?,
        isActive: row['is_active'] == 1,
      );
}

/// O que o terminal sabe sobre si e sobre a loja.
///
/// Aprendido, e não configurado: vem do documento que o servidor já mandou ou
/// da rota da loja. Nada aqui é digitado pelo operador.
class TerminalIdentity {
  const TerminalIdentity({
    this.storeCode,
    this.storeName,
    this.storeDocument,
    this.storeAddress,
    this.terminalName,
    required this.learnedAt,
  });

  final String? storeCode;
  final String? storeName;
  final String? storeDocument;
  final String? storeAddress;
  final String? terminalName;
  final DateTime learnedAt;

  /// Dá para montar um documento com isto?
  ///
  /// O nome da loja é o mínimo: um cupom sem ele não identifica quem vendeu.
  /// Endereço e CNPJ saem em branco sem impedir a venda — o papel serve para
  /// retirada, e o §13.9 manda imprimir offline.
  bool get canPrintOffline => (storeName ?? '').isNotEmpty;
}
