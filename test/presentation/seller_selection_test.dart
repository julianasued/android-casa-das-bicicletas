/// Escolha do vendedor no terminal (§5 do fluxo, API §2.3).
///
/// A escolha aqui é quem **se diz** responsável; provar quem é vem na tela
/// seguinte, com o PIN da própria pessoa. A separação importa porque é dessa
/// escolha que sai a comissão (RF06, RF17–RF20): antes tocar no nome já abria
/// a sessão, e o nome na venda era só o nome que alguém tocou.
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

    expect(find.text('JOÃO SILVA'), findsOneWidget);
    expect(find.text('MARIA COSTA'), findsOneWidget);
    // Um ícone de pessoa por cartão, como na referência — o cadastro não tem
    // foto e as iniciais saíram com a estilização.
    expect(find.byIcon(Icons.person), findsNWidgets(3));
  });

  testWidgets('esta tela não pede senha', (tester) async {
    await montar(tester, sellers: doisVendedores);

    // O PIN existe, mas é da tela seguinte, onde já se sabe de quem ele é.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('senha', findRichText: true), findsNothing);
  });

  testWidgets('cada vendedor é um alvo confortável no M10', (tester) async {
    await montar(tester, sellers: doisVendedores);

    final cartao = tester.getSize(
      find.ancestor(
        of: find.text('JOÃO SILVA'),
        matching: find.byType(InkWell),
      ),
    );

    expect(cartao.height, greaterThanOrEqualTo(80));
  });

  testWidgets('tocar no nome abre o PIN daquela pessoa', (tester) async {
    final http = await montar(tester, sellers: doisVendedores);

    await tester.tap(find.text('MARIA COSTA'));
    await tester.pumpAndSettle();

    // A tela de PIN abriu, nomeando quem vai digitar.
    expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsOneWidget);
    expect(find.text('MARIA COSTA'), findsWidgets);

    // Nada foi aberto ainda: escolher o nome não é autenticar, e uma sessão
    // aberta aqui carimbaria na venda quem só encostou o dedo na lista.
    expect(
      http.requests.any((r) => r.url.path.contains('select-seller')),
      isFalse,
    );
  });

  testWidgets('a tela de PIN abre sem erro de rota', (tester) async {
    // A rota é empurrada direta, e não por nome: rota nomeada com argumento
    // tipado devolve `null` do gerador quando o `is` erra, e o Flutter derruba
    // a tela. Este teste monta a seleção **sem** gerador de rotas — se a tela
    // dependesse de um nome, aqui ela estouraria.
    final deps = buildTestDependencies(
      transport: RecordingTransport(
        (_) => jsonResponse(const {'results': <Object?>[]}),
      ),
    );

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: const MaterialApp(
          home: SellerSelectionPage(sellers: doisVendedores),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('MARIA COSTA'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsOneWidget);
  });

  testWidgets('voltar do PIN devolve à lista', (tester) async {
    await montar(tester, sellers: doisVendedores);

    await tester.tap(find.text('JOÃO SILVA'));
    await tester.pumpAndSettle();
    expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsOneWidget);

    await tester.tap(find.text('VOLTAR'));
    await tester.pumpAndSettle();

    // Volta para os nomes, e não para uma senha de aparelho que não existe.
    expect(find.text('SELECIONE O VENDEDOR'), findsOneWidget);
    expect(find.text('MARIA COSTA'), findsOneWidget);
  });

  testWidgets('carrega a lista quando ela não veio da abertura do terminal',
      (tester) async {
    await montar(tester);

    expect(find.text('JOÃO SILVA'), findsOneWidget);
    expect(find.text('MARIA COSTA'), findsOneWidget);
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

    expect(find.text('JOÃO SILVA'), findsOneWidget);
  });
}
