/// Menu do terminal: o que o vendedor vê depois de entrar.
///
/// Uma ação domina a tela e as demais são ferramenta. O que se garante aqui,
/// além da navegação, é que as etiquetas dizem a verdade sobre o aparelho:
/// etiqueta verde numa impressora sem papel manda o vendedor montar uma venda
/// que não vai imprimir, e ele só descobre com o cliente no balcão.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:casa_das_bicicletas/domain/ports/document_printer.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:casa_das_bicicletas/presentation/home/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  /// Canvas da referência: é nele que a grade de três colunas cabe.
  void usarTelaDaReferencia(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<AppDependencies> abrir(
    WidgetTester tester, {
    FakeDocumentPrinter? impressora,
  }) async {
    usarTelaDaReferencia(tester);

    final deps = buildTestDependencies(printer: impressora);
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
        seller: const Seller(id: 12, name: 'Juliana'),
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

  group('o que o menu mostra', () {
    testWidgets('vendedor, terminal e as três ferramentas', (tester) async {
      await abrir(tester);

      expect(find.text('CASA DAS BICICLETAS'), findsOneWidget);
      expect(find.text('TERMINAL L1'), findsOneWidget);
      expect(find.text('VENDEDOR NO TERMINAL'), findsOneWidget);
      expect(find.text('JULIANA'), findsWidgets);
      expect(find.text('NOVA VENDA'), findsOneWidget);
      expect(find.text('LEITOR DE CÓDIGO'), findsOneWidget);
      expect(find.text('IMPRESSORA'), findsOneWidget);
      expect(find.text('TESTE ELGIN M10'), findsOneWidget);
    });

    testWidgets('a rede aparece com a loja, lida do estado real',
        (tester) async {
      await abrir(tester);

      expect(find.text('LOJA L1 · CONECTADO'), findsOneWidget);
    });

    testWidgets(
        'o rodapé diz o estado da impressora e para onde o terminal fala',
        (tester) async {
      await abrir(tester);

      expect(find.textContaining('Impressora pronta'), findsOneWidget);
      expect(find.textContaining('app '), findsOneWidget);
    });
  });

  group('as etiquetas seguem o aparelho', () {
    testWidgets('impressora pronta aparece como PRONTA', (tester) async {
      await abrir(tester);

      expect(find.text('PRONTA'), findsOneWidget);
      expect(find.text('SEM PAPEL'), findsNothing);
    });

    testWidgets('sem papel, a etiqueta e o rodapé dizem o motivo',
        (tester) async {
      await abrir(
        tester,
        impressora: FakeDocumentPrinter(
          currentStatus: const PrinterStatus(available: true, outOfPaper: true),
        ),
      );

      expect(find.text('SEM PAPEL'), findsOneWidget);
      expect(find.text('PRONTA'), findsNothing);
      expect(find.textContaining('Impressora sem papel'), findsOneWidget);
    });

    testWidgets('impressora fora do ar aparece como OFFLINE', (tester) async {
      await abrir(
        tester,
        impressora: FakeDocumentPrinter(
          currentStatus: const PrinterStatus.unavailable(),
        ),
      );

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.textContaining('Impressora indisponível'), findsOneWidget);
    });
  });

  group('para onde cada toque leva', () {
    testWidgets('NOVA VENDA abre a montagem da venda', (tester) async {
      await abrir(tester);

      await tester.tap(find.text('NOVA VENDA'));
      await tester.pumpAndSettle();

      // Passa pela confirmação de quem é o responsável antes da tela.
      await tester.tap(find.text('SIM, CONTINUAR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /venda'), findsOneWidget);
    });

    for (final destino in const {
      'LEITOR DE CÓDIGO': 'rota: /leitor',
      'IMPRESSORA': 'rota: /impressora',
      'TESTE ELGIN M10': 'rota: /m10',
    }.entries) {
      testWidgets('${destino.key} abre a sua tela', (tester) async {
        await abrir(tester);

        await tester.tap(find.text(destino.key));
        await tester.pumpAndSettle();

        expect(find.text(destino.value), findsOneWidget);
      });
    }

    testWidgets('TROCAR volta à seleção sem derrubar o terminal',
        (tester) async {
      final deps = await abrir(tester);

      await tester.tap(find.text('TROCAR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /vendedores'), findsOneWidget);
      // A sessão do vendedor caiu; a do aparelho continua de pé — é o que evita
      // pedir a senha do terminal a cada troca de turno.
      expect(deps.session.hasSellerSession, isFalse);
      expect(deps.session.hasTerminalAuth, isTrue);
    });

    testWidgets('SAIR fecha o terminal', (tester) async {
      final deps = await abrir(tester);

      await tester.tap(find.text('SAIR'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /inicial'), findsOneWidget);
      expect(deps.session.hasTerminalAuth, isFalse);
    });
  });

  group('alvo de toque do balcão', () {
    testWidgets('nada abaixo de 56 pontos', (tester) async {
      await abrir(tester);

      final alvos = [
        find.ancestor(
          of: find.text('TROCAR'),
          matching: find.byType(OutlinedButton),
        ),
        find.ancestor(
            of: find.text('NOVA VENDA'), matching: find.byType(InkWell)),
        find.ancestor(
          of: find.text('LEITOR DE CÓDIGO'),
          matching: find.byType(InkWell),
        ),
      ];

      for (final alvo in alvos) {
        expect(tester.getRect(alvo.first).height, greaterThanOrEqualTo(56));
      }
    });
  });
}
