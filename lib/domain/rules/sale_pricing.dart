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

/// Percentual, em centésimos, que aplica `amount` de desconto sobre `gross`.
///
/// É a volta do `Money.percent`: o vendedor negocia "tiro R$ 50" e o contrato
/// da API só aceita `discount_percent`, então alguém precisa converter. Fazer
/// isso aqui, e não na tela, é o que mantém uma conta só — a tela mostra o
/// desconto recalculando `gross.percent()` do resultado desta função, de modo
/// que o valor exibido é o mesmo que o servidor vai apurar.
///
/// Não muda regra nenhuma: o teto continua sendo o percentual, e quem chama
/// compara o retorno com [maxDiscountPercentHundredths] como sempre fez.
/// Percentual só tem duas casas, então nem todo valor em reais é exatamente
/// representável — o arredondamento é o mesmo `roundHalfUp` do resto da
/// aritmética, e a diferença fica em um centavo no pior caso.
int discountPercentFromAmount({required Money gross, required Money amount}) {
  if (!gross.isPositive || !amount.isPositive) return 0;
  return roundHalfUp(amount.cents * 10000, gross.cents);
}

/// O desconto negociado, guardado na unidade em que foi negociado.
///
/// Guardar a unidade, e não só o resultado, é o que faz R$ 69,00 continuar
/// valendo R$ 69,00. Percentual tem duas casas: sobre R$ 1.387,93, 4,97% dão
/// R$ 68,98 e 4,98% dão R$ 69,12 — nenhum dos dois é o número que o vendedor
/// combinou com o cliente. Convertendo para mostrar, e não para calcular, o
/// combinado é o que sai no papel.
///
/// As duas unidades se comportam diferente de propósito. Em percentual o
/// desconto acompanha o bruto: tirar um item da venda recalcula. Em reais o
/// valor é o combinado e não se mexe — o que muda é se ele ainda cabe no teto,
/// e disso cuida [exceedsCapOn].
class SaleDiscount {
  /// Negociado em percentual — o valor acompanha o bruto.
  const SaleDiscount.percent(this.hundredths) : amount = null;

  /// Negociado em reais — é este o valor, e nenhuma conversão o substitui.
  const SaleDiscount.amount(Money this.amount) : hundredths = 0;

  const SaleDiscount.none()
      : hundredths = 0,
        amount = null;

  /// Percentual negociado, em centésimos. Zero quando se negociou em reais.
  final int hundredths;

  /// Valor negociado. Nulo quando se negociou em percentual.
  final Money? amount;

  /// Se a negociação foi em reais — é o que decide o campo enviado ao servidor.
  bool get isAmount => amount != null;

  bool get isZero => amount == null ? hundredths == 0 : !amount!.isPositive;

  bool get isNegative => amount == null ? hundredths < 0 : amount!.cents < 0;

  /// O desconto em reais desta venda: o que entra no total e no documento.
  Money amountOn(Money gross) => amount ?? gross.percent(hundredths);

  /// Percentual equivalente, em centésimos — para exibir, nunca para calcular.
  int percentOn(Money gross) => amount == null
      ? hundredths
      : discountPercentFromAmount(gross: gross, amount: amount!);

  /// Se passou do teto de 5% (13.3), medido na unidade da negociação.
  ///
  /// Em reais a comparação é contra o teto **em reais**, e não contra o
  /// percentual convertido: sobre R$ 1.387,93 o teto é R$ 69,40, então R$ 69,40
  /// passa e R$ 69,41 não. É o mesmo centavo que o backend confere, e usar o
  /// percentual arredondado aqui faria os dois discordarem na borda.
  bool exceedsCapOn(Money gross) => amount == null
      ? hundredths > maxDiscountPercentHundredths
      : amount!.cents > gross.percent(maxDiscountPercentHundredths).cents;

  @override
  bool operator ==(Object other) =>
      other is SaleDiscount &&
      other.hundredths == hundredths &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(hundredths, amount);

  @override
  String toString() =>
      amount == null ? 'SaleDiscount.percent($hundredths)' : 'SaleDiscount.amount($amount)';
}

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
///
/// `discountAmount`, quando informado, é o desconto em reais já negociado e
/// substitui o percentual — é por ele que passa o desconto digitado em R\$,
/// que não pode ser reconstituído a partir de um percentual de duas casas.
SaleTotals computeTotals({
  required List<Money> lineGrosses,
  int discountPercentHundredths = 0,
  Money? discountAmount,
}) {
  final gross = sumMoney(lineGrosses);
  final discount = discountAmount ?? gross.percent(discountPercentHundredths);
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
