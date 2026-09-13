/// A fila de operações pendentes (RF35), no SQLite.
///
/// O que está aqui já aconteceu no balcão. A fila é a dívida do terminal com o
/// servidor, e por isso todo cuidado é com **não perder** e **não duplicar** —
/// nunca com velocidade.
///
/// Ordem importa: as operações saem na sequência em que aconteceram, porque o
/// servidor precisa ver a venda antes do pagamento dela. Enviar fora de ordem
/// produziria um conflito que não existe.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/pending_operation.dart';
import '../../domain/repositories/sync_queue.dart';
import '../../domain/usecases/sync_pending_operations.dart';
import 'local_database.dart';

class OperationQueue implements SyncQueue, SyncableQueue {
  const OperationQueue(this._db);

  final LocalDatabase _db;

  /// Põe na fila.
  ///
  /// `ConflictAlgorithm.ignore` e não `replace`: se esta operação já está na
  /// fila, o que está gravado é o que o cliente levou no papel. Sobrescrever
  /// com uma tentativa nova apagaria o histórico de tentativas e, pior,
  /// substituiria o payload que o documento impresso reflete.
  @override
  Future<void> enqueue(PendingOperation operation) async {
    final db = await _db.open();
    await db.insert(
      'pending_operation',
      {
        'operation_id': operation.operationId,
        'type': operation.type.code,
        'payload': jsonEncode(operation.payload),
        'occurred_at': operation.occurredAt.toUtc().toIso8601String(),
        'status': operation.status.code,
        'attempts': operation.attempts,
        'last_error': operation.lastError,
        'server_id': operation.serverId,
        'conflict_id': operation.conflictId,
        'synced_at': operation.syncedAt?.toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// O que deve ir no próximo lote, na ordem em que aconteceu.
  ///
  /// Inclui as que falharam, porque a causa costuma ser passageira. Exclui as
  /// conflitantes: insistir produziria o mesmo conflito e encheria a auditoria
  /// de ruído.
  @override
  Future<List<PendingOperation>> nextBatch({int limit = 50}) async {
    final db = await _db.open();
    final linhas = await db.query(
      'pending_operation',
      where: 'status IN (?, ?)',
      whereArgs: [SyncStatus.pendente.code, SyncStatus.erro.code],
      orderBy: 'occurred_at ASC',
      limit: limit,
    );

    return linhas.map(_fromRow).toList();
  }

  /// Marca como aceita pelo servidor.
  @override
  Future<void> markSynced(String operationId, {int? serverId}) async {
    final db = await _db.open();
    await db.update(
      'pending_operation',
      {
        'status': SyncStatus.sincronizado.code,
        'server_id': serverId,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  /// Registra uma recusa que pode passar, e conta a tentativa.
  ///
  /// A contagem serve para a tela poder dizer "tentei sete vezes" em vez de só
  /// "erro" — sete tentativas falhando é outro problema que a primeira.
  @override
  Future<void> markFailed(String operationId, String error) async {
    final db = await _db.open();
    await db.rawUpdate(
      '''
      UPDATE pending_operation
         SET status = ?, last_error = ?, attempts = attempts + 1
       WHERE operation_id = ?
      ''',
      [SyncStatus.erro.code, error, operationId],
    );
  }

  /// Marca conflito (13.11): sai da fila de reenvio e espera decisão humana.
  @override
  Future<void> markConflicting(
    String operationId, {
    String? conflictId,
    String? error,
  }) async {
    final db = await _db.open();
    await db.rawUpdate(
      '''
      UPDATE pending_operation
         SET status = ?, conflict_id = ?, last_error = ?, attempts = attempts + 1
       WHERE operation_id = ?
      ''',
      [SyncStatus.conflitante.code, conflictId, error, operationId],
    );
  }

  Future<PendingOperation?> find(String operationId) async {
    final db = await _db.open();
    final linhas = await db.query(
      'pending_operation',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );

    return linhas.isEmpty ? null : _fromRow(linhas.single);
  }

  /// Quantas estão em cada situação, para a tela avisar o operador.
  @override
  Future<QueueSummary> summary() async {
    final db = await _db.open();

    final contagens = await db.rawQuery(
      'SELECT status, COUNT(*) AS total FROM pending_operation GROUP BY status',
    );

    var pendentes = 0;
    var falhas = 0;
    var conflitos = 0;

    for (final linha in contagens) {
      final total = linha['total']! as int;
      switch (SyncStatus.fromCode(linha['status'] as String?)) {
        case SyncStatus.pendente:
          pendentes = total;
        case SyncStatus.erro:
          falhas = total;
        case SyncStatus.conflitante:
          conflitos = total;
        case SyncStatus.sincronizado:
          break;
      }
    }

    final maisAntiga = await db.rawQuery(
      '''
      SELECT MIN(occurred_at) AS antiga
        FROM pending_operation
       WHERE status IN (?, ?)
      ''',
      [SyncStatus.pendente.code, SyncStatus.erro.code],
    );

    final quando = maisAntiga.single['antiga'] as String?;

    return QueueSummary(
      pending: pendentes,
      failed: falhas,
      conflicting: conflitos,
      oldestPendingAt: quando == null ? null : DateTime.parse(quando),
    );
  }

  /// Lista as que precisam de gente: conflito e erro repetido.
  Future<List<PendingOperation>> needingAttention() async {
    final db = await _db.open();
    final linhas = await db.query(
      'pending_operation',
      where: 'status IN (?, ?)',
      whereArgs: [SyncStatus.conflitante.code, SyncStatus.erro.code],
      orderBy: 'occurred_at ASC',
    );

    return linhas.map(_fromRow).toList();
  }

  /// Limpa o que já foi sincronizado há mais de [keepFor].
  ///
  /// Não apaga na hora: uma operação recém-sincronizada ainda serve para
  /// explicar ao operador o que aconteceu com aquela venda, e a auditoria
  /// offline (RF37) é justamente sobre preservar origem.
  Future<int> pruneSynced({Duration keepFor = const Duration(days: 7)}) async {
    final db = await _db.open();
    final limite = DateTime.now().toUtc().subtract(keepFor).toIso8601String();

    return db.delete(
      'pending_operation',
      where: 'status = ? AND synced_at IS NOT NULL AND synced_at < ?',
      whereArgs: [SyncStatus.sincronizado.code, limite],
    );
  }

  PendingOperation _fromRow(Map<String, Object?> row) => PendingOperation(
        operationId: row['operation_id']! as String,
        // O tipo é o do banco; se um dia um tipo novo for gravado por uma versão
        // mais nova do aplicativo e lido por uma antiga, cair em `saleCreate`
        // silenciosamente seria pior que falhar aqui.
        type: OperationType.fromCode(row['type'] as String?) ??
            (throw StateError('Tipo de operação desconhecido: ${row['type']}')),
        payload: jsonDecode(row['payload']! as String) as Map<String, Object?>,
        occurredAt: DateTime.parse(row['occurred_at']! as String),
        status: SyncStatus.fromCode(row['status'] as String?),
        attempts: row['attempts'] as int? ?? 0,
        lastError: row['last_error'] as String?,
        serverId: row['server_id'] as int?,
        conflictId: row['conflict_id'] as String?,
        syncedAt: row['synced_at'] == null
            ? null
            : DateTime.parse(row['synced_at']! as String),
      );
}
