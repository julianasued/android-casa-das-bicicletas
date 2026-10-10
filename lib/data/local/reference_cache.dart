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
import '../../domain/entities/terminal_identity.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/store.dart';
import '../../domain/repositories/reference_store.dart';
import 'local_database.dart';

class ReferenceCache implements ReferenceStore {
  /// [lojaAtual] diz de qual loja é o cache, e é consultada a cada operação —
  /// o terminal pode ser reconfigurado sem o aplicativo reiniciar.
  const ReferenceCache(this._db, {int? Function()? lojaAtual}) : _lojaAtual = lojaAtual;

  final LocalDatabase _db;
  final int? Function()? _lojaAtual;

  /// A loja que escopa tudo o que se grava e tudo o que se lê.
  ///
  /// Sem nenhuma configurada, vale `null` — e aí escrita e leitura ficam as duas
  /// no mesmo escopo nulo, que é coerente: grava sem loja, lê sem loja. O
  /// filtro usa `IS`, que no SQLite compara `NULL` como valor, então não há um
  /// caminho em que uma busca enxergue o cache de outro escopo.
  int? get _loja => _lojaAtual?.call();

  // ---------------------------------------------------------------------------
  // Escrita
  // ---------------------------------------------------------------------------

  /// Guarda o que a busca online devolveu.
  ///
  /// `ConflictAlgorithm.replace` porque o servidor é a fonte de verdade
  /// (§13.11): se o preço mudou, o que vale é o que acabou de chegar.
  @override
  Future<void> saveProducts(Iterable<Product> products) async {
    if (products.isEmpty) return;
    final agora = DateTime.now().toUtc().toIso8601String();
    final loja = _loja;
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
            'store_id': loja,
            'cached_at': agora,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await lote.commit(noResult: true);
    });
  }

  @override
  Future<void> saveCustomers(Iterable<Customer> customers) async {
    if (customers.isEmpty) return;
    final agora = DateTime.now().toUtc().toIso8601String();
    final loja = _loja;
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
            'store_id': loja,
            'cached_at': agora,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await lote.commit(noResult: true);
    });
  }

  @override
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

    final where = <String>['is_active = 1', 'store_id IS ?'];
    final args = <Object?>[_loja];

    if (termo.isNotEmpty) {
      // Sem `?1` posicional: já existe um argumento antes (a loja), e repetir
      // o termo é mais claro do que contar posições à mão.
      where.add('(name LIKE ? OR sku LIKE ? OR barcode LIKE ?)');
      args.addAll(['%$termo%', '%$termo%', '%$termo%']);
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
      where: 'barcode = ? AND is_active = 1 AND store_id IS ?',
      whereArgs: [barcode.trim(), _loja],
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
          ? 'is_active = 1 AND store_id IS ?'
          : 'is_active = 1 AND store_id IS ? '
              'AND (name LIKE ? OR document LIKE ? OR phone LIKE ?)',
      whereArgs: termo.isEmpty ? [_loja] : [_loja, '%$termo%', '%$termo%', '%$termo%'],
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
      'SELECT MAX(cached_at) AS ultimo FROM cached_product WHERE store_id IS ?',
      [_loja],
    );

    final valor = linhas.single['ultimo'] as String?;
    return valor == null ? null : DateTime.parse(valor);
  }

  /// Até quando o cache desta loja já recebeu dados do servidor (RF34).
  ///
  /// É o que vai em `?since=` na próxima chamada do `pull`. `null` quando nunca
  /// houve pull, ou quando o marcador guardado é de outra loja — aí a próxima
  /// chamada traz tudo, que é o certo: o catálogo é outro.
  @override
  Future<DateTime?> lastReferenceSync() async {
    final db = await _db.open();
    final linhas = await db.query(
      'reference_sync',
      where: 'id = 1 AND store_id IS ?',
      whereArgs: [_loja],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return DateTime.parse(linhas.single['synced_at']! as String);
  }

  /// Guarda o `synced_at` que o servidor devolveu.
  @override
  Future<void> saveReferenceSync(DateTime syncedAt) async {
    final db = await _db.open();
    await db.insert(
      'reference_sync',
      {
        'id': 1,
        'store_id': _loja,
        'synced_at': syncedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> get hasProducts async {
    final db = await _db.open();
    final linhas = await db.rawQuery(
      'SELECT 1 FROM cached_product WHERE store_id IS ? LIMIT 1',
      [_loja],
    );
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
  @override
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
