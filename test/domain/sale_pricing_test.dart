import 'package:casa_das_bicicletas/core/formatters.dart';
import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitDiscount', () {
    test('rateia na proporção de cada linha', () {
      final shares = splitDiscount(
        const [Money.fromCents(50000), Money.fromCents(100000)],
        const Money.fromCents(7500),
      );

      expect(shares[0].cents, 2500);
      expect(shares[1].cents, 5000);
      expect(sumMoney(shares).cents, 7500);
    });

    test('a sobra de centavo vai para a maior linha', () {
      // R$ 0,01 de desconto sobre duas linhas iguais não divide em dois: uma
      // delas fica com o centavo, e a soma continua fechando.
      final shares = splitDiscount(
        const [Money.fromCents(1000), Money.fromCents(2000)],
        const Money.fromCents(1),
      );

      expect(sumMoney(shares).cents, 1);
      expect(shares[1].cents, greaterThanOrEqualTo(shares[0].cents));
    });

    test('sem desconto, ninguém recebe nada', () {
      final shares = splitDiscount(
        const [Money.fromCents(1000), Money.fromCents(2000)],
        const Money.zero(),
      );
      expect(shares.every((share) => share.isZero), isTrue);
    });

    test('venda de valor zero não divide por zero', () {
      final shares = splitDiscount(
        const [Money.zero(), Money.zero()],
        const Money.fromCents(100),
      );
      expect(shares.every((share) => share.isZero), isTrue);
    });
  });

  group('computeTotals', () {
    test('reproduz o exemplo da especificação da API', () {
      // §3.4.1: dois itens, R$ 500,00 + R$ 1.000,00, sem desconto.
      final totals = computeTotals(
        lineGrosses: const [Money.fromCents(50000), Money.fromCents(100000)],
        discountPercentHundredths: 0,
      );

      expect(totals.gross.toApiString(), '1500.00');
      expect(totals.discount.toApiString(), '0.00');
      expect(totals.total.toApiString(), '1500.00');
    });

    test('a soma dos totais de linha bate com o total da venda', () {
      // A invariante que faz o relatório de comissão por categoria fechar com o
      // total da venda (comentário do `services.create_sale` no backend).
      final totals = computeTotals(
        lineGrosses: const [
          Money.fromCents(3333),
          Money.fromCents(6667),
          Money.fromCents(1),
        ],
        discountPercentHundredths: 500,
      );

      expect(sumMoney(totals.lineTotals).cents, totals.total.cents);
      expect(totals.gross - totals.discount, totals.total);
    });

    test(r'desconto de 5% sobre R$ 1.500,00 é R$ 75,00', () {
      final totals = computeTotals(
        lineGrosses: const [Money.fromCents(150000)],
        discountPercentHundredths: maxDiscountPercentHundredths,
      );

      expect(totals.discount.toApiString(), '75.00');
      expect(totals.total.toApiString(), '1425.00');
    });
  });

  /// A volta do `Money.percent`, usada pelo desconto em reais da Nova Venda.
  ///
  /// O contrato da API é `discount_percent`, então o valor em reais só existe
  /// como entrada: tudo o que sai daqui é percentual, e o teto continua sendo
  /// comparado contra ele.
  group('discountPercentFromAmount', () {
    test('R\$ 50,00 sobre R\$ 1.000,00 dá exatamente 5%', () {
      expect(
        discountPercentFromAmount(
          gross: const Money.fromCents(100000),
          amount: const Money.fromCents(5000),
        ),
        maxDiscountPercentHundredths,
      );
    });

    test('sem valor, sem percentual', () {
      expect(
        discountPercentFromAmount(
          gross: const Money.fromCents(100000),
          amount: const Money.zero(),
        ),
        0,
      );
    });

    test('venda zerada não divide por zero', () {
      expect(
        discountPercentFromAmount(
          gross: const Money.zero(),
          amount: const Money.fromCents(5000),
        ),
        0,
      );
    });

    test('valor acima do teto devolve percentual acima do teto', () {
      // R$ 6,00 em R$ 100,00 são 6%: quem chama recusa pelo mesmo teto de
      // sempre, sem precisar de regra nova para o modo em reais.
      final percentual = discountPercentFromAmount(
        gross: const Money.fromCents(10000),
        amount: const Money.fromCents(600),
      );

      expect(percentual, 600);
      expect(percentual, greaterThan(maxDiscountPercentHundredths));
    });

    test('é a volta do percent: o que entra em reais volta em reais', () {
      const bruto = Money.fromCents(33333);
      for (final centavos in [1, 99, 100, 1000, 1666]) {
        final valor = Money.fromCents(centavos);
        final percentual =
            discountPercentFromAmount(gross: bruto, amount: valor);
        // Percentual só tem duas casas, então nem todo valor fecha exato; o
        // que não pode é a ida e a volta andarem para longe do digitado.
        expect(
          (bruto.percent(percentual).cents - centavos).abs(),
          lessThanOrEqualTo(2),
          reason: 'R\$ ${valor.toDisplayString()}',
        );
      }
    });

    test('numa venda grande o centésimo de percentual vale mais que o centavo',
        () {
      // R$ 10.000,00: 0,01% já são R$ 1,00, então R$ 123,45 não é
      // representável e vira R$ 123,00. É por isso que a tela mostra o
      // desconto recalculado, e não o que foi digitado.
      const bruto = Money.fromCents(1000000);
      final percentual = discountPercentFromAmount(
        gross: bruto,
        amount: const Money.fromCents(12345),
      );

      expect(percentual, 123);
      expect(bruto.percent(percentual).cents, 12300);
    });
  });

  /// O desconto guardado na unidade em que foi negociado.
  ///
  /// R$ 1.387,93 é o caso que motivou o tipo: 4,97% dão R$ 68,98 e 4,98% dão
  /// R$ 69,12, então R$ 69,00 não sobrevive a uma ida e volta pelo percentual.
  group('SaleDiscount', () {
    const bruto = Money.fromCents(138793);

    test('em reais, o valor negociado é o valor aplicado', () {
      const desconto = SaleDiscount.amount(Money.fromCents(6900));

      expect(desconto.amountOn(bruto).cents, 6900);
      // A volta pelo percentual daria 68,98 — é o que não pode acontecer.
      expect(bruto.percent(desconto.percentOn(bruto)).cents, 6898);
    });

    test('em reais, o percentual é só equivalência', () {
      const desconto = SaleDiscount.amount(Money.fromCents(6900));

      expect(desconto.percentOn(bruto), 497);
      expect(formatPercentDisplay(desconto.percentOn(bruto)), '4,97%');
    });

    test('em percentual, o valor acompanha o bruto', () {
      const desconto = SaleDiscount.percent(maxDiscountPercentHundredths);

      // 5% de R$ 1.387,93 são R$ 69,3965, fechados em R$ 69,40.
      expect(desconto.amountOn(bruto).cents, 6940);
      expect(desconto.percentOn(bruto), 500);
    });

    test('o teto em reais é o mesmo 5%, conferido no centavo', () {
      expect(
        const SaleDiscount.amount(Money.fromCents(6900)).exceedsCapOn(bruto),
        isFalse,
      );
      expect(
        const SaleDiscount.amount(Money.fromCents(6940)).exceedsCapOn(bruto),
        isFalse,
      );
      expect(
        const SaleDiscount.amount(Money.fromCents(6941)).exceedsCapOn(bruto),
        isTrue,
      );
    });

    test('o teto não é medido pelo percentual arredondado', () {
      // R$ 69,41 convertido dá 5,00%, que passaria pelo teto percentual. O
      // valor é que precisa ser conferido, e ele está um centavo acima.
      const acima = SaleDiscount.amount(Money.fromCents(6941));

      expect(acima.percentOn(bruto), maxDiscountPercentHundredths);
      expect(acima.exceedsCapOn(bruto), isTrue);
    });

    test('em percentual o teto continua sendo o percentual', () {
      expect(const SaleDiscount.percent(500).exceedsCapOn(bruto), isFalse);
      expect(const SaleDiscount.percent(501).exceedsCapOn(bruto), isTrue);
    });

    test('sem desconto não desconta nada', () {
      const nenhum = SaleDiscount.none();

      expect(nenhum.isZero, isTrue);
      expect(nenhum.amountOn(bruto).cents, 0);
      expect(nenhum.percentOn(bruto), 0);
      expect(nenhum.exceedsCapOn(bruto), isFalse);
    });

    test(r'ir de % para R$ e voltar não move o valor', () {
      const emPercentual = SaleDiscount.percent(maxDiscountPercentHundredths);
      final emReais = SaleDiscount.amount(emPercentual.amountOn(bruto));

      expect(emReais.amountOn(bruto), emPercentual.amountOn(bruto));
      expect(emReais.percentOn(bruto), emPercentual.percentOn(bruto));
      expect(emReais.exceedsCapOn(bruto), isFalse);
    });

    test('o total sai do valor negociado, não do percentual', () {
      final totais = computeTotals(
        lineGrosses: const [bruto],
        discountAmount:
            const SaleDiscount.amount(Money.fromCents(6900)).amountOn(bruto),
      );

      expect(totais.discount.cents, 6900);
      expect(totais.total.cents, 131893);
      expect(totais.lineTotals.single.cents, 131893);
    });
  });
}
