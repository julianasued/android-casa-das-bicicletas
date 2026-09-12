/// Seleção do vendedor no terminal (§5 do fluxo, API §2.3).
///
/// A escolha aqui é quem responde pela venda e, por consequência, quem recebe
/// a comissão (RF06, RF17–RF20). O que se garante: o nome é um alvo grande,
/// não se pede senha nenhuma, e um toque não vira duas seleções.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/presentation/seller/seller_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<RecordingTransport> montar(
    WidgetTester tester, {
    List<Seller>? sellers,
    RecordingTransport? transport,
  }) async {
    final http = transport ??
        RecordingTransport((request) {
          if (request.url.path.contains('select-seller')) {
            return jsonResponse(const {
              'session_token': 'token-de-sessao',
              'seller_id': 12,
              'store_id': 1,
              'terminal_id': 7,
              'role': 'VENDEDOR',
              'expires_in': 28800,
            });
          }
          return jsonResponse(const {
            'results': [
              {'id': 12, 'name': 'João Silva'},
              {'id': 15, 'name': 'Maria Costa'},
            ],
          });
        });

    final deps = buildTestDependencies(transport: http);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: SellerSelectionPage(sellers: sellers),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return http;
  }

  const doisVendedores = [
    Seller(id: 12, name: 'João Silva'),
    Seller(id: 15, name: 'Maria Costa'),
  ];

  testWidgets('traz o título e a instrução do §5', (tester) async {
    await montar(tester, sellers: doisVendedores);

    expect(find.text('SELECIONE O VENDEDOR'), findsOneWidget);
    expect(
      find.text('Toque no nome do vendedor para continuar'),
      findsOneWidget,
    );
  });

  testWidgets('lista os vendedores habilitados no terminal', (tester) async {
    await montar(tester, sellers: doisVendedores);

    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Maria Costa'), findsOneWidget);
    // Iniciais no lugar de foto: o cadastro não tem imagem.
    expect(find.text('JS'), findsOneWidget);
    expect(find.text('MC'), findsOneWidget);
  });

  testWidgets('não pede senha do vendedor', (tester) async {
    await montar(tester, sellers: doisVendedores);

    // A seleção não é autenticação: quem tem senha é o terminal.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('senha', findRichText: true), findsNothing);
  });

  testWidgets('cada vendedor é um alvo confortável no M10', (tester) async {
    await montar(tester, sellers: doisVendedores);

    final botao = tester.getSize(
      find.ancestor(
        of: find.text('João Silva'),
        matching: find.byType(OutlinedButton),
      ),
    );

    expect(botao.height, greaterThanOrEqualTo(80));
  });

  testWidgets('tocar no nome seleciona o vendedor no servidor',
      (tester) async {
    final http = await montar(tester, sellers: doisVendedores);

    await tester.tap(find.text('Maria Costa'));
    await tester.pumpAndSettle();

    final enviada = http.requests.firstWhere(
      (r) => r.url.path.contains('select-seller'),
    );
    expect(enviada.body, const {'seller_id': 15});
  });

  testWidgets('selecionar entra direto na venda (§5 e §19)', (tester) async {
    await montar(tester, sellers: doisVendedores);

    await tester.tap(find.text('João Silva'));
    await tester.pumpAndSettle();

    // Não passa mais pelo menu: quem escolheu o nome escolheu para vender.
    expect(find.text('rota: /venda'), findsOneWidget);
  });

  testWidgets('carrega a lista quando ela não veio da abertura do terminal',
      (tester) async {
    await montar(tester);

    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Maria Costa'), findsOneWidget);
  });

  testWidgets('terminal sem vendedor habilitado explica o que fazer',
      (tester) async {
    await montar(
      tester,
      transport: RecordingTransport(
        (_) => jsonResponse(const {'results': <Object?>[]}),
      ),
    );

    expect(
      find.textContaining('Nenhum vendedor habilitado'),
      findsOneWidget,
    );
  });

  testWidgets('falha ao carregar oferece tentar de novo', (tester) async {
    var tentativas = 0;
    await montar(
      tester,
      transport: RecordingTransport((request) {
        if (request.url.path.contains('sellers')) {
          tentativas++;
          if (tentativas == 1) {
            return jsonResponse(
              const {
                'error': {
                  'code': 'INTERNAL_ERROR',
                  'message': 'Erro não tratado.',
                  'details': <String, Object?>{},
                },
              },
              statusCode: 500,
            );
          }
          return jsonResponse(const {
            'results': [
              {'id': 12, 'name': 'João Silva'},
            ],
          });
        }
        return jsonResponse(const <String, Object?>{});
      }),
    );

    expect(find.text('Tentar de novo'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('João Silva'), findsOneWidget);
  });
}
