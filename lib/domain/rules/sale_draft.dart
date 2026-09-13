/// Venda em montagem no terminal, antes de virar venda no servidor.
///
/// É um objeto de domínio, e não estado de tela, porque as regras que ele
/// carrega são regras de negócio: notinha exige cliente (RF14), desconto tem
/// teto (13.3), venda sem item não existe. A tela apenas as exibe — e a Sprint
/// 9 vai gravar exatamente este objeto no SQLite quando não houver rede.
///
/// O `uuid` nasce aqui, no dispositivo (RF36): é ele que forma o código de
/// barras impresso e é ele que impede a venda de duplicar num reenvio.
library;

import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../core/uuid.dart';
import '../entities/customer.dart';
import '../entities/payment_method.dart';
import '../entities/product.dart';
import 'sale_pricing.dart';

/// Uma linha do carrinho, de uma das duas formas.
///
/// **Manual (V1)** — categoria e valor digitados: "PNEUS, R$ 350,00". É como a
/// loja vende, e não depende de haver produto cadastrado.
///
/// **Catálogo (futuro)** — produto cadastrado, com o preço vindo dele. A
/// capacidade continua inteira; deixou de ser o caminho obrigatório.
///
/// O `id` é local do rascunho, não do servidor: duas linhas manuais da mesma
/// categoria com valores diferentes são linhas diferentes, e identificá-las
/// pelo produto — que nem existe — não funcionaria.
class SaleDraftLine {
  const SaleDraftLine.manual({
    required this.id,
    required ProductCategory this.category,
    required Money price,
    required this.quantity,
  })  : product = null,
        _manualPrice = price;

  const SaleDraftLine.fromCatalog({
    required this.id,
    required Product this.product,
    required this.quantity,
  })  : category = null,
        _manualPrice = null;

  final int id;
  final Product? product;
  final ProductCategory? category;
  final Money? _manualPrice;
  final Quantity quantity;

  bool get isManual => product == null;

  /// O que aparece na linha e no documento impresso.
  String get label => product?.name ?? category!.name;

  String get categoryCode => product?.categoryCode ?? category!.code;

  /// Na linha de catálogo o preço é o cadastrado — o backend confere e recusa
  /// divergência, que é o que impede o desconto de 13.3 de virar decoração. Na
  /// linha manual não há com o que comparar: o valor digitado é o negociado.
  Money get unitPrice => product?.price ?? _manualPrice!;

  Money get grossAmount => quantity.multiply(unitPrice);

  SaleDraftLine withQuantity(Quantity value) => product != null
      ? SaleDraftLine.fromCatalog(id: id, product: product!, quantity: value)
      : SaleDraftLine.manual(
          id: id,
          category: category!,
          price: _manualPrice!,
          quantity: value,
        );
}

/// O que impede a venda de ser finalizada, em texto de balcão.
class SaleDraftProblem {
  const SaleDraftProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// O que não impede de registrar a venda, mas trava depois, no caixa.
///
/// Existe separado de `SaleDraftProblem` porque a diferença é de autoridade: o
/// problema é recusa deste aplicativo, o aviso é previsão do que o servidor
/// fará. Tratar os dois igual bloquearia aqui uma venda que o backend aceita.
class SaleDraftWarning {
  const SaleDraftWarning(this.message);

  final String message;

  @override
  String toString() => message;
}

class SaleDraft {
  SaleDraft({String? uuid, this.paymentMethod = PaymentMethod.dinheiro})
      : uuid = uuid ?? generateUuidV4(),
        _lines = <SaleDraftLine>[];

  /// Identificador da venda gerado no terminal (RF36).
  final String uuid;

  final List<SaleDraftLine> _lines;

  /// Identidade local das linhas — o servidor não a conhece.
  int _nextLineId = 1;

  PaymentMethod paymentMethod;
  Customer? customer;
  int discountPercentHundredths = 0;

  List<SaleDraftLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get lineCount => _lines.length;

  /// Código de barras que o servidor vai gerar para esta venda.
  ///
  /// Calculado localmente a partir do `uuid` e do código da loja — o mesmo
  /// resultado do `sale_barcode` do backend.
  String barcodeFor(String storeCode) =>
      saleBarcodeFor(storeCode: storeCode, saleUuid: uuid);

