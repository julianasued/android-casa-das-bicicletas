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
  ///
  /// Os comandos de cada degrau são escritos de forma idempotente — `IF NOT
  /// EXISTS`, ou recriar o que é descartável: eles podem rodar mais de uma vez
  /// no mesmo banco (ver `onUpgrade`).
  static const int schemaVersion = 5;

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
          //
          // Cada degrau é idempotente (`IF NOT EXISTS`) porque pode rodar duas
          // vezes: o APK é instalado por arquivo no M10, e voltar uma versão
          // rebaixa o número gravado no banco — o degrau seguinte é então
          // reexecutado sobre tabelas que já existem. Sem isso, a abertura
          // falhava com "table already exists" e **o banco inteiro ficava
          // inacessível**, inclusive a fila de vendas não enviadas.
          for (var versao = from + 1; versao <= to; versao++) {
            for (final comando in _migrations[versao] ?? const <String>[]) {
              await db.execute(comando);
            }
            await _ajustes[versao]?.call(db);
          }
        },
        // Banco mais novo do que este código: aceita como está.
        //
        // Acontece quando alguém instala um APK mais novo e volta para este.
        // **Este vazio é o mesmo que o padrão do `sqflite` faz** — sem
        // `onDowngrade` ele não recusa nem apaga, só rebaixa o número gravado
        // (`database_mixin.dart`, `setVersion` ao fim do bloco de versão). Está
        // escrito por dois motivos: deixar a escolha visível e ocupar o lugar,
        // porque a opção pronta para este caso é `onDatabaseDowngradeDelete`,
        // que **apaga o banco** — aqui, apagar vendas que o servidor ainda não
        // viu.
        //
        // Esquema com mais tabelas do que este código conhece não o atrapalha:
        // ele lê o subconjunto que entende. O efeito colateral é o número cair,
        // e por isso o APK novo reexecuta os degraus dele quando voltar — que é
        // o que o `IF NOT EXISTS` de cada degrau torna inofensivo.
        onDowngrade: (db, from, to) async {},
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
    ..._createCachedProduct,
    ..._createCachedCustomer,
    '''
    CREATE TABLE IF NOT EXISTS cached_category (
      id        INTEGER PRIMARY KEY,
      code      TEXT    NOT NULL UNIQUE,
      name      TEXT    NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      cached_at TEXT    NOT NULL
    )
    ''',
    _createTerminalIdentity,
    _createReferenceSync,
    ..._createQueue,
  ];

  /// Catálogo em cache, **escopado por loja** (RF34).
  ///
  /// `store_id` existe porque o terminal pode ser reconfigurado para outra
  /// loja: sem ele, o catálogo e os preços da loja anterior continuavam
  /// aparecendo na busca offline, e a venda sairia com o preço de outro lugar.
  static const List<String> _createCachedProduct = [
    _tabelaCachedProduct,
    ..._indicesCachedProduct,
  ];

  static const String _tabelaCachedProduct = '''
    CREATE TABLE IF NOT EXISTS cached_product (
      id            INTEGER PRIMARY KEY,
      store_id      INTEGER,
      sku           TEXT    NOT NULL,
      name          TEXT    NOT NULL,
      category_code TEXT    NOT NULL,
      category_name TEXT    NOT NULL,
      price_cents   INTEGER NOT NULL,
      barcode       TEXT,
      is_active     INTEGER NOT NULL DEFAULT 1,
      cached_at     TEXT    NOT NULL
    )
    ''';

  /// A busca do balcão é por nome e por código lido no leitor; as duas precisam
  /// responder antes do cliente perder a paciência.
  static const List<String> _indicesCachedProduct = [
    'CREATE INDEX IF NOT EXISTS idx_cached_product_name ON cached_product (name)',
    'CREATE INDEX IF NOT EXISTS idx_cached_product_barcode ON cached_product (barcode)',
    'CREATE INDEX IF NOT EXISTS idx_cached_product_sku ON cached_product (sku)',
    'CREATE INDEX IF NOT EXISTS idx_cached_product_store ON cached_product (store_id)',
  ];

  /// Clientes em cache, pelo mesmo motivo — e com um agravante: aqui há CPF,
  /// telefone e endereço, que não devem sobrar no aparelho de outra loja.
  static const List<String> _createCachedCustomer = [
    _tabelaCachedCustomer,
    ..._indicesCachedCustomer,
  ];

  static const String _tabelaCachedCustomer = '''
    CREATE TABLE IF NOT EXISTS cached_customer (
      id        INTEGER PRIMARY KEY,
      store_id  INTEGER,
      name      TEXT    NOT NULL,
      document  TEXT,
      phone     TEXT,
      address   TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      cached_at TEXT    NOT NULL
    )
    ''';

  static const List<String> _indicesCachedCustomer = [
    'CREATE INDEX IF NOT EXISTS idx_cached_customer_name ON cached_customer (name)',
    'CREATE INDEX IF NOT EXISTS idx_cached_customer_store ON cached_customer (store_id)',
  ];

  /// Cada degrau de versão, para quem já tem o banco em campo.
  ///
  /// O `_schema` reaproveita estas listas: um banco novo nasce com tudo, e um
  /// antigo recebe só o que falta — sem dois lugares para manter sincronizados.
  static const Map<int, List<String>> _migrations = {
    2: [_createTerminalIdentity],
    3: _createQueue,
    // v4 está em `_ajustes`: acrescentar coluna preservando o que já existe
    // não cabe numa lista de DDL idempotente (ver lá).
    5: [_createReferenceSync],
  };

  /// Degraus que precisam de código, não só de DDL.
  ///
  /// Existe porque `ALTER TABLE ADD COLUMN` não aceita `IF NOT EXISTS` no
  /// SQLite, e o `onUpgrade` precisa poder rodar o mesmo degrau duas vezes
  /// (ver a explicação lá). A alternativa seria recriar a tabela — mas o cache
  /// recriado deixa o terminal **sem catálogo** logo depois de atualizar o
  /// APK, que é justamente quando ele pode estar sem rede e precisando vender.
  static final Map<int, Future<void> Function(Database)> _ajustes = {
    // v4 — `store_id` no cache (RF34). Sem ele, terminal reconfigurado para
    // outra loja continuava mostrando o catálogo e os clientes da anterior na
    // busca offline. As linhas que já estavam ali ficam com `store_id` nulo:
    // são de antes de existir escopo, e a primeira busca online as substitui
    // já com a loja certa.
    4: (db) async {
      // A ordem importa: tabela, coluna, índice.
      //
      // A tabela pode não existir — a cadeia de migração nunca a criou para
      // quem veio da v1 —, e aí nasce já com a coluna. Se existir, é o `ALTER`
      // que acrescenta. E o índice sobre `store_id` só pode vir depois das
      // duas coisas.
      await db.execute(_tabelaCachedProduct);
      await db.execute(_tabelaCachedCustomer);
      await _acrescentarColuna(db, 'cached_product', 'store_id', 'INTEGER');
      await _acrescentarColuna(db, 'cached_customer', 'store_id', 'INTEGER');
      for (final comando in [..._indicesCachedProduct, ..._indicesCachedCustomer]) {
        await db.execute(comando);
      }
    },
  };

  /// `ALTER TABLE ADD COLUMN` que pode rodar duas vezes.
  static Future<void> _acrescentarColuna(
    Database db,
    String tabela,
    String coluna,
    String tipo,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    // Lista vazia é tabela que não existe — toda tabela tem ao menos uma
    // coluna. Não é erro: o degrau acabou de criá-la, já com a coluna.
    if (colunas.isEmpty) return;
    if (colunas.any((linha) => linha['name'] == coluna)) return;
    await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $tipo');
  }

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
    CREATE TABLE IF NOT EXISTS pending_operation (
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
    'CREATE INDEX IF NOT EXISTS idx_pending_status ON pending_operation (status, occurred_at)',
  ];

  /// Identidade do terminal: o que o documento precisa e o `SaleDraft` não tem.
  ///
  /// Linha única (`CHECK (id = 1)`) porque um aparelho é um terminal de uma
  /// loja. `learned_at` registra quando foi aprendido: um endereço de loja de
  /// seis meses atrás ainda serve para o papel, mas quem depura merece saber a
  /// idade do dado.
  /// Até quando o cache já recebeu dados de referência do servidor (RF34).
  ///
  /// Uma linha só, como a identidade: um aparelho é um terminal de uma loja. É o
  /// `synced_at` que o `GET /sync/pull/` devolve, e que a chamada seguinte manda
  /// de volta em `?since=` — guardar a hora do servidor, e não a nossa, é o que
  /// evita perder mudança por diferença de relógio.
  ///
  /// `store_id` porque o marcador é da loja: terminal reconfigurado não pode
  /// continuar pedindo "o que mudou desde" um instante que vale para outro
  /// catálogo.
  static const String _createReferenceSync = '''
    CREATE TABLE IF NOT EXISTS reference_sync (
      id        INTEGER PRIMARY KEY CHECK (id = 1),
      store_id  INTEGER,
      synced_at TEXT NOT NULL
    )
  ''';

  static const String _createTerminalIdentity = '''
    CREATE TABLE IF NOT EXISTS terminal_identity (
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
