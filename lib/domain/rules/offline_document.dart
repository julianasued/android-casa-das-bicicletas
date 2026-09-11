/// O documento 1 montado no próprio terminal, quando não há rede (§13.9).
///
/// Normalmente quem monta é o servidor: a resposta do `POST /sales/` já vem com
/// o documento pronto, plano, no formato que a impressora quer. Sem rede não há
/// resposta — e o §13.9 põe impressão entre as operações que devem funcionar
/// offline, porque o cliente está no balcão esperando o papel para levar ao
/// caixa.
///
/// **O que o terminal não pode inventar.** Três campos são do servidor por
/// definição: o `id` da venda (autoincremento do banco dele), a `reference`
/// (`DOC1-L1-...`, exigida na devolução — 13.4) e a `sequence` da via. Este
/// documento sai dizendo isso em vez de fingir um número: gerar uma referência
/// local que depois divergisse deixaria o papel na mão do cliente apontando
/// para um documento que não existe, e a devolução usa justamente esse número.
///
/// **O que ele pode.** O código de barras — que é o que o caixa lê para achar a
/// venda (RF09) — é calculado do `uuid` gerado no terminal, pela mesma regra do
/// backend. Esse, sim, vai a valer.
library;

import '../entities/terminal_identity.dart';
import '../entities/printed_document.dart';
import '../entities/sale.dart';
import '../entities/seller.dart';
import 'sale_draft.dart';

/// Texto que ocupa o lugar da referência até a venda chegar ao servidor.
///
/// Fica visível no papel de propósito: quem receber precisa saber que o número
/// definitivo ainda não existe, e uma reimpressão depois da sincronização traz
/// o documento completo (§3.4.3).
const String pendingReferenceLabel = 'AGUARDANDO SINCRONIZACAO';

/// Monta o documento 1 a partir do que o terminal sabe.
///
/// Devolve `null` quando falta o mínimo para um cupom se identificar — hoje, o
/// nome da loja. Um papel sem isso não diz de quem é a venda, e imprimir seria
/// pior que não imprimir.
PrintedDocument? offlineDocument1({
  required SaleDraft draft,
  required TerminalIdentity identity,
  required Seller seller,
  required String storeCode,
  DateTime? occurredAt,
}) {
  if (!identity.canPrintOffline) return null;

  final quando = occurredAt ?? DateTime.now();
  final totals = draft.totals;

  return PrintedDocument(
    type: DocumentType.doc1,

    // Os três campos do servidor. `saleId` fica em zero e a `sequence` em 1:
    // o layout mostra o que recebe, e é a referência que avisa o operador.
    reference: pendingReferenceLabel,
    saleId: 0,
    sequence: 1,
    isReprint: false,

    printedAt: quando,
    printedByName: seller.name,

    storeCode: identity.storeCode ?? storeCode,
    storeName: identity.storeName ?? '',
    storeDocument: identity.storeDocument ?? '',
    storeAddress: identity.storeAddress ?? '',

    // Este vale: mesma regra do backend, a partir do uuid do terminal.
    saleBarcode: draft.barcodeFor(identity.storeCode ?? storeCode),
    saleOccurredAt: quando,

    paymentMethodLabel: draft.paymentMethod.label,
    sellerName: seller.name,
    terminalName: identity.terminalName ?? '',
    customerName: draft.customer?.name,

    // `id` fica em zero: é do servidor, como o da venda. O desconto de cada
    // linha sai da diferença entre o bruto e o total rateado, e não de uma
    // conta nova — o rateio de 13.3 tem regra de arredondamento própria, e
    // recalcular aqui abriria espaço para o papel divergir em um centavo.
    items: [
      for (final (indice, line) in draft.lines.indexed)
        SaleItem(
          id: 0,
          productId: line.product.id,
          productSku: line.product.sku,
          productName: line.product.name,
          categoryCode: line.product.categoryCode,
          quantity: line.quantity,
          unitPrice: line.product.price,
          discount: line.grossAmount - totals.lineTotals[indice],
          lineTotal: totals.lineTotals[indice],
        ),
    ],

    grossAmount: totals.gross,
    discountAmount: totals.discount,
    totalAmount: totals.total,

    notice: _offlineNotice,
  );
}

/// O aviso do RF08 mais a condição desta via.
///
/// O primeiro documento nunca foi comprovante de pagamento; agora ele também
/// não tem número definitivo, e as duas coisas precisam estar no papel.
const String _offlineNotice =
    'Documento de encaminhamento ao caixa. Nao e comprovante de pagamento '
    '(RF08). Emitido sem conexao: o numero do documento sai na reimpressao, '
    'depois da sincronizacao.';
