/// Aritmética da venda, igual à do backend (`apps/sales/services.py`).
///
/// O terminal precisa mostrar o total **antes** de enviar a venda: o cliente
/// pergunta "quanto ficou?" no balcão, não depois da resposta do servidor. Como
/// o servidor recalcula tudo por conta própria (e é ele quem vale), o único
/// jeito de os dois números baterem é o cálculo ser o mesmo — mesmo
/// arredondamento, mesmo rateio, mesma sobra de centavo.
///
/// Isto vive no domínio, e não na tela, porque a Sprint 9 vai precisar dele
/// para gravar a venda no SQLite antes de existir rede.
library;

import '../../core/money.dart';

/// Teto de desconto negociável no balcão (13.3). O backend recusa acima disso.
const int maxDiscountPercentHundredths = 500; // 5,00%

/// Divide o desconto da venda entre as linhas, na proporção de cada uma.
///
/// A sobra de arredondamento vai para a maior linha — mesma regra do
/// `split_discount` do backend. Sem isso, `soma(line_total)` deixaria de bater
/// com `total_amount` por um centavo, e o documento impresso não fecharia com
/// o extrato do caixa.
List<Money> splitDiscount(List<Money> lineGrosses, Money discountAmount) {
  final gross = sumMoney(lineGrosses);
  if (!discountAmount.isPositive || !gross.isPositive) {
    return List<Money>.filled(lineGrosses.length, const Money.zero());
  }

  final shares = [
    for (final line in lineGrosses)
      discountAmount.proportion(part: line, whole: gross),
  ];

  final residual = discountAmount - sumMoney(shares);
  if (!residual.isZero) {
    var largest = 0;
    for (var i = 1; i < lineGrosses.length; i++) {
      if (lineGrosses[i].cents > lineGrosses[largest].cents) largest = i;
    }
    shares[largest] = shares[largest] + residual;
  }
  return shares;
}

/// Totais apurados de uma venda em montagem.
class SaleTotals {
  const SaleTotals({
    required this.gross,
    required this.discount,
    required this.total,
    required this.lineTotals,
  });

  final Money gross;
  final Money discount;
  final Money total;

  /// Total de cada linha já com a parte dela no desconto.
  final List<Money> lineTotals;
}

/// Apura bruto, desconto e total a partir dos brutos de cada linha.
SaleTotals computeTotals({
  required List<Money> lineGrosses,
  required int discountPercentHundredths,
}) {
  final gross = sumMoney(lineGrosses);
  final discount = gross.percent(discountPercentHundredths);
  final shares = splitDiscount(lineGrosses, discount);

  return SaleTotals(
    gross: gross,
    discount: discount,
    total: gross - discount,
    lineTotals: [
      for (var i = 0; i < lineGrosses.length; i++) lineGrosses[i] - shares[i],
    ],
  );
}
