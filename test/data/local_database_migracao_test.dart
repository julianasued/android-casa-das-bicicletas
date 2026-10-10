/// OFF-009 — voltar uma versão do APK não pode trancar o banco do terminal.
///
/// O APK é instalado por arquivo no M10, então voltar uma versão é cenário
/// real. Quando isso acontece, o número de esquema gravado no banco é
/// rebaixado, e a próxima instalação do APK novo reexecuta o degrau de
/// migração sobre tabelas que já existem. Sem `IF NOT EXISTS`, a abertura
/// falhava com "table already exists" — e falhar na abertura não derruba uma
/// tela, derruba **o banco inteiro**, inclusive a fila de vendas que o
/// servidor ainda não viu.
///
/// O caminho inverso também é tratado: banco mais novo do que o código (alguém
/// instalou um APK novo e voltou para este). O padrão do `sqflite` recusa a
/// abertura e a opção pronta apaga o arquivo; aqui o esquema extra é aceito
/// como está, porque apagar significa apagar dinheiro que já saiu da loja.
library;

import 'dart:io';

import 'package:casa_das_bicicletas/data/local/local_database.dart';
import 'package:casa_das_bicicletas/data/local/operation_queue.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PendingOperation _venda(String id) => PendingOperation(
      operationId: id,
      type: OperationType.saleCreate,
      payload: {'uuid': id, 'payment_method': 'PIX', 'seller_id': 12},
      occurredAt: DateTime.utc(2026, 10, 9, 14, 30),
      status: SyncStatus.pendente,
    );

void main() {
  sqfliteFfiInit();

  late Directory pasta;
  late String caminho;

  setUp(() async {
    // Arquivo de verdade, não `inMemoryDatabasePath`: o que se testa aqui é
    // reabrir o **mesmo** banco com códigos de versões diferentes.
    pasta = await Directory.systemTemp.createTemp('cdb-migracao');
    caminho = p.join(pasta.path, 'casa_das_bicicletas.db');
  });

  tearDown(() => pasta.delete(recursive: true));

  /// Abre o arquivo como um APK de outra versão faria, sem passar pelo
  /// `LocalDatabase` deste código.
  Future<void> abrirComoOutraVersao(int versao) async {
    final banco = await databaseFactoryFfi.openDatabase(
      caminho,
      options: OpenDatabaseOptions(
        version: versao,
        // O APK antigo não conhecia tabela nenhuma das novas; o que importa
        // aqui é só que ele grava o número de versão dele no arquivo.
        onDowngrade: (db, from, to) async {},
        onCreate: (db, version) async {},
        onUpgrade: (db, from, to) async {},
      ),
    );
    await banco.close();
  }

  /// Lê a versão gravada no arquivo.
  ///
  /// Só com o `LocalDatabase` fechado: o `sqflite` compartilha o handle por
  /// caminho, e fechar o daqui fecharia o de lá no meio do teste.
  Future<int> versaoGravada() async {
    final banco = await databaseFactoryFfi.openDatabase(caminho);
    final versao = await banco.getVersion();
    await banco.close();
    return versao;
  }

  test('a fila sobrevive a voltar uma versão e atualizar de novo', () async {
    final primeiro = LocalDatabase(factory: databaseFactoryFfi, path: caminho);
    await OperationQueue(primeiro).enqueue(_venda('op-antes'));
    await primeiro.close();

    // O operador instala o APK anterior: o número gravado cai.
    await abrirComoOutraVersao(2);
    expect(await versaoGravada(), 2);

    // E depois volta para o atual, que reexecuta o degrau 3.
    final depois = LocalDatabase(factory: databaseFactoryFfi, path: caminho);
    final fila = OperationQueue(depois);

    final guardada = await fila.find('op-antes');
    expect(guardada, isNotNull, reason: 'a venda não enviada se perdeu');
    expect(guardada!.payload['seller_id'], 12);

    // E o banco continua utilizável, não só legível.
    await fila.enqueue(_venda('op-depois'));
    expect(await fila.nextBatch(), hasLength(2));
    await depois.close();

    expect(await versaoGravada(), LocalDatabase.schemaVersion);
  });

  test('banco de versão futura abre sem apagar nada', () async {
    final atual = LocalDatabase(factory: databaseFactoryFfi, path: caminho);
    await OperationQueue(atual).enqueue(_venda('op-do-futuro'));
    await atual.close();

    // Alguém instalou um APK mais novo, com esquema maior, e voltou para este.
    await abrirComoOutraVersao(9);
    expect(await versaoGravada(), 9);

    final reaberto = LocalDatabase(factory: databaseFactoryFfi, path: caminho);
    final fila = OperationQueue(reaberto);

    final guardada = await fila.find('op-do-futuro');
    expect(guardada, isNotNull, reason: 'o banco foi apagado na volta de versão');
    await reaberto.close();

    // O número gravado **cai** para o deste código — é assim que o `sqflite`
    // encerra o `onDowngrade`. As tabelas extras continuam lá, intactas; o que
    // isso significa é que o APK mais novo, ao voltar, vai reexecutar os
    // degraus dele do 4 ao 9. É a razão de cada degrau precisar ser idempotente,
    // e não só os que existem hoje.
    expect(await versaoGravada(), LocalDatabase.schemaVersion);
  });

  test('banco novo nasce com o esquema inteiro', () async {
    final db = LocalDatabase(factory: databaseFactoryFfi, path: caminho);
    final banco = await db.open();

    final tabelas = await banco.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['table'],
    );
    final nomes = tabelas.map((linha) => linha['name']).toSet();

    expect(
      nomes,
      containsAll([
        'cached_product',
        'cached_customer',
        'cached_category',
        'terminal_identity',
        'pending_operation',
      ]),
    );
    await db.close();
    expect(await versaoGravada(), LocalDatabase.schemaVersion);
  });
}
