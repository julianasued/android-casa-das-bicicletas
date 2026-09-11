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
  static const int schemaVersion = 1;

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
          // Fase 1 não tem versão anterior em campo. Quando tiver, cada degrau
          // entra aqui — e apagar o banco não é migração: a fila de operações
          // pendentes leva vendas que ainda não chegaram ao servidor.
          throw UnsupportedError(
            'Migração de $from para $to não implementada.',
          );
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
  ];
}
