/// Banco local do terminal (RF34).
///
/// O M10 fica no balcão de uma loja que pode perder internet no meio de um
/// atendimento. O que este banco guarda é o que permite continuar vendendo
/// quando isso acontece: o catálogo e os clientes já conhecidos (§13.9), e —
/// a partir da Fase 2 da Sprint 9 — a fila de operações pendentes (RF35).
///
/// **O cache é do terminal, não do usuário.** A loja é a mesma o dia inteiro e
/// o vendedor troca; guardar por sessão faria o catálogo sumir a cada troca de
/// turno, que é justamente quando ninguém quer esperar download.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Abre o banco e mantém o esquema no dia.
///
/// Uma instância só por processo: o `sqflite` serializa as escritas, e abrir o
/// mesmo arquivo duas vezes é como se perde transação em Android.
class LocalDatabase {
  LocalDatabase({DatabaseFactory? factory, String? path})
      : _factory = factory ?? databaseFactory,
        _path = path;

  static const String fileName = 'casa_das_bicicletas.db';

  /// Sobe quando o esquema muda; cada degrau precisa de um `onUpgrade`.
  static const int schemaVersion = 3;

  final DatabaseFactory _factory;
  final String? _path;

  Database? _database;

  Future<Database> open() async {
    if (_database case final Database aberto) return aberto;

    final caminho = _path ?? p.join(await _factory.getDatabasesPath(), fileName);

    final aberto = await _factory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          // Sem isto o SQLite aceita `REFERENCES` e não confere nada.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          for (final comando in _schema) {
            await db.execute(comando);
          }
        },
        onUpgrade: (db, from, to) async {
          // Apagar e recriar não é migração: a partir da Fase 2 este banco
          // guarda vendas que ainda não chegaram ao servidor, e perdê-las é
          // perder dinheiro que já saiu da loja.
          for (var versao = from + 1; versao <= to; versao++) {
            for (final comando in _migrations[versao] ?? const <String>[]) {
              await db.execute(comando);
            }
          }
        },
      ),
    );

    _database = aberto;
    return aberto;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Esquema da Fase 1: só o cache de leitura.
  ///
  /// Os identificadores são os do servidor, porque este cache é cópia do que
  /// ele já sabe — nada nasce aqui. Quem nasce no terminal é a venda, e isso é
  /// da Fase 2, com identificador próprio.
  static const List<String> _schema = [
    '''
    CREATE TABLE cached_product (
      id            INTEGER PRIMARY KEY,
      sku           TEXT    NOT NULL,
      name          TEXT    NOT NULL,
      category_code TEXT    NOT NULL,
      category_name TEXT    NOT NULL,
      price_cents   INTEGER NOT NULL,
      barcode       TEXT,
      is_active     INTEGER NOT NULL DEFAULT 1,
      cached_at     TEXT    NOT NULL
    )
    ''',
    // A busca do balcão é por nome e por código lido no leitor; as duas
    // precisam responder antes do cliente perder a paciência.
    'CREATE INDEX idx_cached_product_name ON cached_product (name)',
    'CREATE INDEX idx_cached_product_barcode ON cached_product (barcode)',
    'CREATE INDEX idx_cached_product_sku ON cached_product (sku)',
    '''
    CREATE TABLE cached_customer (
      id        INTEGER PRIMARY KEY,
      name      TEXT    NOT NULL,
      document  TEXT,
      phone     TEXT,
      address   TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      cached_at TEXT    NOT NULL
    )
    ''',
    'CREATE INDEX idx_cached_customer_name ON cached_customer (name)',
    '''
    CREATE TABLE cached_category (
      id        INTEGER PRIMARY KEY,
      code      TEXT    NOT NULL UNIQUE,
      name      TEXT    NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      cached_at TEXT    NOT NULL
    )
    ''',
    _createTerminalIdentity,
    ..._createQueue,
  ];

  /// Cada degrau de versão, para quem já tem o banco em campo.
  ///
  /// O `_schema` reaproveita estas listas: um banco novo nasce com tudo, e um
  /// antigo recebe só o que falta — sem dois lugares para manter sincronizados.
  static const Map<int, List<String>> _migrations = {
    2: [_createTerminalIdentity],
    3: _createQueue,
  };

  /// Fila de operações (RF35).
  ///
  /// `operation_id` é a chave primária, e não um autoincremento: ele é o
  /// identificador de idempotência (RF36), o mesmo valor que vai no
  /// `X-Idempotency-Key` e no `operation_id` do lote de sync. Gravar duas vezes
  /// a mesma operação é erro de programação, e a chave primária diz isso na
  /// hora em vez de deixar duas vendas iguais na fila.
  ///
  /// `payload` é o corpo REST em JSON. Guardar o corpo pronto — em vez de
  /// remontar da venda na hora de enviar — é o que garante que o servidor receba
  /// exatamente o que o papel do cliente diz, mesmo que a regra de preço mude
  /// entre a venda e a sincronização.
  static const List<String> _createQueue = [
    '''
    CREATE TABLE pending_operation (
      operation_id TEXT    PRIMARY KEY,
      type         TEXT    NOT NULL,
      payload      TEXT    NOT NULL,
      occurred_at  TEXT    NOT NULL,
      status       TEXT    NOT NULL,
      attempts     INTEGER NOT NULL DEFAULT 0,
      last_error   TEXT,
      server_id    INTEGER,
      conflict_id  TEXT,
      synced_at    TEXT,
      created_at   TEXT    NOT NULL
    )
    ''',
    // A fila é lida por status e enviada na ordem em que aconteceu: o servidor
    // precisa ver a venda antes do pagamento dela.
    'CREATE INDEX idx_pending_status ON pending_operation (status, occurred_at)',
  ];

  /// Identidade do terminal: o que o documento precisa e o `SaleDraft` não tem.
  ///
  /// Linha única (`CHECK (id = 1)`) porque um aparelho é um terminal de uma
  /// loja. `learned_at` registra quando foi aprendido: um endereço de loja de
  /// seis meses atrás ainda serve para o papel, mas quem depura merece saber a
  /// idade do dado.
  static const String _createTerminalIdentity = '''
    CREATE TABLE terminal_identity (
      id             INTEGER PRIMARY KEY CHECK (id = 1),
      store_code     TEXT,
      store_name     TEXT,
      store_document TEXT,
      store_address  TEXT,
      terminal_name  TEXT,
      learned_at     TEXT NOT NULL
    )
  ''';
}
