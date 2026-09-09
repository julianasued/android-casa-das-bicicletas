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

/// Uma linha do carrinho.
class SaleDraftLine {
  const SaleDraftLine({required this.product, required this.quantity});

  final Product product;
  final Quantity quantity;

  /// Bruto da linha: quantidade × preço de catálogo.
  ///
  /// O preço não é editável de propósito. O backend confere `unit_price`
  /// contra o catálogo e recusa divergência: a negociação tem um canal só, que
  /// é o desconto percentual da venda (13.3).
  Money get grossAmount => quantity.multiply(product.price);

  SaleDraftLine withQuantity(Quantity value) =>
      SaleDraftLine(product: product, quantity: value);
}

/// O que impede a venda de ser finalizada, em texto de balcão.
class SaleDraftProblem {
  const SaleDraftProblem(this.message);

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
  void add(Product product, {Quantity quantity = const Quantity.units(1)}) {
    final index = _lines.indexWhere((line) => line.product.id == product.id);
    if (index >= 0) {
      _lines[index] = _lines[index].withQuantity(_lines[index].quantity + quantity);
      return;
    }
    _lines.add(SaleDraftLine(product: product, quantity: quantity));
  }

  /// Define a quantidade da linha; quantidade zero ou negativa remove a linha.
  void setQuantity(int productId, Quantity quantity) {
    final index = _lines.indexWhere((line) => line.product.id == productId);
    if (index < 0) return;
    if (!quantity.isPositive) {
      _lines.removeAt(index);
      return;
    }
    _lines[index] = _lines[index].withQuantity(quantity);
  }

  void remove(int productId) =>
      _lines.removeWhere((line) => line.product.id == productId);

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

  bool get canBeFinished => problems.isEmpty;
}
