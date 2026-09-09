/// Testes de fumaça do aplicativo: ele abre e leva o operador ao lugar certo.
///
/// O roteamento inicial é decidido pelo que está no armazenamento seguro
/// (`BootstrapPage`), e errar isso significa pedir a senha do terminal no meio
/// de um atendimento ou, pior, cair numa tela de venda sem vendedor
/// selecionado.
library;

import 'package:casa_das_bicicletas/app/app.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('terminal sem configuração abre na tela de configuração',
      (tester) async {
    final deps = buildTestDependencies();

    await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.text('Configuração do terminal'), findsOneWidget);
    expect(find.text('Endereço da API'), findsOneWidget);
  });

  testWidgets('terminal configurado pede a senha do aparelho', (tester) async {
    final deps = buildTestDependencies();
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

    await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.text('Abrir terminal'), findsWidgets);
    expect(find.text('Senha do terminal'), findsOneWidget);
  });

  testWidgets('terminal aberto sem vendedor vai para a seleção', (tester) async {
    final deps = buildTestDependencies(
      transport: RecordingTransport(
        (_) => jsonResponse(const {
          'results': [
            {'id': 12, 'name': 'João Silva'},
            {'id': 15, 'name': 'Maria Costa'},
          ],
        }),
      ),
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

    await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.text('Quem vai vender?'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Maria Costa'), findsOneWidget);
  });

  testWidgets('sessão completa abre no menu do terminal', (tester) async {
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
    await deps.session.saveSession(
      SellerSession(
        sessionToken: 'token-de-sessao',
        seller: const Seller(id: 12, name: 'João Silva'),
        storeId: 1,
        terminalId: 7,
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
      ),
    );

    await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.text('Nova venda'), findsOneWidget);
    expect(find.text('Leitor de código'), findsOneWidget);
    expect(find.text('Impressora'), findsOneWidget);
    // O vendedor responsável fica visível o tempo todo (RF06).
    expect(find.text('João Silva'), findsOneWidget);
  });

  testWidgets('token vencido não restaura a sessão', (tester) async {
    final deps = buildTestDependencies();

    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    await deps.session.saveTerminal(
      TerminalAuth(
        terminalToken: 'token-vencido',
        terminalId: 7,
        storeId: 1,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    await tester.pumpWidget(CasaDasBicicletasApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.text('Senha do terminal'), findsOneWidget);
  });

  testWidgets('o aplicativo é um MaterialApp com o título da loja',
      (tester) async {
    await tester.pumpWidget(
      CasaDasBicicletasApp(dependencies: buildTestDependencies()),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Casa das Bicicletas');
  });
}
