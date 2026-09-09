import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/quantity.dart';
import 'package:casa_das_bicicletas/domain/entities/customer.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({int id = 10, int cents = 25000, String name = 'Pneu Aro 15'}) =>
    Product(
      id: id,
      sku: 'SKU-$id',
      name: name,
      categoryCode: 'PNEUS',
      categoryName: 'Pneus',
      price: Money.fromCents(cents),
    );

void main() {
  group('carrinho', () {
    test('o mesmo produto soma na linha existente, sem duplicar', () {
      final draft = SaleDraft()
        ..add(_product())
        ..add(_product());

      expect(draft.lineCount, 1);
      expect(draft.lines.single.quantity, const Quantity.units(2));
    });

    test('quantidade zero remove a linha', () {
      final draft = SaleDraft()..add(_product());
      draft.setQuantity(10, const Quantity.units(0));

      expect(draft.isEmpty, isTrue);
    });

    test('totais acompanham o carrinho', () {
      final draft = SaleDraft()
        ..add(_product(cents: 25000))
        ..add(_product(id: 33, cents: 100000));

      expect(draft.totals.total.toApiString(), '1250.00');
    });
  });

  group('regras de finalização', () {
    test('venda sem item não pode ser finalizada', () {
      final draft = SaleDraft();

      expect(draft.canBeFinished, isFalse);
      expect(draft.problems.first.message, contains('produto'));
    });

    test('notinha exige cliente (RF14)', () {
      final draft = SaleDraft()
        ..add(_product())
        ..paymentMethod = PaymentMethod.notinha;

      expect(draft.canBeFinished, isFalse);
      expect(draft.problems.any((p) => p.message.contains('cliente')), isTrue);

      draft.customer = const Customer(id: 42, name: 'Cliente Teste');
      expect(draft.canBeFinished, isTrue);
    });

    test('desconto acima de 5% é recusado antes de ir à rede (13.3)', () {
      final draft = SaleDraft()
        ..add(_product())
        ..discountPercentHundredths = 501;

      expect(draft.canBeFinished, isFalse);
      expect(draft.problems.any((p) => p.message.contains('5%')), isTrue);
    });

    test('venda comum não exige cliente', () {
      final draft = SaleDraft()
        ..add(_product())
        ..paymentMethod = PaymentMethod.pix;

      expect(draft.canBeFinished, isTrue);
    });
  });

  test('o identificador nasce no terminal e forma o código de barras', () {
    final draft = SaleDraft();

    expect(draft.uuid.length, 36);
    expect(draft.barcodeFor('L2'), startsWith('SALE-L2-'));
  });
}
