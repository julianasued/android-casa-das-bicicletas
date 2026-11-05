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
  /// [receiverName] é quem recebeu — o vendedor da sessão — e vai impresso no
  /// lugar do nome do caixa.
  Future<Result<OfflinePaymentReceived>> call({
    required Sale sale,
    required PrintedDocument document1,
    required String receiverName,
  }) async {
    if (sale.status != SaleStatus.aguardandoCaixa || !sale.createdOffline) {
      return const Err(
        BusinessRuleFailure('Só a venda feita sem internet é recebida no PDV.'),
      );
    }

    final notinha = sale.paymentMethod == PaymentMethod.notinha;
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
            if (!notinha)
              {
                'payment_method': sale.paymentMethod.code,
                'amount': sale.totalAmount.toApiString(),
              },
          ],
        },
        occurredAt: quando,
        status: SyncStatus.pendente,
      ),
    );

    final confirmada = _confirmada(sale, notinha: notinha);
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
      paymentMethodLabel: document1.paymentMethodLabel,
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
        if (!notinha)
          DocumentPayment(
            paymentMethodLabel: sale.paymentMethod.label,
            amount: sale.totalAmount,
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

  /// A venda no estado em que o servidor vai deixá-la (`cash_services.confirm`).
  Sale _confirmada(Sale sale, {required bool notinha}) => Sale(
        id: sale.id,
        uuid: sale.uuid,
        storeId: sale.storeId,
        sellerId: sale.sellerId,
        sellerName: sale.sellerName,
        status: notinha ? SaleStatus.pendenteNotinha : SaleStatus.paga,
        paymentMethod: sale.paymentMethod,
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
}
