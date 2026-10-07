/// Venda manual por categoria e valor — a forma como a V1 vende.
///
/// O catálogo continua no domínio e continua funcionando; o que deixou de
/// existir é a obrigação de passar por ele. O que estes testes protegem é o que
/// a linha guarda e o que vai para o servidor.
library;

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/quantity.dart';
import 'package:casa_das_bicicletas/data/repositories/sale_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  const pecas = ProductCategory(id: 1, code: 'PECAS', name: 'Peças');
  const pneus = ProductCategory(id: 2, code: 'PNEUS', name: 'Pneus');

  Product produto() => const Product(
        id: 10,
        sku: 'PN-10',
        name: 'Pneu 26 Cravado',
        categoryCode: 'PNEUS',
        categoryName: 'Pneus',
        price: Money.fromCents(12000),
      );

  group('linha manual', () {
    test('categoria e valor sem produto', () {
      final draft = SaleDraft()
        ..addManual(category: pecas, price: const Money.fromCents(12000));

      final line = draft.lines.single;
      expect(line.isManual, isTrue);
      expect(line.product, isNull);
      expect(line.label, 'Peças');
      expect(line.categoryCode, 'PECAS');
      expect(line.grossAmount, const Money.fromCents(12000));
    });

    test('quantidade omitida vale uma', () {
      final draft = SaleDraft()
        ..addManual(category: pecas, price: const Money.fromCents(12000));

      expect(draft.lines.single.quantity, const Quantity.units(1));
      expect(draft.totals.total, const Money.fromCents(12000));
    });

    test('quantidade multiplica o valor', () {
      final draft = SaleDraft()
        ..addManual(
          category: pneus,
          price: const Money.fromCents(35000),
          quantity: const Quantity.units(2),
        );

      expect(draft.totals.total, const Money.fromCents(70000));
    });

    test('várias categorias somam', () {
      final draft = SaleDraft()
        ..addManual(category: pecas, price: const Money.fromCents(12000))
        ..addManual(category: pneus, price: const Money.fromCents(35000));

      expect(draft.lineCount, 2);
      expect(draft.totals.total, const Money.fromCents(47000));
    });

    test('mesma categoria com valores diferentes são linhas distintas', () {
      // Somar esconderia do vendedor o que ele acabou de lançar.
      final draft = SaleDraft()
        ..addManual(category: pecas, price: const Money.fromCents(12000))
        ..addManual(category: pecas, price: const Money.fromCents(8000));

      expect(draft.lineCount, 2);
      expect(draft.totals.total, const Money.fromCents(20000));
    });

    test('a linha tem identidade própria para editar e remover', () {
      final draft = SaleDraft();
      final primeira =
          draft.addManual(category: pecas, price: const Money.fromCents(12000));
      final segunda =
          draft.addManual(category: pneus, price: const Money.fromCents(35000));

      expect(primeira.id, isNot(segunda.id));

      draft.setQuantity(segunda.id, const Quantity.units(3));
      expect(draft.totals.total, const Money.fromCents(12000 + 105000));

      draft.remove(primeira.id);
      expect(draft.lineCount, 1);
    });

    test('desconto de 5% incide sobre a venda manual', () {
      final draft = SaleDraft()
        ..addManual(category: pecas, price: const Money.fromCents(12000))
        ..discountPercentHundredths = 500;

      expect(draft.totals.discount, const Money.fromCents(600));
      expect(draft.totals.total, const Money.fromCents(11400));
      expect(draft.canBeFinished, isTrue);
    });
  });

  group('envio ao servidor', () {
    final repositorio = SaleRepositoryImpl(
      buildTestDependencies().apiClient,
    );

    test('linha manual vai como categoria e valor, sem product_id', () {
      final draft = SaleDraft()
        ..addManual(
          category: pneus,
          price: const Money.fromCents(35000),
          quantity: const Quantity.units(2),
        );

      final item = (repositorio.payloadFor(draft)['items']! as List).single
          as Map<String, Object?>;

      expect(item['category'], 'PNEUS');
      expect(item['unit_price'], '350.00');
      expect(item['quantity'], '2.000');
      expect(item.containsKey('product_id'), isFalse);
    });

    test('linha de catálogo continua indo como product_id', () {
      final draft = SaleDraft()..add(produto());

      final item = (repositorio.payloadFor(draft)['items']! as List).single
          as Map<String, Object?>;

      expect(item['product_id'], 10);
      expect(item['unit_price'], '120.00');
      expect(item.containsKey('category'), isFalse);
    });

    test('venda mista envia cada linha na sua forma', () {
      final draft = SaleDraft()
        ..add(produto())
        ..addManual(category: pecas, price: const Money.fromCents(8000));

      final itens =
          (repositorio.payloadFor(draft)['items']! as List).cast<Map<String, Object?>>();

      expect(itens, hasLength(2));
      expect(itens.first['product_id'], 10);
      expect(itens.last['category'], 'PECAS');
    });
  });
}
