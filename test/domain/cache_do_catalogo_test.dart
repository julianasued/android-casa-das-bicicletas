/// OFF-005 — a idade do catálogo guardado no terminal (RF34).
///
/// Sete dias é decisão do dono (09/10/2026). O que se fixa aqui é a fronteira,
/// porque é ela que decide se o vendedor vê aviso antes de fechar a venda com
/// um preço que pode ter mudado.
library;

import 'package:casa_das_bicicletas/domain/rules/cache_do_catalogo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final agora = DateTime(2026, 10, 9, 15, 0);

  group('classificação', () {
    test('sem catálogo guardado, não há idade a comentar', () {
      expect(
        estadoDoCatalogoLocal(null, agora: agora),
        EstadoDoCatalogoLocal.ausente,
      );
    });

    test('catálogo de hoje é recente', () {
      expect(
        estadoDoCatalogoLocal(agora.subtract(const Duration(hours: 2)), agora: agora),
        EstadoDoCatalogoLocal.recente,
      );
    });

    test('seis dias ainda não avisa', () {
      // O limite anunciado foi sete; avisar antes viraria ruído diário.
      expect(
        estadoDoCatalogoLocal(agora.subtract(const Duration(days: 6)), agora: agora),
        EstadoDoCatalogoLocal.recente,
      );
    });

    test('sete dias cheios avisa', () {
      expect(
        estadoDoCatalogoLocal(agora.subtract(const Duration(days: 7)), agora: agora),
        EstadoDoCatalogoLocal.velho,
      );
    });

    test('um mês avisa', () {
      expect(
        estadoDoCatalogoLocal(agora.subtract(const Duration(days: 30)), agora: agora),
        EstadoDoCatalogoLocal.velho,
      );
    });

    test('data no futuro não é tratada como velha', () {
      // Relógio do M10 adiantado não pode inventar aviso (ver OFF-004).
      expect(
        estadoDoCatalogoLocal(agora.add(const Duration(days: 3)), agora: agora),
        EstadoDoCatalogoLocal.recente,
      );
    });
  });

  group('dias para a frase', () {
    test('conta dias inteiros', () {
      expect(diasDeCatalogo(agora.subtract(const Duration(days: 12, hours: 5)), agora: agora), 12);
    });

    test('menos de um dia é zero', () {
      expect(diasDeCatalogo(agora.subtract(const Duration(hours: 10)), agora: agora), 0);
    });
  });

  test('a fronteira é de sete dias', () {
    // O número está num lugar só, e é este o teste que o diz.
    expect(idadeQueMereceAviso, const Duration(days: 7));
  });
}
