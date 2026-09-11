/// Operação feita no terminal que ainda não chegou ao servidor (RF35).
///
/// O que entra aqui já aconteceu no balcão: a venda foi fechada, o papel saiu e
/// o cliente foi embora. A fila não é um "talvez" — é uma dívida do terminal com
/// o servidor, e é por isso que ela mora no SQLite e não na memória: reiniciar o
/// aparelho não pode apagar uma venda.
library;

/// Estados de sincronização do §13.9.
enum SyncStatus {
  /// Está na fila, esperando rede.
  pendente('PENDENTE_SINCRONIZACAO', 'Aguardando sincronização'),

  /// O servidor aceitou. Fica no banco por um tempo para a auditoria (RF37).
  sincronizado('SINCRONIZADO', 'Sincronizada'),

  /// O servidor recusou por um motivo que pode passar — rede instável, 5xx.
  /// Continua na fila e será tentada de novo.
  erro('ERRO_SINCRONIZACAO', 'Erro ao sincronizar'),

  /// O servidor recusou por divergência de estado (13.11). **Não** se resolve
  /// tentando de novo: precisa de decisão de gerente ou dono.
  conflitante('CONFLITANTE', 'Em conflito');

  const SyncStatus(this.code, this.label);

  final String code;
  final String label;

  static SyncStatus fromCode(String? code) => values.firstWhere(
        (status) => status.code == code,
        orElse: () => pendente,
      );

  /// Deve ser enviada na próxima tentativa.
  ///
  /// `erro` volta para a fila porque a causa costuma ser passageira;
  /// `conflitante` não, porque insistir produziria o mesmo conflito e encheria a
  /// auditoria de ruído.
  bool get shouldRetry => this == pendente || this == erro;

  /// Precisa de gente para resolver.
  bool get needsDecision => this == conflitante;
}

/// Tipos aceitos pelo `POST /sync/push/`.
///
/// Só o que o §13.9 permite offline. Cancelamento, devolução e mudança de regra
/// de comissão exigem servidor, e o próprio contrato do sync os rejeita com
/// `403` mesmo dentro de um lote.
enum OperationType {
  saleCreate('SALE_CREATE', 'Venda'),
  cashPayment('CASH_PAYMENT', 'Pagamento no caixa');

  const OperationType(this.code, this.label);

  final String code;
  final String label;

  static OperationType? fromCode(String? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

class PendingOperation {
  const PendingOperation({
    required this.operationId,
    required this.type,
    required this.payload,
    required this.occurredAt,
    required this.status,
    this.attempts = 0,
    this.lastError,
    this.serverId,
    this.conflictId,
    this.syncedAt,
  });

  /// Identificador único da operação (RF36).
  ///
  /// É o mesmo valor que vai no `X-Idempotency-Key` quando a operação é enviada
  /// direto, e no `operation_id` quando vai pelo lote de sync — assim reenviar
  /// por qualquer um dos dois caminhos nunca duplica.
  final String operationId;

  final OperationType type;

  /// Corpo equivalente à rota REST da operação, como o contrato do sync pede.
  final Map<String, Object?> payload;

  /// Quando aconteceu no balcão, não quando foi enviada. É o que a auditoria
  /// offline precisa preservar (RF37).
  final DateTime occurredAt;

  final SyncStatus status;
  final int attempts;

  /// A mensagem da última recusa, para o operador e para quem depura.
  final String? lastError;

  /// O `id` que o servidor atribuiu, quando aceitou.
  final int? serverId;

  /// O conflito aberto no servidor, quando houve (13.11).
  final String? conflictId;

  final DateTime? syncedAt;

  PendingOperation copyWith({
    SyncStatus? status,
    int? attempts,
    String? lastError,
    int? serverId,
    String? conflictId,
    DateTime? syncedAt,
  }) =>
      PendingOperation(
        operationId: operationId,
        type: type,
        payload: payload,
        occurredAt: occurredAt,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
        serverId: serverId ?? this.serverId,
        conflictId: conflictId ?? this.conflictId,
        syncedAt: syncedAt ?? this.syncedAt,
      );

  /// No formato do `POST /sync/push/`.
  Map<String, Object?> toSyncJson() => {
        'operation_id': operationId,
        'type': type.code,
        'payload': payload,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      };
}

/// O que a tela precisa saber sobre a fila, sem listar tudo.
class QueueSummary {
  const QueueSummary({
    required this.pending,
    required this.failed,
    required this.conflicting,
    this.oldestPendingAt,
  });

  final int pending;
  final int failed;
  final int conflicting;

  /// A mais antiga esperando: é o que mede o tamanho do problema. Uma venda de
  /// dez minutos atrás é normal; de três dias, alguém precisa saber.
  final DateTime? oldestPendingAt;

  bool get isEmpty => pending == 0 && failed == 0 && conflicting == 0;

  /// Total que ainda não chegou ao servidor.
  int get outstanding => pending + failed + conflicting;
}
