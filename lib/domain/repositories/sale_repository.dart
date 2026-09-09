import '../../core/result.dart';
import '../entities/printed_document.dart';
import '../entities/sale.dart';
import '../rules/sale_draft.dart';

/// Vendas (API §3.4).
abstract interface class SaleRepository {
  /// RF06–RF08 — cria a venda e devolve, junto, o documento 1 a imprimir.
  Future<Result<SaleWithDocument>> create(SaleDraft draft);

  /// RF09 — localiza a venda pelo código lido no leitor.
  Future<Result<Sale>> findByBarcode(String barcode);

  Future<Result<Sale>> findById(int saleId);

  /// Reimpressão auditável (§3.4.3): cada via sai numerada.
  Future<Result<PrintedDocument>> reprintDocument(int saleId, DocumentType type);
}
