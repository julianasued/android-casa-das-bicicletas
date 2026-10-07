/// Reimpressão de um documento já emitido (§3.4.3).
///
/// A reimpressão passa pelo servidor de propósito: cada via é registrada e
/// numerada (`-R2`, `-R3`), e é isso que a torna auditável. Reimprimir do cache
/// local produziria duas vias iguais e indistinguíveis — exatamente o que a
/// devolução (13.4) não pode aceitar.
library;

import '../../core/result.dart';
import '../entities/printed_document.dart';
import '../ports/document_printer.dart';
import '../repositories/sale_repository.dart';

class ReprintDocument {
  const ReprintDocument({
    required SaleRepository sales,
    required DocumentPrinter printer,
  })  : _sales = sales,
        _printer = printer;

  final SaleRepository _sales;
  final DocumentPrinter _printer;

  Future<Result<PrintedDocument>> call(int saleId, DocumentType type) async {
    final registered = await _sales.reprintDocument(saleId, type);
    if (registered case Err(:final failure)) {
      return Err(failure);
    }

    final document = (registered as Ok<PrintedDocument>).value;
    final printed = await _printer.printDocument(document);

    return switch (printed) {
      Err(:final failure) => Err(failure),
      Ok() => Ok(document),
    };
  }
}
