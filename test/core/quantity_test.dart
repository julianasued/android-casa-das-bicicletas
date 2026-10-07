import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse lê as três casas que a API aceita', () {
    expect(Quantity.parse('2').thousandths, 2000);
    expect(Quantity.parse('2.000').thousandths, 2000);
    expect(Quantity.parse('0.5').thousandths, 500);
    expect(Quantity.parse('1,250').thousandths, 1250);
  });

  test('toApiString sempre devolve três casas', () {
    expect(const Quantity.units(2).toApiString(), '2.000');
    expect(const Quantity.fromThousandths(500).toApiString(), '0.500');
  });

  test('toDisplayString esconde a casa decimal quando não há', () {
    expect(const Quantity.units(2).toDisplayString(), '2');
    expect(const Quantity.fromThousandths(1500).toDisplayString(), '1,5');
  });

  test('multiply fecha o total da linha em centavos', () {
    final total = const Quantity.units(3).multiply(const Money.fromCents(2599));
    expect(total.cents, 7797);
  });

  test('quantidade fracionada multiplica sem erro de arredondamento', () {
    // Meio litro de óleo a R$ 33,33 = R$ 16,665 -> R$ 16,67 (meia para cima).
    final total =
        const Quantity.fromThousandths(500).multiply(const Money.fromCents(3333));
    expect(total.cents, 1667);
  });
}
