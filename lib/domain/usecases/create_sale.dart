/// Finalização da venda no terminal (RF06–RF08), com ou sem rede (§13.9).
///
/// Um caso de uso, e não uma chamada direta ao repositório, porque a venda só
/// está pronta quando o papel sai. A ordem importa: registrar primeiro,
/// imprimir depois — o contrário produziria um documento com código de barras
/// de uma venda que o servidor recusou.
///
/// Falha de impressão **não** desfaz a venda. A venda existe, o cliente está no
/// balcão, e a saída é reimprimir (§3.4.3) — não cancelar o que foi vendido.
///
/// **Sem rede, a venda não para.** Ela vai para a fila (RF35) e o documento é
/// montado aqui no terminal, marcado como provisório. O cliente leva o papel
/// para o caixa, que consegue ler o código de barras — esse é calculado do
/// `uuid` local pela mesma regra do backend, e vale desde já.
///
/// **Só falha de rede vira fila.** Recusa do servidor — desconto acima do teto,
/// produto inativo, permissão — é resposta legítima e precisa chegar ao
/// vendedor, que pode corrigir. Enfileirar um `422` faria a venda "dar certo" no
/// balcão para ser recusada de novo a cada tentativa de sincronizar.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../entities/printed_document.dart';
import '../ports/document_printer.dart';
import '../repositories/sale_repository.dart';
import '../repositories/sync_queue.dart';
import '../rules/offline_document.dart';
import '../rules/offline_sale_context.dart';
import '../rules/sale_draft.dart';

/// Desfecho da finalização: o que foi registrado e o que aconteceu com o papel.
class SaleFinished {
  const SaleFinished({
    required this.result,
    this.printFailure,
    this.pendingOperationId,
    this.customerPhone,
    this.discountPercentHundredths = 0,
  });

  final SaleWithDocument result;

  /// Telefone do cliente, como estava no rascunho.
  ///
  /// A `Sale` do servidor traz só id e nome do cliente (§5 da API); o contato
  /// veio da busca que o vendedor fez, e a tela de desfecho o mostra para quem
  /// precisar ligar por causa da retirada.
  final String? customerPhone;

  /// Percentual negociado, em centésimos de ponto.
  ///
  /// O servidor devolve o desconto **em reais**, que é o que vale. Isto aqui é
  /// o critério — "5% sobre o subtotal" —, e serve só para a tela dizer de onde
  /// o valor saiu. Zero quando não houve desconto.
  final int discountPercentHundredths;

  /// `null` quando o documento 1 saiu; preenchido quando falta papel, a
  /// impressora está fora ou o SDK não respondeu (§11).
  final Failure? printFailure;

  /// Preenchido quando a venda foi para a fila em vez do servidor (RF35).
  ///
  /// A tela precisa disto para dizer ao vendedor que a venda está registrada no
  /// aparelho e ainda vai subir — o que é diferente de "pronto" e diferente de
  /// "falhou".
  final String? pendingOperationId;

  bool get printed => printFailure == null;

  bool get awaitsSync => pendingOperationId != null;
}

class CreateSale {
  const CreateSale({
    required SaleRepository sales,
    required DocumentPrinter printer,
    SyncQueue? queue,
    Future<OfflineSaleContext?> Function()? offlineContext,
  })  : _sales = sales,
        _printer = printer,
        _queue = queue,
        _offlineContext = offlineContext;

  final SaleRepository _sales;
  final DocumentPrinter _printer;

  /// Sem fila, o caso de uso se comporta como antes: falha de rede é falha.
  final SyncQueue? _queue;

  /// O que o terminal sabe para montar o documento sozinho.
  ///
  /// É função, e não valor, porque a identidade é aprendida ao longo do uso —
  /// ler na hora da venda pega o que foi aprendido depois de o grafo ser
  /// montado. E assíncrona porque ela vem do banco.
  final Future<OfflineSaleContext?> Function()? _offlineContext;

  Future<Result<SaleFinished>> call(SaleDraft draft) async {
    final problems = draft.problems;
    if (problems.isNotEmpty) {
      return Err(BusinessRuleFailure(problems.first.message));
    }

    final registered = await _sales.create(draft);

    if (registered case Err(failure: NetworkFailure())) {
      final offline = await _sellOffline(draft);
      if (offline != null) return offline;
    }

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
          customerPhone: draft.customer?.phone,
          discountPercentHundredths: draft.discountPercentHundredths,
        ),
      );
    }

    final printed = await _printer.printDocument(document);
    return Ok(
      SaleFinished(
        result: value,
        printFailure: printed.failureOrNull,
        customerPhone: draft.customer?.phone,
        discountPercentHundredths: draft.discountPercentHundredths,
      ),
    );
  }

  /// Guarda a venda na fila e imprime o documento provisório.
  ///
  /// Devolve `null` quando não dá para vender offline — sem fila configurada ou
  /// sem o mínimo para montar o cupom. Aí a falha de rede segue seu caminho, que
  /// é o comportamento honesto: melhor o vendedor saber que não deu do que
  /// receber um papel que não identifica a loja.
  Future<Result<SaleFinished>?> _sellOffline(SaleDraft draft) async {
    final fila = _queue;
    final contexto = await _offlineContext?.call();
    if (fila == null || contexto == null) return null;

    final document = offlineDocument1(
      draft: draft,
      identity: contexto.identity,
      seller: contexto.seller,
      storeCode: contexto.storeCode,
    );
    if (document == null) return null;

    // A fila primeiro, o papel depois: a mesma ordem do caminho online, e pela
    // mesma razão. Um documento impresso de uma venda que não ficou registrada
    // em lugar nenhum é o pior desfecho possível.
    await fila.enqueue(contexto.operationFor(draft, document.saleOccurredAt));

    final printed = await _printer.printDocument(document);

    return Ok(
      SaleFinished(
        result: SaleWithDocument(
          sale: contexto.localSale(draft, document),
          document: document,
        ),
        printFailure: printed.failureOrNull,
        pendingOperationId: draft.uuid,
        customerPhone: draft.customer?.phone,
        discountPercentHundredths: draft.discountPercentHundredths,
      ),
    );
  }
}
