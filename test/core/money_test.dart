import 'package:casa_das_bicicletas/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('lê a string decimal da API sem passar por double', () {
      expect(Money.parse('1500.00').cents, 150000);
      expect(Money.parse('0.05').cents, 5);
      expect(Money.parse('250').cents, 25000);
      expect(Money.parse('-12.34').cents, -1234);
    });

    test('aceita vírgula, como o operador digita', () {
      expect(Money.parse('1500,50').cents, 150050);
    });

    test('arredonda a terceira casa para cima, em vez de truncar', () {
      expect(Money.parse('10.005').cents, 1001);
      expect(Money.parse('10.004').cents, 1000);
    });

    test('recusa valor que não é número', () {
      expect(() => Money.parse('abc'), throwsFormatException);
      expect(() => Money.parse('1.2.3'), throwsFormatException);
    });
  });

  group('formatação', () {
    test('toApiString devolve duas casas com ponto', () {
      expect(const Money.fromCents(150000).toApiString(), '1500.00');
      expect(const Money.fromCents(5).toApiString(), '0.05');
      expect(const Money.fromCents(-1234).toApiString(), '-12.34');
    });

    test('toDisplayString usa o formato do balcão', () {
      expect(const Money.fromCents(150000).toDisplayString(), r'R$ 1.500,00');
      expect(const Money.fromCents(100).toDisplayString(), r'R$ 1,00');
      expect(
        const Money.fromCents(123456789).toDisplayString(),
        r'R$ 1.234.567,89',
      );
      expect(
        const Money.fromCents(150000).toDisplayString(symbol: false),
        '1.500,00',
      );
    });
  });

  group('aritmética', () {
    test('soma dez centavos dez vezes e chega a um real exato', () {
      // O caso que motiva guardar centavos inteiros: em ponto flutuante esta
      // soma daria 0,9999999999999999.
      var total = const Money.zero();
      for (var i = 0; i < 10; i++) {
        total = total + const Money.fromCents(10);
      }
      expect(total.cents, 100);
    });

    test('percent arredonda meia unidade para cima, como o backend', () {
      // 5% de R$ 1.000,00 = R$ 50,00
      expect(const Money.fromCents(100000).percent(500).cents, 5000);
      // 3% de R$ 0,05 = R$ 0,0015 -> R$ 0,00
      expect(const Money.fromCents(5).percent(300).cents, 0);
      // 50% de R$ 0,01 = R$ 0,005 -> R$ 0,01 (meia unidade para cima)
      expect(const Money.fromCents(1).percent(5000).cents, 1);
    });

    test('timesThousandths multiplica pela quantidade em milésimos', () {
      expect(const Money.fromCents(25000).timesThousandths(2000).cents, 50000);
      expect(const Money.fromCents(1000).timesThousandths(500).cents, 500);
    });

    test('proportion calcula a fatia dentro de um todo', () {
      final share = const Money.fromCents(1000).proportion(
        part: const Money.fromCents(2500),
        whole: const Money.fromCents(10000),
      );
      expect(share.cents, 250);
    });
  });

  test('roundHalfUp arredonda meia unidade para cima nos dois sinais', () {
    expect(roundHalfUp(5, 2), 3);
    expect(roundHalfUp(4, 2), 2);
    expect(roundHalfUp(-5, 2), -3);
  });

  test('sumMoney soma uma lista', () {
    expect(
      sumMoney(const [
        Money.fromCents(1050),
        Money.fromCents(2000),
        Money.fromCents(1),
      ]).cents,
      3051,
    );
  });
}
