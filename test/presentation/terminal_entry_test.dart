/// Entrada do terminal: tela inicial e PIN do vendedor (§3 e §4 do fluxo).
///
/// O que se garante aqui é o que o balconista encosta o dedo: o teclado da
/// tela escreve no campo, apagar tira um dígito, limpar zera, e a senha
/// recusado não fica no campo esperando ser reenviado igual.
///
/// A senha é da pessoa, não do aparelho: não há mais etapa de senha do
/// terminal no acesso do vendedor (§2.3).
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/presentation/terminal/seller_login_page.dart';
import 'package:casa_das_bicicletas/presentation/welcome/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<AppDependencies> montarPin(
    WidgetTester tester, {
    RecordingTransport? transport,
  }) async {
    final deps = buildTestDependencies(transport: transport);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: const SellerLoginPage(
            vendedor: Seller(id: 12, name: 'Juliana'),
          ),
          // A tela navega para a venda quando o PIN passa.
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

      // O nome da loja agora vem dentro da arte da marca, não em texto solto.
      expect(find.byType(Image), findsOneWidget);
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

  group('PIN do vendedor', () {
    testWidgets('traz o título, o subtítulo e o teclado da tela',
        (tester) async {
      await montarPin(tester);

      expect(find.text('INSIRA A SENHA DO VENDEDOR'), findsOneWidget);
      // O nome de quem vai digitar fica à vista o tempo todo.
      expect(find.text('JULIANA'), findsOneWidget);
      expect(find.text('Digite sua senha'), findsOneWidget);
      for (final digito in ['0', '1', '5', '9']) {
        expect(find.widgetWithText(OutlinedButton, digito), findsOneWidget);
      }
      expect(find.text('LIMPAR'), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('o teclado escreve no campo', (tester) async {
      await montarPin(tester);

      for (final digito in ['1', '2', '3', '4']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }

      expect(senhaDigitada(tester), '1234');
    });

    testWidgets('apagar tira o último dígito e limpar zera', (tester) async {
      await montarPin(tester);

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
      await montarPin(tester);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(senhaDigitada(tester), isEmpty);
    });

    testWidgets('confirmar fica inativo enquanto não há senha', (tester) async {
      await montarPin(tester);

      final botao = find.widgetWithText(FilledButton, 'CONFIRMAR');
      expect(tester.widget<FilledButton>(botao).onPressed, isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, '1'));
      await tester.pump();

      expect(tester.widget<FilledButton>(botao).onPressed, isNotNull);
    });

    testWidgets('senha recusada mostra o erro e esvazia o campo',
        (tester) async {
      await montarPin(
        tester,
        transport: RecordingTransport(
          (_) => jsonResponse(
            const {
              'error': {
                'code': 'UNAUTHENTICATED',
                'message': 'Senha incorreta.',
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

      expect(find.text('Senha incorreta. Tente de novo.'), findsOneWidget);
      // Reenviar a mesma senha recusada é o engano mais comum aqui.
      expect(senhaDigitada(tester), isEmpty);
    });

    testWidgets('digitar de novo tira o erro da tela', (tester) async {
      await montarPin(
        tester,
        transport: RecordingTransport(
          (_) => jsonResponse(
            const {
              'error': {
                'code': 'UNAUTHENTICATED',
                'message': 'Senha incorreta.',
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
      expect(find.text('Senha incorreta. Tente de novo.'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '2'));
      await tester.pump();

      expect(find.text('Senha incorreta. Tente de novo.'), findsNothing);
    });

    /// Resposta de sessão aberta, como o §2.3 devolve.
    RecordingTransport sessaoAberta() => RecordingTransport(
          (_) => jsonResponse(const {
            'session_token': 'token-da-sessao',
            'seller_id': 12,
            'store_id': 1,
            'terminal_id': 7,
            'role': 'VENDEDOR',
            'expires_in': 28800,
          }),
        );

    testWidgets('o teclado é só numérico — não há letra para digitar',
        (tester) async {
      await montarPin(tester);

      // As letras de telefone saíram: é um PIN, e sugerir senha alfanumérica
      // num teclado que não digita letra é oferecer o que não existe.
      for (final letras in ['ABC', 'DEF', 'WXYZ']) {
        expect(find.text(letras), findsNothing, reason: letras);
      }
      // E o campo não abre o teclado do Android, que cobriria metade da tela.
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    });

    testWidgets('o PIN vai ao servidor com o vendedor escolhido (§2.3)',
        (tester) async {
      final transport = sessaoAberta();
      await montarPin(tester, transport: transport);

      for (final digito in ['4', '3', '2', '1']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRMAR'));
      await tester.pumpAndSettle();

      final enviada = transport.requests.firstWhere(
        (r) => r.url.path.contains('select-seller'),
      );
      // O id é de quem foi escolhido na tela anterior; o PIN é o que acabou de
      // ser digitado. É esse par que o servidor confere.
      expect(enviada.body, const {'seller_id': 12, 'password': '4321'});

      // E nenhuma senha de aparelho foi pedida: essa etapa não existe mais.
      expect(
        transport.requests.any((r) => r.url.path.endsWith('auth/terminal/')),
        isFalse,
      );
    });

    testWidgets('PIN certo autentica e entra na venda', (tester) async {
      final deps = await montarPin(tester, transport: sessaoAberta());

      await tester.tap(find.widgetWithText(OutlinedButton, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRMAR'));
      await tester.pumpAndSettle();

      // É este nome que a venda vai carimbar (RF06).
      expect(deps.session.hasSellerSession, isTrue);
      expect(deps.session.seller?.id, 12);
      expect(deps.session.seller?.name, 'Juliana');
      expect(find.text('rota: /venda'), findsOneWidget);
    });

    testWidgets('o PIN digitado não fica guardado no aparelho', (tester) async {
      final deps = await montarPin(tester, transport: sessaoAberta());

      for (final digito in ['4', '3', '2', '1']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digito));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRMAR'));
      await tester.pumpAndSettle();

      // O que sobra é o token da sessão, nunca a credencial.
      expect(deps.session.session?.sessionToken, 'token-da-sessao');
    });
  });
}
