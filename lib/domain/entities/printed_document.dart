import '../../core/money.dart';
import 'sale.dart';

/// Tipo do documento impresso (`PrintedDocument.DocType` no backend).
enum DocumentType {
  doc1('DOC1', 'Encaminhamento ao caixa'),
  doc2('DOC2', 'Retirada da compra');

  const DocumentType(this.code, this.label);

  final String code;
  final String label;

  static DocumentType fromCode(String code) =>
      code == 'DOC2' ? DocumentType.doc2 : DocumentType.doc1;
}

/// Um recebimento registrado pelo caixa, como sai no documento 2.
class DocumentPayment {
  const DocumentPayment({
    required this.paymentMethodLabel,
    required this.amount,
    required this.occurredAt,
  });

  final String paymentMethodLabel;
  final Money amount;
  final DateTime occurredAt;
}

/// Documento impresso, no formato que a API entrega pronto (§3.4.1).
///
/// O servidor manda a estrutura plana justamente para o M10 (comentário do
/// `Document1Serializer`): quem imprime monta linhas de texto, não navega
/// objetos aninhados. O aplicativo não recalcula nada aqui — imprime o que foi
/// registrado, que é o que a auditoria vai cobrar depois.
class PrintedDocument {
  const PrintedDocument({
    required this.type,
    required this.reference,
    required this.sequence,
    required this.isReprint,
    required this.printedAt,
    required this.printedByName,
    required this.storeCode,
    required this.storeName,
    required this.storeDocument,
    required this.storeAddress,
    required this.saleId,
    required this.saleBarcode,
    required this.saleOccurredAt,
    required this.paymentMethodLabel,
    required this.sellerName,
    required this.terminalName,
    required this.items,
    required this.grossAmount,
    required this.discountAmount,
    required this.totalAmount,
    required this.notice,
    this.customerName,
    this.confirmedAt,
    this.cashierName,
    this.payments = const <DocumentPayment>[],
  });

  final DocumentType type;

  /// `DOC1-L1-7F3A9C2B` — a referência exigida na devolução (13.4).
  final String reference;

  /// Via: 1 é a original, 2 em diante são reimpressões.
  final int sequence;
  final bool isReprint;

  final DateTime printedAt;
  final String printedByName;

  final String storeCode;
  final String storeName;
  final String storeDocument;
  final String storeAddress;

  final int saleId;
  final String saleBarcode;
  final DateTime saleOccurredAt;
  final String paymentMethodLabel;
  final String sellerName;
  final String terminalName;
  final String? customerName;

  final List<SaleItem> items;
  final Money grossAmount;
  final Money discountAmount;
  final Money totalAmount;

  /// Aviso legal do papel — vem do servidor para não divergir entre versões.
  final String notice;

  // Só no documento 2 (RF12).
  final DateTime? confirmedAt;
  final String? cashierName;
  final List<DocumentPayment> payments;

  bool get hasDiscount => discountAmount.isPositive;
}

/// O que a criação da venda devolve: a venda e o documento a imprimir (RF08).
class SaleWithDocument {
  const SaleWithDocument({required this.sale, required this.document});

  final Sale sale;

  /// `null` quando o servidor não devolveu o documento — a venda existe e a
  /// reimpressão continua disponível, então isso não invalida a operação.
  final PrintedDocument? document;
}
