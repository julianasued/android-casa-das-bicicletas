/// Tradução do JSON da API para as entidades do domínio.
///
/// Fica na camada de dados porque é ela que conhece o formato do servidor: o
/// domínio não sabe que existe JSON, e por isso continua igual se amanhã o
/// contrato mudar de nome de campo.
///
/// A leitura é tolerante com o que é acessório e rígida com o que não é. Um
/// `customer_name` ausente vira `null`; um `total_amount` ausente é erro, e é
/// melhor falhar ao mapear do que imprimir um documento com valor zerado.
library;

import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../domain/entities/barcode_read.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/seller.dart';
import '../../domain/entities/store.dart';
import '../../domain/entities/terminal_session.dart';

// ---------------------------------------------------------------------------
// Leitores primitivos
// ---------------------------------------------------------------------------

int readInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Campo inteiro ausente ou inválido: $field');
}

int? readIntOrNull(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

String readString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return value;
  if (value != null) return value.toString();
  throw FormatException('Campo de texto ausente: $field');
}

String? readStringOrNull(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

Money readMoney(Map<String, Object?> json, String field) =>
    Money.parse(readString(json, field));

Money readMoneyOrZero(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return const Money.zero();
  return Money.tryParse(value);
}

DateTime readDateTime(Map<String, Object?> json, String field) =>
    DateTime.parse(readString(json, field)).toLocal();

DateTime? readDateTimeOrNull(Map<String, Object?> json, String field) {
  final raw = readStringOrNull(json, field);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

List<Map<String, Object?>> readList(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return [
    for (final item in value)
      if (item is Map<String, Object?>) item,
  ];
}

/// Itens de uma listagem paginada (§1.3) ou de uma lista simples.
List<Map<String, Object?>> readResults(Map<String, Object?> json) =>
    readList(json['results'] ?? json);

// ---------------------------------------------------------------------------
// Entidades
// ---------------------------------------------------------------------------

Store storeFromJson(Map<String, Object?> json) => Store(
      id: readInt(json, 'id'),
      code: readString(json, 'code'),
      name: readString(json, 'name'),
      document: readStringOrNull(json, 'document') ?? '',
      address: readStringOrNull(json, 'address') ?? '',
    );

Seller sellerFromJson(Map<String, Object?> json) => Seller(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
    );

/// §2.1 — `expires_in` vem em segundos; guardamos o instante do vencimento.
TerminalAuth terminalAuthFromJson(Map<String, Object?> json) => TerminalAuth(
      terminalToken: readString(json, 'terminal_token'),
      terminalId: readInt(json, 'terminal_id'),
      storeId: readInt(json, 'store_id'),
      expiresAt: DateTime.now().add(
        Duration(seconds: readIntOrNull(json, 'expires_in') ?? 0),
      ),
    );

/// §2.3 — a resposta traz `seller_id`, não o nome; ele vem da tela de seleção.
SellerSession sellerSessionFromJson(
  Map<String, Object?> json, {
  required Seller seller,
}) =>
    SellerSession(
      sessionToken: readString(json, 'session_token'),
      seller: seller,
      storeId: readInt(json, 'store_id'),
      terminalId: readInt(json, 'terminal_id'),
      expiresAt: DateTime.now().add(
        Duration(seconds: readIntOrNull(json, 'expires_in') ?? 0),
      ),
    );

ProductCategory categoryFromJson(Map<String, Object?> json) => ProductCategory(
      id: readInt(json, 'id'),
      code: readString(json, 'code'),
      name: readString(json, 'name'),
      isActive: json['is_active'] as bool? ?? true,
    );

Product productFromJson(Map<String, Object?> json) => Product(
      id: readInt(json, 'id'),
      sku: readString(json, 'sku'),
      name: readString(json, 'name'),
      categoryCode: readStringOrNull(json, 'category') ?? '',
      categoryName: readStringOrNull(json, 'category_name') ?? '',
      price: readMoney(json, 'price'),
      barcode: readStringOrNull(json, 'barcode'),
      isActive: json['is_active'] as bool? ?? true,
    );

Customer customerFromJson(Map<String, Object?> json) => Customer(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
      document: readStringOrNull(json, 'document'),
      phone: readStringOrNull(json, 'phone'),
      address: readStringOrNull(json, 'address'),
      isActive: json['is_active'] as bool? ?? true,
    );

SaleItem saleItemFromJson(Map<String, Object?> json) => SaleItem(
      id: readInt(json, 'id'),
      productId: readIntOrNull(json, 'product_id') ?? 0,
      productSku: readStringOrNull(json, 'product_sku') ?? '',
      productName: readStringOrNull(json, 'product_name') ?? '',
      categoryCode: readStringOrNull(json, 'category') ?? '',
      quantity: Quantity.parse(readString(json, 'quantity')),
      unitPrice: readMoney(json, 'unit_price'),
      discount: readMoneyOrZero(json, 'discount'),
      lineTotal: readMoney(json, 'line_total'),
    );

Sale saleFromJson(Map<String, Object?> json) => Sale(
      id: readInt(json, 'id'),
      uuid: readStringOrNull(json, 'uuid') ?? '',
      storeId: readInt(json, 'store_id'),
      terminalId: readIntOrNull(json, 'terminal_id'),
      sellerId: readIntOrNull(json, 'seller_id') ?? 0,
      sellerName: readStringOrNull(json, 'seller_name') ?? '',
      customerId: readIntOrNull(json, 'customer_id'),
      customerName: readStringOrNull(json, 'customer_name'),
      status: SaleStatus.fromCode(readStringOrNull(json, 'status')),
      paymentMethod:
          PaymentMethod.tryFromCode(readStringOrNull(json, 'payment_method')) ??
              PaymentMethod.dinheiro,
      barcode: readStringOrNull(json, 'barcode') ?? '',
      grossAmount: readMoneyOrZero(json, 'gross_amount'),
      discountAmount: readMoneyOrZero(json, 'discount_amount'),
      totalAmount: readMoney(json, 'total_amount'),
      items: [for (final item in readList(json['items'])) saleItemFromJson(item)],
      occurredAt: readDateTimeOrNull(json, 'occurred_at') ??
          readDateTimeOrNull(json, 'created_at') ??
          DateTime.now(),
      createdOffline: json['created_offline'] as bool? ?? false,
    );

DocumentPayment documentPaymentFromJson(Map<String, Object?> json) =>
    DocumentPayment(
      paymentMethodLabel:
          PaymentMethod.tryFromCode(readStringOrNull(json, 'payment_method'))
                  ?.label ??
              readStringOrNull(json, 'payment_method') ??
              '',
      amount: readMoneyOrZero(json, 'amount'),
      occurredAt: readDateTimeOrNull(json, 'occurred_at') ?? DateTime.now(),
    );

/// Documento impresso (§3.4.1 e §3.5).
///
/// O tipo sai da própria referência (`DOC1-L1-7F3A9C2B`), que é como o backend
/// a monta em `identifiers.document_reference` — o serializer não devolve um
/// campo `doc_type` separado.
PrintedDocument printedDocumentFromJson(Map<String, Object?> json) {
  final reference = readString(json, 'reference');
  final type = reference.startsWith('DOC2') ? DocumentType.doc2 : DocumentType.doc1;

  return PrintedDocument(
    type: type,
    reference: reference,
    sequence: readIntOrNull(json, 'sequence') ?? 1,
    isReprint: json['is_reprint'] as bool? ?? (readIntOrNull(json, 'sequence') ?? 1) > 1,
    printedAt: readDateTimeOrNull(json, 'printed_at') ?? DateTime.now(),
    printedByName: readStringOrNull(json, 'printed_by_name') ?? '',
    storeCode: readStringOrNull(json, 'store_code') ?? '',
    storeName: readStringOrNull(json, 'store_name') ?? '',
    storeDocument: readStringOrNull(json, 'store_document') ?? '',
    storeAddress: readStringOrNull(json, 'store_address') ?? '',
    saleId: readIntOrNull(json, 'sale_id') ?? 0,
    saleBarcode: readStringOrNull(json, 'sale_barcode') ?? '',
    saleOccurredAt: readDateTimeOrNull(json, 'sale_occurred_at') ?? DateTime.now(),
    paymentMethodLabel:
        PaymentMethod.tryFromCode(readStringOrNull(json, 'payment_method'))?.label ??
            readStringOrNull(json, 'payment_method') ??
            '',
    sellerName: readStringOrNull(json, 'seller_name') ?? '',
    terminalName: readStringOrNull(json, 'terminal_name') ?? '',
    customerName: readStringOrNull(json, 'customer_name'),
    items: [for (final item in readList(json['items'])) saleItemFromJson(item)],
    grossAmount: readMoneyOrZero(json, 'gross_amount'),
    discountAmount: readMoneyOrZero(json, 'discount_amount'),
    totalAmount: readMoneyOrZero(json, 'total_amount'),
    notice: readStringOrNull(json, 'notice') ?? '',
    confirmedAt: readDateTimeOrNull(json, 'confirmed_at'),
    cashierName: readStringOrNull(json, 'cashier_name'),
    payments: [
      for (final payment in readList(json['payments']))
        documentPaymentFromJson(payment),
    ],
  );
}

/// Resposta de `POST /sales/`: a venda e, junto, o documento 1 (RF08).
SaleWithDocument saleWithDocumentFromJson(Map<String, Object?> json) {
  final rawDocument = json['document_1'];
  return SaleWithDocument(
    sale: saleFromJson(json),
    document: rawDocument is Map<String, Object?>
        ? printedDocumentFromJson(rawDocument)
        : null,
  );
}

/// Leitura vinda do canal nativo do leitor.
BarcodeRead barcodeReadFromChannel(Map<Object?, Object?> event) {
  final code = (event['code'] ?? '').toString().trim();
  final rawAt = event['read_at']?.toString();
  final rawSource = event['source']?.toString();

  return BarcodeRead(
    code: code,
    readAt: rawAt == null ? DateTime.now() : (DateTime.tryParse(rawAt) ?? DateTime.now()),
    symbology: event['symbology']?.toString(),
    source: rawSource == 'keyboard'
        ? BarcodeSource.keyboardWedge
        : BarcodeSource.integratedScanner,
  );
}
