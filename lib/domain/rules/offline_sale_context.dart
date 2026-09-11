/// O que o caso de uso precisa saber para vender sem rede (§13.9).
///
/// Junta as três coisas que a venda offline exige e que não estão no
/// `SaleDraft`: quem é este terminal, quem é o vendedor logado, e como montar o
/// corpo que o servidor espera.
///
/// Existe para manter o `CreateSale` sem dependência de sessão nem de banco: ele
/// recebe isto pronto e continua testável com objetos simples.
library;

import '../entities/pending_operation.dart';
import '../entities/printed_document.dart';
import '../entities/sale.dart';
import '../entities/seller.dart';
import '../entities/terminal_identity.dart';
import 'sale_draft.dart';

class OfflineSaleContext {
  const OfflineSaleContext({
    required this.identity,
    required this.seller,
    required this.storeCode,
    required this.storeId,
    required this.payload,
  });

  final TerminalIdentity identity;
  final Seller seller;
  final String storeCode;
  final int storeId;

  /// O corpo do `POST /sales/`, montado por quem já sabe montá-lo.
  ///
  /// Vem de fora para não duplicar a regra: o repositório já monta esse corpo
  /// para o caminho online, e duas versões da mesma serialização divergiriam na
  /// primeira mudança de contrato — com a diferença aparecendo só na
  /// sincronização, dias depois da venda.
  final Map<String, Object?> Function(SaleDraft draft) payload;

  /// A venda como ela vai existir no servidor.
  ///
  /// `id` zero porque é o autoincremento de lá. O status é `AGUARDANDO_CAIXA`,
  /// que é o que ela será: `PENDENTE_SINCRONIZACAO` é estado da operação na
  /// fila, não da venda — confundir os dois faria a tela dizer ao cliente que a
  /// venda dele está num limbo, quando ela está feita e só falta subir.
  Sale localSale(SaleDraft draft, PrintedDocument document) {
    final totals = draft.totals;

    return Sale(
      id: 0,
      uuid: draft.uuid,
      storeId: storeId,
      sellerId: seller.id,
      sellerName: seller.name,
      status: SaleStatus.aguardandoCaixa,
      paymentMethod: draft.paymentMethod,
      barcode: document.saleBarcode,
      grossAmount: totals.gross,
      discountAmount: totals.discount,
      totalAmount: totals.total,
      items: document.items,
      occurredAt: document.saleOccurredAt,
      customerName: draft.customer?.name,
      createdOffline: true,
    );
  }

  /// A operação como ela entra na fila.
  PendingOperation operationFor(SaleDraft draft, DateTime occurredAt) =>
      PendingOperation(
        operationId: draft.uuid,
        type: OperationType.saleCreate,
        payload: payload(draft),
        occurredAt: occurredAt,
        status: SyncStatus.pendente,
      );
}
