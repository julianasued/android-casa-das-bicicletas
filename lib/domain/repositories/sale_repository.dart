import '../../core/result.dart';
import '../entities/printed_document.dart';
import '../entities/sale.dart';
import '../rules/sale_draft.dart';

/// Vendas (API §3.4).
abstract interface class SaleRepository {
  /// RF06–RF08 — cria a venda e devolve, junto, o documento 1 a imprimir.
  Future<Result<SaleWithDocument>> create(SaleDraft draft);

  /// O corpo que o `POST /sales/` recebe, para a venda que vai esperar na fila.
  ///
  /// Exposto porque a operação enfileirada precisa guardar exatamente o que
  /// seria enviado — e duas versões da mesma serialização divergiriam na
  /// primeira mudança de contrato, com a diferença aparecendo só dias depois,
  /// na sincronização.
  Map<String, Object?> payloadFor(SaleDraft draft);

  /// RF09 — localiza a venda pelo código lido no leitor.
  Future<Result<Sale>> findByBarcode(String barcode);

  Future<Result<Sale>> findById(int saleId);

  /// Reimpressão auditável (§3.4.3): cada via sai numerada.
  Future<Result<PrintedDocument>> reprintDocument(int saleId, DocumentType type);
}
