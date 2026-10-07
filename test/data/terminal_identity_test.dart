/// A identidade que o terminal aprende (Sprint 9, Fase 2).
///
/// O cabeçalho da notinha — nome, CNPJ e endereço da loja, e o nome do terminal
/// — não está no `SaleDraft` nem na sessão. Ele chega dentro do documento que o
/// servidor monta, e é guardado para o dia em que a rede cair e o terminal
/// precisar montar o documento sozinho.
library;

import 'package:casa_das_bicicletas/data/local/local_database.dart';
import 'package:casa_das_bicicletas/data/local/reference_cache.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/entities/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';

PrintedDocument _documento({
  String storeName = 'Casa das Bicicletas Centro',
  String storeDocument = '12345678000190',
  String storeAddress = 'Rua das Flores, 100',
  String terminalName = 'Caixa 1 - Loja 1',
}) =>
    printedDocumentFromJson({
      ...documentJson(),
      'store_name': storeName,
      'store_document': storeDocument,
      'store_address': storeAddress,
      'terminal_name': terminalName,
    });

void main() {
  sqfliteFfiInit();

  late LocalDatabase db;
  late ReferenceCache cache;

  setUp(() {
    db = LocalDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    cache = ReferenceCache(db);
  });

  tearDown(() => db.close());

  group('aprendizado', () {
    test('sem nada aprendido não há identidade', () async {
      expect(await cache.identity(), isNull);
    });

    test('aprende o cabeçalho do documento que o servidor mandou', () async {
      await cache.learnIdentity(_documento());

      final identidade = await cache.identity();
      expect(identidade, isNotNull);
      expect(identidade!.storeName, 'Casa das Bicicletas Centro');
      expect(identidade.storeDocument, '12345678000190');
      expect(identidade.storeAddress, 'Rua das Flores, 100');
      expect(identidade.terminalName, 'Caixa 1 - Loja 1');
      expect(identidade.canPrintOffline, isTrue);
    });

    test('aprende da loja, que é o que existe antes da primeira impressão',
        () async {
      await cache.learnStore(
        const Store(
          id: 1,
          code: 'L1',
          name: 'Casa das Bicicletas Centro',
          document: '12345678000190',
          address: 'Rua das Flores, 100',
        ),
      );

      final identidade = await cache.identity();
      expect(identidade!.storeName, 'Casa das Bicicletas Centro');
      // A rota da loja não conhece o terminal; só o documento traz esse nome.
      expect(identidade.terminalName, isNull);
    });

    test('guarda uma linha só, por mais que aprenda', () async {
      await cache.learnIdentity(_documento());
      await cache.learnIdentity(_documento(storeName: 'Outro nome'));

      final db2 = await db.open();
      final linhas = await db2.query('terminal_identity');
      expect(linhas, hasLength(1));
      expect((await cache.identity())!.storeName, 'Outro nome');
    });

    test('campo vazio não apaga o que já se sabia', () async {
      // Um documento que veio sem endereço não deve apagar o endereço de ontem.
      await cache.learnIdentity(_documento());
      await cache.learnIdentity(_documento(storeAddress: ''));

      expect((await cache.identity())!.storeAddress, 'Rua das Flores, 100');
    });

    test('a loja completa o que o documento não trouxe, e vice-versa', () async {
      // Primeiro só a loja (sem nome de terminal)...
      await cache.learnStore(
        const Store(id: 1, code: 'L1', name: 'Loja', address: 'Rua X'),
      );
      expect((await cache.identity())!.terminalName, isNull);

      // ...depois o documento acrescenta o terminal, sem perder o endereço.
      await cache.learnIdentity(_documento(storeAddress: ''));
      final identidade = await cache.identity();
      expect(identidade!.terminalName, 'Caixa 1 - Loja 1');
      expect(identidade.storeAddress, 'Rua X');
    });
  });

  group('pode imprimir offline?', () {
    test('sem nome de loja, não', () async {
      // Um cupom sem nome não identifica quem vendeu.
      await cache.learnStore(const Store(id: 1, code: 'L1', name: ''));
      final identidade = await cache.identity();
      expect(identidade?.canPrintOffline ?? false, isFalse);
    });

    test('com nome de loja, sim — endereço e CNPJ em branco não impedem',
        () async {
      await cache.learnStore(const Store(id: 1, code: 'L1', name: 'Loja'));
      expect((await cache.identity())!.canPrintOffline, isTrue);
    });
  });

  group('migração', () {
    test('banco da versão 1 recebe a tabela nova sem perder o cache', () async {
      // Apagar e recriar não é migração: da Fase 2 em diante este banco leva
      // vendas que ainda não chegaram ao servidor.
      // Nome próprio por execução e apagado antes: o `sqflite_common_ffi`
      // guarda o arquivo entre rodadas, e um banco sobrevivente faria este
      // teste passar sozinho e falhar na suíte inteira.
      final arquivo = 'migracao_${DateTime.now().microsecondsSinceEpoch}.db';
      await databaseFactoryFfi.deleteDatabase(arquivo);

      // Cria um banco na versão 1, do jeito que a Fase 1 criava.
      final v1 = await databaseFactoryFfi.openDatabase(
        arquivo,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE cached_customer (
                id        INTEGER PRIMARY KEY,
                name      TEXT    NOT NULL,
                document  TEXT,
                phone     TEXT,
                address   TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                cached_at TEXT    NOT NULL
              )
            ''');
            await db.insert('cached_customer', {
              'id': 77,
              'name': 'João Silva',
              'is_active': 1,
              'cached_at': '2026-09-10T12:00:00Z',
            });
          },
        ),
      );
      await v1.close();

      // Abre com o esquema atual: a migração roda.
      final migrado = LocalDatabase(
        factory: databaseFactoryFfi,
        path: arquivo,
      );
      final aberto = await migrado.open();

      expect(await aberto.getVersion(), LocalDatabase.schemaVersion);

      // O cliente da versão 1 continua lá.
      final clientes = await ReferenceCache(migrado).searchCustomers();
      expect(clientes.single.name, 'João Silva');

      // E a tabela nova existe.
      await ReferenceCache(migrado).learnStore(
        const Store(id: 1, code: 'L1', name: 'Loja'),
      );
      expect(await ReferenceCache(migrado).identity(), isNotNull);

      await migrado.close();
      await databaseFactoryFfi.deleteDatabase(arquivo);
    });
  });
}
