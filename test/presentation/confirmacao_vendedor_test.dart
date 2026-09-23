/// Confirmação de quem é o responsável, antes de abrir a venda.
///
/// A sessão do vendedor dura o expediente e a venda é atribuída a quem estiver
/// nela: sem a pergunta, basta o balcão trocar de gente para a venda — e a
/// comissão dela — sair no nome errado, e o conserto depois é alteração de
/// venda aprovada por gerente.
///
/// O que se garante aqui é que a pergunta não vira etapa: um toque segue, a
/// troca usa a seleção que já existe, e desistir não mexe em nada.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/presentation/home/home_page.dart';
import 'package:casa_das_bicicletas/presentation/sale/sale_finished_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<AppDependencies> abrirMenu(
    WidgetTester tester, {
    String vendedor = 'Juliana',
  }) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final deps = buildTestDependencies();
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    await deps.session.saveStoreCode('L1');
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
        sessionToken: 'token-da-sessao',
        seller: Seller(id: 12, name: vendedor),
        storeId: 1,
        terminalId: 7,
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
      ),
    );

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: const HomePage(),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return deps;
  }

  Future<void> tocarEmNovaVenda(WidgetTester tester) async {
    await tester.ensureVisible(find.text('NOVA VENDA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOVA VENDA'));
    await tester.pumpAndSettle();
  }

  group('a pergunta', () {
    testWidgets('mostra o vendedor da sessão pelo nome', (tester) async {
      await abrirMenu(tester, vendedor: 'Juliana');
      await tocarEmNovaVenda(tester);

      expect(find.text('VENDEDOR'), findsOneWidget);
      expect(find.text('JULIANA'), findsWidgets);
      expect(find.text('É você quem vai realizar esta venda?'), findsOneWidget);
      expect(find.text('SIM, CONTINUAR'), findsOneWidget);
      expect(find.text('TROCAR VENDEDOR'), findsOneWidget);
    });

    testWidgets('vem antes da venda, não depois', (tester) async {
      await abrirMenu(tester);
      await tocarEmNovaVenda(tester);

      // A montagem só abre depois da resposta.
      expect(find.text('rota: /venda'), findsNothing);
    });

    testWidgets('não pede a senha do terminal de novo', (tester) async {
      await abrirMenu(tester);
      await tocarEmNovaVenda(tester);

      expect(find.text('Senha do terminal'), findsNothing);
      expect(find.text('INSIRA A SENHA DO TERMINAL'), findsNothing);
    });
  });

  group('vendedor confirmado', () {
    testWidgets('um toque abre a venda', (tester) async {
      await abrirMenu(tester);
      await tocarEmNovaVenda(tester);

      await tester.tap(find.text('SIM, CONTINUAR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /venda'), findsOneWidget);
    });

    testWidgets('a venda continua vinculada a quem foi confirmado',
        (tester) async {
      final deps = await abrirMenu(tester, vendedor: 'Maria Costa');
      await tocarEmNovaVenda(tester);
      await tester.tap(find.text('SIM, CONTINUAR'));
      await tester.pumpAndSettle();

      // Confirmar não mexe na sessão: é a mesma pessoa, com a mesma sessão,
      // que a venda vai registrar.
      expect(deps.session.seller?.name, 'Maria Costa');
      expect(deps.session.seller?.id, 12);
      expect(deps.session.hasSellerSession, isTrue);
      expect(deps.session.hasTerminalAuth, isTrue);
    });
  });

  group('troca de vendedor', () {
    testWidgets('abre a seleção que já existe', (tester) async {
      await abrirMenu(tester);
      await tocarEmNovaVenda(tester);

      await tester.tap(find.text('TROCAR VENDEDOR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /vendedores'), findsOneWidget);
      expect(find.text('rota: /venda'), findsNothing);
    });

    testWidgets('derruba só a sessão do vendedor, não o terminal',
        (tester) async {
      final deps = await abrirMenu(tester);
      await tocarEmNovaVenda(tester);
      await tester.tap(find.text('TROCAR VENDEDOR'));
      await tester.pumpAndSettle();

      expect(deps.session.hasSellerSession, isFalse);
      // O aparelho continua autenticado e configurado: a senha do terminal
      // não volta a ser pedida por causa de uma troca de turno.
      expect(deps.session.hasTerminalAuth, isTrue);
      expect(deps.session.deviceId, 'M10-0001');
    });

    testWidgets('não escolhe ninguém sozinho', (tester) async {
      final deps = await abrirMenu(tester);
      await tocarEmNovaVenda(tester);
      await tester.tap(find.text('TROCAR VENDEDOR'));
      await tester.pumpAndSettle();

      // Quem escolhe é a tela de seleção; aqui ninguém entra no lugar.
      expect(deps.session.seller, isNull);
    });
  });

  group('desistir', () {
    testWidgets('tocar fora não abre a venda nem troca o vendedor',
        (tester) async {
      final deps = await abrirMenu(tester);
      await tocarEmNovaVenda(tester);

      // Fora do cartão: o canto superior esquerdo da tela.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.text('É você quem vai realizar esta venda?'), findsNothing);
      expect(find.text('rota: /venda'), findsNothing);
      expect(find.text('rota: /vendedores'), findsNothing);
      expect(deps.session.seller?.name, 'Juliana');
      expect(deps.session.hasSellerSession, isTrue);
    });

    testWidgets('e o menu continua utilizável', (tester) async {
      await abrirMenu(tester);
      await tocarEmNovaVenda(tester);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      // A pergunta pode ser feita de novo, sem sair do lugar.
      await tocarEmNovaVenda(tester);
      expect(find.text('É você quem vai realizar esta venda?'), findsOneWidget);

      await tester.tap(find.text('SIM, CONTINUAR'));
      await tester.pumpAndSettle();
      expect(find.text('rota: /venda'), findsOneWidget);
    });
  });

  /// A venda acabou e se começa outra — é aqui que o turno costuma virar.
  group('depois de uma venda registrada', () {
    Future<AppDependencies> montarDesfecho(
      WidgetTester tester, {
      String? vendedor = 'Juliana',
    }) async {
      final deps = buildTestDependencies();
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
      await deps.session.saveTerminal(
        TerminalAuth(
          terminalToken: 'token-do-terminal',
          terminalId: 7,
          storeId: 1,
          expiresAt: DateTime.now().add(const Duration(hours: 12)),
        ),
      );
      if (vendedor != null) {
        await deps.session.saveSession(
          SellerSession(
            sessionToken: 'token-da-sessao',
            seller: Seller(id: 12, name: vendedor),
            storeId: 1,
            terminalId: 7,
            expiresAt: DateTime.now().add(const Duration(hours: 8)),
          ),
        );
      }

      final json = saleJson();
      json['document_1'] = documentJson();

      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            home: SaleFinishedPage(
              finished: SaleFinished(result: saleWithDocumentFromJson(json)),
            ),
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
              settings: settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return deps;
    }

    Future<void> tocarEmNovaVenda(WidgetTester tester) async {
      await tester.ensureVisible(find.text('NOVA VENDA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NOVA VENDA'));
      await tester.pumpAndSettle();
    }

    testWidgets('NOVA VENDA também confirma o responsável', (tester) async {
      await montarDesfecho(tester);
      await tocarEmNovaVenda(tester);

      expect(find.text('É você quem vai realizar esta venda?'), findsOneWidget);
      expect(find.text('rota: /venda'), findsNothing);
    });

    testWidgets('confirmado, abre a venda seguinte', (tester) async {
      final deps = await montarDesfecho(tester);
      await tocarEmNovaVenda(tester);
      await tester.tap(find.text('SIM, CONTINUAR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /venda'), findsOneWidget);
      expect(deps.session.seller?.name, 'Juliana');
    });

    testWidgets('trocando, vai à seleção com o terminal de pé', (tester) async {
      final deps = await montarDesfecho(tester);
      await tocarEmNovaVenda(tester);
      await tester.tap(find.text('TROCAR VENDEDOR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /vendedores'), findsOneWidget);
      expect(deps.session.hasSellerSession, isFalse);
      expect(deps.session.hasTerminalAuth, isTrue);
    });

    testWidgets('sem vendedor em sessão não há o que confirmar',
        (tester) async {
      await montarDesfecho(tester, vendedor: null);
      await tocarEmNovaVenda(tester);

      // Nada a perguntar: a pergunta seria sobre ninguém.
      expect(find.text('É você quem vai realizar esta venda?'), findsNothing);
      expect(find.text('rota: /venda'), findsOneWidget);
    });
  });
}
