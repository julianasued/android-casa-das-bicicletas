/// Finalização da venda no terminal (RF06–RF08).
///
/// Um caso de uso, e não uma chamada direta ao repositório, porque a venda só
/// está pronta quando o papel sai. A ordem importa: registrar primeiro,
/// imprimir depois — o contrário produziria um documento com código de barras
/// de uma venda que o servidor recusou.
///
/// Falha de impressão **não** desfaz a venda. A venda existe, o cliente está no
/// balcão, e a saída é reimprimir (§3.4.3) — não cancelar o que foi vendido.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../entities/printed_document.dart';
import '../ports/document_printer.dart';
import '../repositories/sale_repository.dart';
import '../rules/sale_draft.dart';

/// Desfecho da finalização: o que foi registrado e o que aconteceu com o papel.
class SaleFinished {
  const SaleFinished({required this.result, this.printFailure});

  final SaleWithDocument result;

  /// `null` quando o documento 1 saiu; preenchido quando falta papel, a
  /// impressora está fora ou o SDK não respondeu (§11).
  final Failure? printFailure;

  bool get printed => printFailure == null;
}

class CreateSale {
  const CreateSale({
    required SaleRepository sales,
    required DocumentPrinter printer,
  })  : _sales = sales,
        _printer = printer;

  final SaleRepository _sales;
  final DocumentPrinter _printer;

  Future<Result<SaleFinished>> call(SaleDraft draft) async {
    final problems = draft.problems;
    if (problems.isNotEmpty) {
      return Err(BusinessRuleFailure(problems.first.message));
    }

    final registered = await _sales.create(draft);
    if (registered case Err(:final failure)) {
      return Err(failure);
    }

    final value = (registered as Ok<SaleWithDocument>).value;
    final document = value.document;
    if (document == null) {
      return Ok(
        SaleFinished(
          result: value,
          printFailure: const PrintFailure(
            'A venda foi registrada, mas o servidor não devolveu o documento. '
            'Use a reimpressão.',
          ),
        ),
      );
    }

    final printed = await _printer.printDocument(document);
    return Ok(SaleFinished(result: value, printFailure: printed.failureOrNull));
  }
}
