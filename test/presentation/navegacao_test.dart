/// Ida e volta entre as telas do fluxo (§19 do fluxo do terminal).
///
/// O aplicativo roda em modo quiosque, com a barra do Android escondida: o
/// gesto do sistema existe, mas não está à vista. Uma tela sem retorno visível
/// deixa o operador preso — e no balcão "preso" significa fechar o terminal e
/// digitar a senha de novo no meio do atendimento.
///
/// O que se garante aqui é o caminho de volta, não o botão: cada teste sai da
/// tela e confere onde chegou.
library;

import 'package:casa_das_bicicletas/app/app.dart';
import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  RecordingTransport servidor() => RecordingTransport((request) {
        if (request.url.path.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
            ],
          });
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  group('PIN do vendedor', () {
    /// Aplicativo inteiro, pelo caminho de verdade: inicial → lista → nome.
    Future<AppDependencies> abrirPin(WidgetTester tester) async {
      final deps = buildTestDependencies(
        transport: RecordingTransport((request) {
          if (request.url.path.contains('sellers')) {
            return jsonResponse(const {
              'results': [
                {'id': 12, 'name': 'Juliana'},
              ],
            });
          }
          return jsonResponse(const {'results': <Object?>[]});
        }),
      );
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

      await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
      await tester.pumpAndSettle();
      await tocar(tester, find.text('INICIAR VENDA'));
      await tocar(tester, find.text('JULIANA'));
      return deps;
    }

    testWidgets('o fluxo chega ao PIN sem pedir senha de aparelho',
        (tester) async {
      await abrirPin(tester);

      expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsOneWidget);
      expect(find.text('INSIRA A SENHA DO TERMINAL'), findsNothing);
    });

    testWidgets('oferece a volta para a lista de nomes', (tester) async {
      await abrirPin(tester);

      expect(find.text('VOLTAR'), findsOneWidget);
      await tocar(tester, find.text('VOLTAR'));

      // Voltar aqui é trocar de pessoa, não sair do aparelho.
      expect(find.text('SELECIONE O VENDEDOR'), findsOneWidget);
      expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsNothing);
    });

    testWidgets('voltar não apaga a configuração do aparelho', (tester) async {
      final deps = await abrirPin(tester);
      await tocar(tester, find.text('VOLTAR'));

      expect(deps.session.deviceId, 'M10-0001');
      expect(deps.session.storeId, 1);
      // E dá para escolher de novo, sem passar por senha de aparelho nenhuma.
      await tocar(tester, find.text('JULIANA'));
      expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsOneWidget);
    });
  });

  group('nova venda', () {
    Future<AppDependencies> abrirVenda(WidgetTester tester) async {
      final deps = buildTestDependencies(transport: servidor());
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
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
      return deps;
    }

    Future<void> abrirMenu(WidgetTester tester) =>
        tocar(tester, find.byIcon(Icons.menu));

    testWidgets('o menu oferece trocar de vendedor', (tester) async {
      await abrirVenda(tester);
      await abrirMenu(tester);

      expect(find.text('Trocar vendedor'), findsOneWidget);
      // Sem venda lançada não há o que confirmar nem o que descartar.
      expect(find.text('Descartar esta venda'), findsNothing);
    });

    testWidgets('trocar de vendedor chega na seleção sem fechar o terminal',
        (tester) async {
      // Aplicativo inteiro: o que se quer provar é onde a navegação chega, e
      // isso depende das rotas nomeadas.
      final deps = buildTestDependencies(
        transport: RecordingTransport((request) {
          if (request.url.path.contains('product-categories')) {
            return jsonResponse(const {'results': <Object?>[]});
          }
          return jsonResponse(const {
            'results': [
              {'id': 12, 'name': 'Juliana'},
              {'id': 15, 'name': 'Maria Costa'},
            ],
          });
        }),
      );
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
      await deps.session.saveTerminal(
        TerminalAuth(
          terminalToken: 'token-do-terminal',
          terminalId: 7,
          storeId: 1,
          expiresAt: DateTime.now().add(const Duration(hours: 12)),
        ),
      );
      await deps.session.saveSession(
        SellerSession(
          sessionToken: 'tok',
          seller: const Seller(id: 12, name: 'Juliana'),
          storeId: 1,
          terminalId: 7,
          expiresAt: DateTime.now().add(const Duration(hours: 8)),
        ),
      );

      await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
      await tester.pumpAndSettle();
      await tocar(tester, find.text('NOVA VENDA'));
      await tocar(tester, find.text('SIM, CONTINUAR'));

      await abrirMenu(tester);
      await tocar(tester, find.text('Trocar vendedor'));

      // Chegou na seleção, e não na senha do aparelho: a autenticação do
      // terminal continua valendo.
      expect(find.text('SELECIONE O VENDEDOR'), findsOneWidget);
      expect(deps.session.hasSellerSession, isFalse);
      expect(deps.session.hasTerminalAuth, isTrue);
    });

    testWidgets('com itens lançados, trocar pede confirmação', (tester) async {
      await abrirVenda(tester);
      for (final d in '10000'.split('')) {
        await tester.tap(find.text(d).first);
        await tester.pump();
      }
      await tocar(tester, find.text('PEÇAS'));
      expect(find.text('R\$ 100,00'), findsWidgets);

      await abrirMenu(tester);
      await tocar(tester, find.text('Trocar vendedor'));

      expect(find.text('Trocar de vendedor com a venda aberta?'),
          findsOneWidget);
    });

    testWidgets('continuar vendendo mantém a venda em pé', (tester) async {
      final deps = await abrirVenda(tester);
      for (final d in '10000'.split('')) {
        await tester.tap(find.text(d).first);
        await tester.pump();
      }
      await tocar(tester, find.text('PEÇAS'));

      await abrirMenu(tester);
      await tocar(tester, find.text('Trocar vendedor'));
      await tocar(tester, find.text('Continuar vendendo'));

      // Nada se perdeu e ninguém foi desconectado.
      expect(find.text('R\$ 100,00'), findsWidgets);
      expect(deps.session.hasSellerSession, isTrue);
    });
  });
}
