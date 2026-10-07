/// Pendência de uma venda em notinha (RF15).
///
/// A notinha não passa pelo caixa: ela vira dívida do cliente (RF13/RF14), e é
/// esta entidade que o vendedor consulta antes de fiar outra vez. Quem recebe o
/// pagamento é o caixa (RF16), fora deste aplicativo.
library;

import '../../core/money.dart';

/// Estados da pendência, conforme o `CHECK` de `receivable` no modelo de dados.
enum ReceivableStatus {
  aberta('ABERTA', 'Aberta'),
  emRecebimento('EM_RECEBIMENTO', 'Em recebimento'),
  emAlteracao('EM_ALTERACAO', 'Em alteração'),
  quitada('QUITADA', 'Quitada'),
  cancelada('CANCELADA', 'Cancelada'),
  baixadaDevolucao('BAIXADA_DEVOLUCAO', 'Baixada por devolução'),
  vencida('VENCIDA', 'Vencida'),

  /// O backend pode ganhar estados novos antes deste aplicativo ser atualizado;
  /// um terminal que fica meses no balcão não pode quebrar por isso.
  desconhecido('', 'Desconhecida');

  const ReceivableStatus(this.code, this.label);

  final String code;
  final String label;

  static ReceivableStatus fromCode(String? code) => values.firstWhere(
        (status) => status.code == code,
        orElse: () => desconhecido,
      );

  /// Ainda deve dinheiro: é o que importa antes de liberar outra notinha.
  bool get isOutstanding =>
      this == aberta || this == emRecebimento || this == vencida;
}

class Receivable {
  const Receivable({
    required this.id,
    required this.saleId,
    required this.originalAmount,
    required this.paidAmount,
    required this.pendingAmount,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int saleId;
  final Money originalAmount;
  final Money paidAmount;
  final Money pendingAmount;
  final ReceivableStatus status;
  final DateTime createdAt;

  /// Houve pagamento, mas não o suficiente para quitar.
  ///
  /// A API hoje não aceita pagamento parcial — ela quita o saldo inteiro de uma
  /// vez —, mas o modelo de dados prevê `EM_RECEBIMENTO` e o campo
  /// `paid_amount` existe. Quem exibe a pendência não deveria supor que ele é
  /// sempre zero.
  bool get isPartiallyPaid =>
      paidAmount.cents > 0 && pendingAmount.cents > 0;
}

/// O que o vendedor precisa saber sobre o cliente antes de fiar.
///
/// Existe porque a pergunta do balcão não é "quais são as pendências" e sim
/// "posso vender fiado para esta pessoa" — e essa resposta é um total, não uma
/// lista.
extension ReceivableSummary on List<Receivable> {
  /// Soma do que ainda está devendo, ignorando o que já foi resolvido.
  Money get totalOutstanding => fold(
        const Money.zero(),
        (total, receivable) => receivable.status.isOutstanding
            ? total + receivable.pendingAmount
            : total,
      );

  Iterable<Receivable> get outstanding =>
      where((receivable) => receivable.status.isOutstanding);

  /// Alguma pendência passou do prazo — o caso que mais importa no balcão.
  bool get hasOverdue =>
      any((receivable) => receivable.status == ReceivableStatus.vencida);
}
