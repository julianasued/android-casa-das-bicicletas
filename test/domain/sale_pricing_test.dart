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

    test('desconto de 5% sobre R$ 1.500,00 é R$ 75,00', () {
      final totals = computeTotals(
        lineGrosses: const [Money.fromCents(150000)],
        discountPercentHundredths: maxDiscountPercentHundredths,
      );

      expect(totals.discount.toApiString(), '75.00');
      expect(totals.total.toApiString(), '1425.00');
    });
  });
}
