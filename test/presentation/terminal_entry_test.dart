/// Entrada do terminal: tela inicial e senha do aparelho (§3 e §4 do fluxo).
///
/// O que se garante aqui é o que o balconista encosta o dedo: o teclado da
/// tela escreve no campo, apagar tira um dígito, limpar zera, e a senha
/// recusada não fica no campo esperando ser reenviada igual.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/terminal/terminal_login_page.dart';
import 'package:casa_das_bicicletas/presentation/welcome/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<AppDependencies> montarSenha(
    WidgetTester tester, {
    RecordingTransport? transport,
  }) async {
    final deps = buildTestDependencies(transport: transport);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: const TerminalLoginPage(),
          // A tela navega para a seleção de vendedor quando a senha passa.
          // Sem gerador, a `MaterialApp` nua do teste falharia na navegação e
          // esconderia o que está sendo verificado.
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

  /// O campo é `obscureText`, então o texto visível não serve de asserção.
  String senhaDigitada(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  group('tela inicial', () {
    testWidgets('mostra o aparelho e a ação única', (tester) async {
      final deps = buildTestDependencies();
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: const MaterialApp(home: WelcomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CASA DAS BICICLETAS'), findsOneWidget);
      expect(find.text('M10-0001'), findsOneWidget);
      expect(find.text('INICIAR VENDA'), findsOneWidget);
    });

    testWidgets('sem identificação não deixa a área em branco', (tester) async {
      final deps = buildTestDependencies();

      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: const MaterialApp(home: WelcomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('não identificado'), findsOneWidget);
    });
  });

  group('senha do terminal', () {
    testWidgets('traz o título, o subtítulo e o teclado da tela',
        (tester) async {
      await montarSenha(tester);

      expect(find.text('INSIRA A SENHA DO TERMINAL'), findsOneWidget);
      expect(
        find.text('Digite sua senha para acessar o sistema'),
        findsOneWidget,
      );
      for (final digito in ['0', '1', '5', '9']) {
        expect(find.widgetWithText(OutlinedButton, digito), findsOneWidget);
      }
      expect(find.text('LIMPAR'), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('o teclado escreve no campo', (tester) async {
      await montarSenha(tester);

      for (final digito in ['1', '2', '3', '4']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }

      expect(senhaDigitada(tester), '1234');
    });

    testWidgets('apagar tira o último dígito e limpar zera', (tester) async {
      await montarSenha(tester);

      for (final digito in ['7', '8', '9']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(senhaDigitada(tester), '78');

      await tester.tap(find.text('LIMPAR'));
      await tester.pump();
      expect(senhaDigitada(tester), isEmpty);
    });

    testWidgets('apagar com o campo vazio não quebra', (tester) async {
      await montarSenha(tester);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(senhaDigitada(tester), isEmpty);
    });

    testWidgets('confirmar fica inativo enquanto não há senha', (tester) async {
      await montarSenha(tester);

      final botao = find.widgetWithText(FilledButton, 'CONFIRMAR');
      expect(tester.widget<FilledButton>(botao).onPressed, isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, '1'));
      await tester.pump();

      expect(tester.widget<FilledButton>(botao).onPressed, isNotNull);
    });

    testWidgets('senha recusada mostra o erro e esvazia o campo',
        (tester) async {
      await montarSenha(
        tester,
        transport: RecordingTransport(
          (_) => jsonResponse(
            const {
              'error': {
                'code': 'UNAUTHENTICATED',
                'message': 'Senha do terminal inválida.',
                'details': <String, Object?>{},
              },
            },
            statusCode: 401,
          ),
        ),
      );

      for (final digito in ['9', '9', '9', '9']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRMAR'));
      await tester.pumpAndSettle();

      expect(find.text('Senha do terminal incorreta.'), findsOneWidget);
      // Reenviar a mesma senha recusada é o engano mais comum aqui.
      expect(senhaDigitada(tester), isEmpty);
    });

    testWidgets('digitar de novo tira o erro da tela', (tester) async {
      await montarSenha(
        tester,
        transport: RecordingTransport(
          (_) => jsonResponse(
            const {
              'error': {
                'code': 'UNAUTHENTICATED',
                'message': 'Senha do terminal inválida.',
                'details': <String, Object?>{},
              },
            },
            statusCode: 401,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRMAR'));
      await tester.pumpAndSettle();
      expect(find.text('Senha do terminal incorreta.'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '2'));
      await tester.pump();

      expect(find.text('Senha do terminal incorreta.'), findsNothing);
    });

    testWidgets('a senha vai para o servidor no contrato do §2.1',
        (tester) async {
      final transport = RecordingTransport(
        (_) => jsonResponse(const {
          'terminal_token': 'token-do-terminal',
          'terminal_id': 7,
          'store_id': 1,
          'expires_in': 43200,
        }),
      );
      await montarSenha(tester, transport: transport);

      for (final digito in ['4', '3', '2', '1']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRMAR'));
      await tester.pumpAndSettle();

      final enviada = transport.requests.firstWhere(
        (r) => r.url.path.contains('auth/terminal'),
      );
      expect(
        enviada.body,
        const {'store_id': 1, 'terminal_password': '4321'},
      );
    });
  });
}
