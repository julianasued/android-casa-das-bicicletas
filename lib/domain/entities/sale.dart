import '../../core/money.dart';
import '../../core/quantity.dart';
import 'payment_method.dart';

/// Estados da venda (API §6 e o modelo de estados da venda).
enum SaleStatus {
  aguardandoCaixa('AGUARDANDO_CAIXA', 'Aguardando caixa'),
  paga('PAGA', 'Paga'),
  pendenteNotinha('PENDENTE_NOTINHA', 'Pendente de notinha'),
  quitada('QUITADA', 'Notinha quitada'),
  emAlteracao('EM_ALTERACAO', 'Em alteração'),
  cancelada('CANCELADA', 'Cancelada'),
  devolvidaParcial('DEVOLVIDA_PARCIAL', 'Devolvida parcialmente'),
  devolvidaTotal('DEVOLVIDA_TOTAL', 'Devolvida'),
  desconhecido('', 'Desconhecido');

  const SaleStatus(this.code, this.label);

  final String code;
  final String label;

  /// A venda ainda pode ser recebida no caixa.
  bool get awaitsCashier => this == SaleStatus.aguardandoCaixa;

  /// Estado em que o documento 2 já existe (RF12).
  bool get isConfirmed =>
      this == SaleStatus.paga ||
      this == SaleStatus.pendenteNotinha ||
      this == SaleStatus.quitada;

  /// Códigos desconhecidos não derrubam a tela: um estado novo no servidor
  /// aparece como "Desconhecido" em vez de quebrar o aplicativo em campo.
  static SaleStatus fromCode(String? code) {
    for (final status in SaleStatus.values) {
      if (status.code == code) return status;
    }
    return SaleStatus.desconhecido;
  }
}

/// Item da venda, como o servidor o registrou.
///
/// Não há `commissionPercent` nem `commissionAmount`: para o perfil que opera o
/// M10 esses campos **não existem no JSON** (§5 da API, RF18). Declará-los aqui
/// como opcionais convidaria alguém a exibi-los um dia.
class SaleItem {
  const SaleItem({
    required this.id,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.categoryCode,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.lineTotal,
  });

  final int id;
  final int productId;
  final String productSku;
  final String productName;
  final String categoryCode;
  final Quantity quantity;
  final Money unitPrice;

  /// Parte desta linha no desconto rateado da venda (13.3).
  final Money discount;

  final Money lineTotal;
}

/// Venda apurada (API §3.4.1).
class Sale {
  const Sale({
    required this.id,
    required this.uuid,
    required this.storeId,
    required this.sellerId,
    required this.sellerName,
    required this.status,
    required this.paymentMethod,
    required this.barcode,
    required this.grossAmount,
    required this.discountAmount,
    required this.totalAmount,
    required this.items,
    required this.occurredAt,
    this.terminalId,
    this.customerId,
    this.customerName,
    this.createdOffline = false,
  });

  final int id;
  final String uuid;
  final int storeId;
  final int? terminalId;
  final int sellerId;
  final String sellerName;
  final int? customerId;
  final String? customerName;
  final SaleStatus status;
  final PaymentMethod paymentMethod;

  /// Identificador impresso e lido pelo caixa (RF07/RF09).
  final String barcode;

  final Money grossAmount;
  final Money discountAmount;
  final Money totalAmount;
  final List<SaleItem> items;

  /// Hora do balcão, não a do servidor — importa quando a venda nasce offline.
  final DateTime occurredAt;

  final bool createdOffline;

  bool get hasDiscount => discountAmount.isPositive;
}
