/// Avisos do rascunho da venda (§10 do fluxo, regra 13.3 / D1).
///
/// O aviso existe porque a recusa acontece longe daqui: `POST /sales/` aceita
/// crédito com desconto, e quem devolve `DISCOUNT_WITH_CREDIT` é o caixa. Sem
/// avisar na composição, o erro só aparece com o cliente já no balcão do caixa
/// e o documento 1 impresso.
library;

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Product produto() => const Product(
        id: 1,
        sku: 'PN-1',
        name: 'Pneu 26 Cravado',
        categoryCode: 'PNEUS',
        categoryName: 'Pneus',
        price: Money.fromCents(12000),
      );

  SaleDraft comItem() => SaleDraft()..add(produto());

  test('crédito com desconto avisa, mas não impede de registrar', () {
    final draft = comItem()
      ..paymentMethod = PaymentMethod.credito
      ..discountPercentHundredths = 500;

    expect(draft.warnings, hasLength(1));
    expect(draft.warnings.first.message, contains('crédito'));
    // O backend aceita esta venda: bloquear aqui seria inventar regra.
    expect(draft.canBeFinished, isTrue);
    expect(draft.problems, isEmpty);
  });

  test('crédito sem desconto não avisa nada', () {
    final draft = comItem()..paymentMethod = PaymentMethod.credito;

    expect(draft.warnings, isEmpty);
  });

  test('desconto em outra forma de pagamento não avisa', () {
    for (final forma in [
      PaymentMethod.pix,
      PaymentMethod.dinheiro,
      PaymentMethod.debito,
    ]) {
      final draft = comItem()
        ..paymentMethod = forma
        ..discountPercentHundredths = 500;

      expect(draft.warnings, isEmpty, reason: 'forma ${forma.code}');
    }
  });

  test('tirar o desconto tira o aviso', () {
    final draft = comItem()
      ..paymentMethod = PaymentMethod.credito
      ..discountPercentHundredths = 300;
    expect(draft.warnings, hasLength(1));

    draft.discountPercentHundredths = 0;
    expect(draft.warnings, isEmpty);
  });

  test('acima do teto continua sendo problema, não aviso', () {
    final draft = comItem()
      ..paymentMethod = PaymentMethod.credito
      ..discountPercentHundredths = 800;

    expect(draft.problems, isNotEmpty);
    expect(draft.canBeFinished, isFalse);
  });
}
