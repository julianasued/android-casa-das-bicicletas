/// Vendas (API §3.4).
///
/// Duas decisões de protocolo moram aqui.
///
/// A primeira é o `uuid`: ele nasce no terminal (`SaleDraft`) e vai no corpo da
/// requisição. É ele que o backend usa para reconhecer o reenvio da mesma venda
/// e devolver a que já existe, em vez de criar a segunda (`_venda_ja_registrada`
/// na view de vendas).
///
/// A segunda é usar esse mesmo `uuid` como `X-Idempotency-Key` (§1.5). A chave
/// precisa ser **a mesma** em toda nova tentativa da mesma venda e **diferente**
/// entre vendas — que é exatamente o que o identificador da venda já é. Gerar
/// uma chave nova a cada tentativa daria ao servidor duas chaves para o mesmo
/// fato, e a proteção contra o toque duplo se perderia.
library;

import '../../core/result.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/entities/sale.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/rules/sale_draft.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';

class SaleRepositoryImpl implements SaleRepository {
  const SaleRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<SaleWithDocument>> create(SaleDraft draft) async {
    final response = await _api.post(
      ApiEndpoints.sales,
      body: _bodyFor(draft),
      idempotencyKey: draft.uuid,
    );

    return mapApiResponse(
      response,
      (result) => saleWithDocumentFromJson(result.data),
    );
  }

  Map<String, Object?> _bodyFor(SaleDraft draft) => {
        'uuid': draft.uuid,
        'payment_method': draft.paymentMethod.code,
        if (draft.customer != null) 'customer_id': draft.customer!.id,
        'discount_percent': _percent(draft.discountPercentHundredths),
        'created_offline': false,
        'items': [
          for (final line in draft.lines)
            {
              'product_id': line.product.id,
              'quantity': line.quantity.toApiString(),
              // Enviado para conferência: o backend recusa preço divergente do
              // catálogo, e é assim que o teto de desconto (13.3) não vira
              // decoração.
              'unit_price': line.product.price.toApiString(),
            },
        ],
      };

  String _percent(int hundredths) {
    final whole = hundredths ~/ 100;
    final fraction = (hundredths % 100).toString().padLeft(2, '0');
    return '$whole.$fraction';
  }

  @override
  Future<Result<Sale>> findByBarcode(String barcode) async {
    final response = await _api.get(ApiEndpoints.saleByBarcode(barcode));
    return mapApiResponse(response, (result) => saleFromJson(result.data));
  }

  @override
  Future<Result<Sale>> findById(int saleId) async {
    final response = await _api.get(ApiEndpoints.sale(saleId));
    return mapApiResponse(response, (result) => saleFromJson(result.data));
  }

  @override
  Future<Result<PrintedDocument>> reprintDocument(
    int saleId,
    DocumentType type,
  ) async {
    final path = type == DocumentType.doc2
        ? ApiEndpoints.printDocument2(saleId)
        : ApiEndpoints.printDocument1(saleId);

    // Sem chave de idempotência de propósito: cada pedido de reimpressão **deve**
    // gerar uma via nova e numerada (§3.4.3). Repetir a chave devolveria a via
    // anterior, e o registro de auditoria deixaria de contar quantas cópias
    // daquele papel existem no mundo.
    final response = await _api.post(path);
    return mapApiResponse(
      response,
      (result) => printedDocumentFromJson(result.data),
    );
  }
}