  /// Adiciona o produto; repetir o mesmo produto soma na linha existente.
  /// Lança uma linha manual: categoria e valor (V1).
  ///
  /// Não agrupa com linha igual de propósito: "PEÇAS R$ 120" e "PEÇAS R$ 80"
  /// são duas vendas distintas dentro da mesma venda, e somá-las esconderia do
  /// vendedor o que ele acabou de lançar.
  SaleDraftLine addManual({
    required ProductCategory category,
    required Money price,
    Quantity quantity = const Quantity.units(1),
  }) {
    final line = SaleDraftLine.manual(
      id: _nextLineId++,
      category: category,
      price: price,
      quantity: quantity,
    );
    _lines.add(line);
    return line;
  }

  /// Lança a partir do catálogo — capacidade guardada, sem uso na V1.
  void add(Product product, {Quantity quantity = const Quantity.units(1)}) {
    final index = _lines.indexWhere((line) => line.product?.id == product.id);
    if (index >= 0) {
      _lines[index] = _lines[index].withQuantity(_lines[index].quantity + quantity);
      return;
    }
    _lines.add(
      SaleDraftLine.fromCatalog(
        id: _nextLineId++,
        product: product,
        quantity: quantity,
      ),
    );
  }

  /// Define a quantidade da linha; quantidade zero ou negativa remove a linha.
  void setQuantity(int lineId, Quantity quantity) {
    final index = _lines.indexWhere((line) => line.id == lineId);
    if (index < 0) return;
    if (!quantity.isPositive) {
      _lines.removeAt(index);
      return;
    }
    _lines[index] = _lines[index].withQuantity(quantity);
  }

  void remove(int lineId) => _lines.removeWhere((line) => line.id == lineId);

  void clear() {
    _lines.clear();
    discountPercentHundredths = 0;
    customer = null;
  }

  SaleTotals get totals => computeTotals(
        lineGrosses: [for (final line in _lines) line.grossAmount],
        discountPercentHundredths: discountPercentHundredths,
      );

  /// Tudo o que impede o envio, de uma vez — a tela lista, não descobre um a um.
  List<SaleDraftProblem> get problems {
    final found = <SaleDraftProblem>[];

    if (_lines.isEmpty) {
      found.add(const SaleDraftProblem('Adicione ao menos um produto à venda.'));
    }
    if (discountPercentHundredths > maxDiscountPercentHundredths) {
      found.add(const SaleDraftProblem('O desconto máximo é de 5% (13.3).'));
    }
    if (discountPercentHundredths < 0) {
      found.add(const SaleDraftProblem('Desconto não pode ser negativo.'));
    }
    if (paymentMethod.requiresCustomer && customer == null) {
      found.add(
        const SaleDraftProblem('Venda em notinha exige um cliente cadastrado (RF14).'),
      );
    }
    return found;
  }

  /// Avisos do que o caixa vai recusar, ainda em tempo de corrigir.
  ///
  /// A regra é do backend e continua sendo dele: `POST /sales/` **aceita**
  /// crédito com desconto, e quem recusa é `POST /cash/payments/`, com
  /// `DISCOUNT_WITH_CREDIT` (13.3). Sem este aviso o desfecho é o pior
  /// possível: o vendedor imprime o documento 1, o cliente atravessa a loja, e
  /// só no caixa se descobre que a venda precisa de alteração aprovada por um
  /// gerente — com o cliente esperando em pé.
  ///
  /// É aviso, não trava: a decisão continua no servidor, e a venda pode ser
  /// registrada assim se for o que o vendedor quer.
  List<SaleDraftWarning> get warnings {
    final found = <SaleDraftWarning>[];

    if (paymentMethod == PaymentMethod.credito && discountPercentHundredths > 0) {
      found.add(
        const SaleDraftWarning(
          'O caixa não recebe no crédito uma venda com desconto (13.3). '
          'Para receber no crédito será preciso solicitar alteração da venda.',
        ),
      );
    }
    return found;
  }

  bool get canBeFinished => problems.isEmpty;
}
