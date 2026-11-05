/// Recebimento no próprio PDV quando não há internet.
///
/// Com rede, quem recebe é o caixa (RF10–RF12) e o vendedor só confere. Sem
/// rede o caixa não enxerga a venda — ela só existe na fila deste aparelho —,
/// e a loja parava. Aqui o vendedor recebe, o cliente sai com o comprovante de
/// retirada, e a confirmação sobe para o servidor junto com a venda.
///
/// **A ordem é a mesma da venda offline:** a fila primeiro, o papel depois. Um
/// comprovante de pagamento que não ficou registrado em lugar nenhum é o pior
/// desfecho possível.
///
/// **Na fila, a confirmação vem depois da venda.** O servidor acha a venda pelo
/// `uuid` (`_resolver_venda`), e a operação de pagamento leva um instante
/// posterior ao da venda: o lote sai em ordem de `occurred_at`, e o pagamento
/// chegando antes faria o servidor procurar uma venda que ainda não existe.
library;

import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/result.dart';
import '../../core/uuid.dart';
import '../entities/payment_method.dart';
import '../entities/pending_operation.dart';
import '../entities/printed_document.dart';
import '../entities/sale.dart';
import '../ports/document_printer.dart';
import '../repositories/sync_queue.dart';

/// O que saiu do recebimento: a venda como ficou e o que houve com o papel.
class OfflinePaymentReceived {
  const OfflinePaymentReceived({
    required this.sale,
    required this.document,
    required this.operationId,
    this.printFailure,
  });

  /// A venda já como o servidor vai registrá-la: paga, ou pendente de notinha.
  final Sale sale;

  /// O comprovante de retirada provisório (documento 2).
  final PrintedDocument document;

  final String operationId;
  final Failure? printFailure;

  bool get printed => printFailure == null;
}

/// Uma parte do pagamento: forma e valor.
class OfflinePaymentPart {
  const OfflinePaymentPart(this.method, this.amount);

  final PaymentMethod method;
  final Money amount;
}

/// No máximo duas formas por venda — a mesma regra do caixa (13.7).
const int maxPaymentParts = 2;

/// Confere os recebimentos com as regras que o servidor vai aplicar
/// (`cash_services.confirm`). Devolve a mensagem do problema, ou `null`.
///
/// Conferir aqui, e não só lá, é o que evita a venda "dar certo" no balcão e
/// ser recusada na sincronização, com o cliente já longe.
String? offlinePaymentProblem(Sale sale, List<OfflinePaymentPart> parts) {
  if (sale.paymentMethod == PaymentMethod.notinha) {
    return parts.isEmpty
        ? null
        : 'Venda em notinha não recebe pagamento: o valor fica na conta do cliente.';
  }
  if (parts.isEmpty) return 'Informe a forma de pagamento.';
  if (parts.length > maxPaymentParts) {
    return 'A venda aceita no máximo $maxPaymentParts formas de pagamento.';
  }
  if (parts.any((p) => p.method == PaymentMethod.notinha)) {
    return 'Notinha não entra na divisão do pagamento.';
  }
  if (parts.length == 2 && parts[0].method == parts[1].method) {
    return 'Escolha duas formas diferentes para dividir.';
  }
  if (parts.any((p) => !p.amount.isPositive)) {
    return 'Cada forma precisa de um valor maior que zero.';
  }
  final soma = parts.fold(const Money.fromCents(0), (t, p) => t + p.amount);
  if (soma.cents != sale.totalAmount.cents) {
    return 'A soma das formas tem de fechar com o total da venda.';
  }
  if (sale.hasDiscount && parts.any((p) => p.method == PaymentMethod.credito)) {
    return 'Venda com desconto não pode ser recebida no crédito.';
  }
  return null;
}

/// Texto do rodapé do comprovante emitido sem internet.
const String offlineReceiptNotice =
    'Comprovante de retirada. Pagamento recebido no PDV sem conexao: o numero '
    'definitivo do documento sai na reimpressao, depois da sincronizacao.';

class ReceiveOfflinePayment {
  const ReceiveOfflinePayment({
    required SyncQueue queue,
    required DocumentPrinter printer,
    DateTime Function()? clock,
    String Function()? newId,
  })  : _queue = queue,
        _printer = printer,
        _clock = clock ?? DateTime.now,
        _newId = newId ?? generateUuidV4;

