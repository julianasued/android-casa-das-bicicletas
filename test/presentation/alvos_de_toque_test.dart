/// Tamanho e alinhamento dos controles da Nova Venda.
///
/// O M10 é operado em pé, com o dedo, e o balcão não espera: controle curto
/// aqui é venda lançada errada. Três defeitos vistos no aparelho moram neste
/// arquivo — teclas de ~45 pontos com a última fileira cortada pelo painel da
/// venda, o DESCONTO com a casca do tema (pílula verde de raio 20) ao lado do
/// CLIENTE, e o vendedor com o SAIR parados no meio do cabeçalho.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Tela do M10 em pixels lógicos: 720x1440 físicos a dois pixels por ponto.
const Size _m10 = Size(720, 1440);
const double _densidade = 2;

/// Alvo mínimo de toque desta tela.
const double _minimo = 56;

void main() {
  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = _m10;
    tester.view.devicePixelRatio = _densidade;
    addTearDown(tester.view.reset);

    final deps = buildTestDependencies(
      transport: RecordingTransport((request) {
        if (request.url.path.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
              {'id': 2, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
              {'id': 3, 'code': 'OLEOS', 'name': 'Óleos', 'is_active': true},
            ],
          });
        }
        return jsonResponse(const {'results': <Object?>[]});
      }),
    );
    await deps.session.saveSession(
      SellerSession(
        sessionToken: 'tok',
        seller: const Seller(id: 12, name: 'Juliana'),
        storeId: 1,
        terminalId: 1,
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
      ),
    );

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: const MaterialApp(home: NewSalePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  /// A área que responde ao toque, e não a caixa desenhada em volta dela.
  Rect areaDeToque(WidgetTester tester, Finder conteudo) => tester.getRect(
        find.ancestor(of: conteudo, matching: find.byType(InkWell)).first,
      );

  group('nada abaixo de 56 pontos de altura', () {
    testWidgets('teclas do teclado do valor', (tester) async {
      await abrir(tester);

      for (final tecla in ['1', '5', '9', '0', '00']) {
        expect(
          areaDeToque(tester, find.text(tecla)).height,
          greaterThanOrEqualTo(_minimo),
          reason: 'tecla $tecla',
        );
      }
    });

    testWidgets('formas de pagamento', (tester) async {
      await abrir(tester);

      for (final forma in ['PIX', 'DINHEIRO', 'CRÉDITO', 'DÉBITO', 'NOTINHA']) {
        expect(
          areaDeToque(tester, find.text(forma)).height,
          greaterThanOrEqualTo(_minimo),
          reason: forma,
        );
      }
    });

    testWidgets('cliente e desconto', (tester) async {
      await abrir(tester);

      for (final alvo in [
        find.text('CLIENTE'),
        find.byIcon(Icons.percent),
      ]) {
        expect(
          tester
              .getRect(
                find.ancestor(of: alvo, matching: find.byType(OutlinedButton)),
              )
              .height,
          greaterThanOrEqualTo(_minimo),
        );
      }
    });
  });

  group('a última fileira do teclado não é cortada', () {
    testWidgets('o 0 e o apagar cabem acima do painel da venda',
        (tester) async {
      await abrir(tester);

      // O painel da venda começa onde o teclado acaba; a fileira do `0` tem de
      // caber inteira antes disso, sombra dura inclusive.
      final zero = areaDeToque(tester, find.text('0'));
      final pagamento = areaDeToque(tester, find.text('PIX'));

      expect(zero.bottom, lessThan(pagamento.top));
    });
  });

  group('cliente e desconto são o mesmo botão', () {
    testWidgets('mesma altura, mesma largura, mesma linha', (tester) async {
      await abrir(tester);

      final cliente = tester.getRect(
        find.ancestor(
          of: find.text('CLIENTE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      final desconto = tester.getRect(
        find.ancestor(
          of: find.byIcon(Icons.percent),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(desconto.height, cliente.height);
      expect(desconto.width, cliente.width);
      expect(desconto.top, cliente.top);
    });

    testWidgets('o desconto usa a paleta do PDV, não o verde do tema',
        (tester) async {
      await abrir(tester);

      final icone = tester.widget<Icon>(find.byIcon(Icons.percent));
      expect(
          icone.color,
          isNot(Theme.of(tester.element(find.byType(NewSalePage)))
              .colorScheme
              .primary));
      expect(icone.color, const Color(0xFF3C4257));
    });
  });

  group('cabeçalho', () {
    testWidgets('vendedor e SAIR ficam no canto direito', (tester) async {
      await abrir(tester);

      final tela = tester.getRect(find.byType(NewSalePage));
      final sair = tester.getRect(find.byIcon(Icons.logout));
      final vendedor = tester.getRect(find.text('JULIANA'));
      final titulo = tester.getRect(find.text('NOVA VENDA'));

      // O SAIR encosta na margem da tela — não sobra espaço morto à direita.
      expect(tela.right - sair.right, lessThan(24));
      // E o vendedor vem logo antes dele, depois do título.
      expect(vendedor.left, greaterThan(titulo.left));
      expect(vendedor.right, lessThan(sair.left));
    });
  });
}