  final SyncQueue _queue;
  final DocumentPrinter _printer;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Registra o recebimento de [sale], cujo documento 1 provisório é
  /// [document1], e imprime o comprovante.
  ///
  /// [payments] são as formas e valores recebidos — uma ou duas, podendo ser
  /// outra forma que não a escolhida na montagem da venda. Vazio na notinha;
  /// omitido, vale a forma da venda pelo total.
  ///
  /// [receiverName] é quem recebeu — o vendedor da sessão — e vai impresso no
  /// lugar do nome do caixa.
  Future<Result<OfflinePaymentReceived>> call({
    required Sale sale,
    required PrintedDocument document1,
    required String receiverName,
    List<OfflinePaymentPart>? payments,
  }) async {
    if (sale.status != SaleStatus.aguardandoCaixa || !sale.createdOffline) {
      return const Err(
        BusinessRuleFailure('Só a venda feita sem internet é recebida no PDV.'),
      );
    }

    final notinha = sale.paymentMethod == PaymentMethod.notinha;
    final partes = payments ??
        [if (!notinha) OfflinePaymentPart(sale.paymentMethod, sale.totalAmount)];
    final problema = offlinePaymentProblem(sale, partes);
    if (problema != null) return Err(BusinessRuleFailure(problema));
    final agora = _clock();
    // Depois da venda, sempre — ver o cabeçalho.
    final minimo = sale.occurredAt.add(const Duration(milliseconds: 1));
    final quando = agora.isAfter(minimo) ? agora : minimo;

    final operationId = _newId();
    await _queue.enqueue(
      PendingOperation(
        operationId: operationId,
        type: OperationType.cashPayment,
        payload: {
          'sale_uuid': sale.uuid,
          // Notinha não é recebida (RF14): o servidor confirma a entrega e cria
          // a pendência do cliente.
          'payments': [
            for (final parte in partes)
              {
                'payment_method': parte.method.code,
                'amount': parte.amount.toApiString(),
              },
          ],
        },
        occurredAt: quando,
        status: SyncStatus.pendente,
      ),
    );

    final confirmada = _confirmada(sale, partes, notinha: notinha);
    final comprovante = PrintedDocument(
      type: DocumentType.doc2,
      reference: document1.reference,
      sequence: 1,
      isReprint: false,
      printedAt: quando,
      printedByName: receiverName,
      storeCode: document1.storeCode,
      storeName: document1.storeName,
      storeDocument: document1.storeDocument,
      storeAddress: document1.storeAddress,
      saleId: document1.saleId,
      saleBarcode: document1.saleBarcode,
      saleOccurredAt: document1.saleOccurredAt,
      paymentMethodLabel: notinha
          ? document1.paymentMethodLabel
          : partes.map((p) => p.method.label).join(' + '),
      sellerName: document1.sellerName,
      terminalName: document1.terminalName,
      customerName: document1.customerName,
      items: document1.items,
      grossAmount: document1.grossAmount,
      discountAmount: document1.discountAmount,
      totalAmount: document1.totalAmount,
      notice: offlineReceiptNotice,
      confirmedAt: quando,
      cashierName: receiverName,
      payments: [
        for (final parte in partes)
          DocumentPayment(
            paymentMethodLabel: parte.method.label,
            amount: parte.amount,
            occurredAt: quando,
          ),
      ],
    );

    final impresso = await _printer.printDocument(comprovante);

    return Ok(
      OfflinePaymentReceived(
        sale: confirmada,
        document: comprovante,
        operationId: operationId,
        printFailure: impresso.failureOrNull,
      ),
    );
  }

  /// A venda no estado em que o servidor vai deixá-la (`cash_services.confirm`):
  /// a forma da venda passa a ser a de maior valor, como lá.
  Sale _confirmada(
    Sale sale,
    List<OfflinePaymentPart> partes, {
    required bool notinha,
  }) =>
      Sale(
        id: sale.id,
        uuid: sale.uuid,
        storeId: sale.storeId,
        sellerId: sale.sellerId,
        sellerName: sale.sellerName,
        status: notinha ? SaleStatus.pendenteNotinha : SaleStatus.paga,
        paymentMethod: notinha ? sale.paymentMethod : _maior(partes).method,
        barcode: sale.barcode,
        grossAmount: sale.grossAmount,
        discountAmount: sale.discountAmount,
        totalAmount: sale.totalAmount,
        items: sale.items,
        occurredAt: sale.occurredAt,
        terminalId: sale.terminalId,
        customerId: sale.customerId,
        customerName: sale.customerName,
        createdOffline: true,
      );

  /// A de maior valor; no empate, a primeira — o `max` do Python faz igual.
  static OfflinePaymentPart _maior(List<OfflinePaymentPart> partes) =>
      partes.reduce((a, b) => b.amount.cents > a.amount.cents ? b : a);
}
