/// Configuração do terminal: a primeira tela de um aparelho novo.
///
/// O que se garante aqui é o que dói quando falha em campo: endereço `http://`
/// aceito (RNF01), configuração gravada apontando para um servidor que não
/// responde — o terminal não abre e quem descobre é o balcão —, e o
/// identificador do aparelho escondido justamente quando o suporte precisa
/// ouvi-lo pelo telefone.
library;

import 'dart:io';

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/data/remote/http_transport.dart';
import 'package:casa_das_bicicletas/presentation/setup/setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Transporte que não chega ao servidor — o caso do endereço errado.
RecordingTransport _semRede() =>
    RecordingTransport((_) => throw const SocketException('sem rota'));

void main() {
  const sugestaoDoAparelho = 'M10-ANDROID-ID';

  /// Canvas da referência. Sem isto o teste roda em 800x600, onde o botão de
  /// salvar fica abaixo da dobra e o toque não o alcança.
  void usarTelaDaReferencia(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<AppDependencies> abrir(
    WidgetTester tester, {
    HttpTransport? transporte,
  }) async {
    usarTelaDaReferencia(tester);
    final deps = transporte is RecordingTransport || transporte == null
        ? buildTestDependencies(transport: transporte as RecordingTransport?)
        : buildTestDependencies(transport: RecordingTransport.empty());

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: const SetupPage(),
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

  /// Abre o teclado do campo e digita, tecla a tecla.
  Future<void> digitar(
    WidgetTester tester,
    String rotuloDoCampo,
    String texto,
  ) async {
    await tester.tap(find.text(rotuloDoCampo).first);
    await tester.pumpAndSettle();
    for (final letra in texto.split('')) {
      await tester.tap(find.widgetWithText(FilledButton, letra).last);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'PRONTO'));
    await tester.pumpAndSettle();
  }

  Future<void> limparCampo(WidgetTester tester, String rotuloDoCampo) async {
    await tester.tap(find.text(rotuloDoCampo).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('LIMPAR').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'PRONTO'));
    await tester.pumpAndSettle();
  }

  FilledButton salvar(WidgetTester tester) => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('SALVAR E ABRIR TERMINAL'),
          matching: find.byType(FilledButton),
        ),
      );

  group('o que a tela mostra', () {
    testWidgets('anuncia o aparelho lido e o primeiro acesso', (tester) async {
      await abrir(tester);

      expect(find.text('APARELHO DETECTADO'), findsOneWidget);
      expect(find.text('Elgin M10'), findsOneWidget);
      expect(find.text('Android 11'), findsOneWidget);
      expect(find.text('PRIMEIRO ACESSO'), findsOneWidget);
    });

    testWidgets('o identificador do terminal fica à vista', (tester) async {
      await abrir(tester);

      // Nunca mascarado: é o valor que o suporte pede ao telefone.
      expect(find.text(sugestaoDoAparelho), findsWidgets);
    });
  });

  group('validação antes de gravar', () {
    testWidgets('endereço http recusa o avanço e avisa o motivo',
        (tester) async {
      await abrir(tester);
      await limparCampo(tester, 'ENDEREÇO DA API');
      await digitar(tester, 'ENDEREÇO DA API', 'HTTP');

      expect(find.text('USE HTTPS'), findsOneWidget);
      expect(salvar(tester).onPressed, isNull);
      expect(
        find.textContaining('precisa começar com https://'),
        findsOneWidget,
      );
    });

    testWidgets('sem loja e sem identificador, o salvar fica desligado',
        (tester) async {
      await abrir(tester);
      await limparCampo(tester, 'LOJA (ID)');

      expect(salvar(tester).onPressed, isNull);
      expect(find.textContaining('Preencha loja'), findsOneWidget);
    });

    testWidgets('com tudo preenchido, a faixa diz o que vai acontecer',
        (tester) async {
      await abrir(tester);
      await digitar(tester, 'LOJA (ID)', '1');

      expect(salvar(tester).onPressed, isNotNull);
      expect(
        find.textContaining('será vinculado à loja 1'),
        findsOneWidget,
      );
    });

    testWidgets('a loja aceita só dígitos, no máximo quatro', (tester) async {
      await abrir(tester);
      await limparCampo(tester, 'LOJA (ID)');
      await digitar(tester, 'LOJA (ID)', '12345');

      // O quinto dígito não entra.
      expect(find.text('1234'), findsWidgets);
      expect(find.text('12345'), findsNothing);
    });
  });

  group('sugestão do aparelho', () {
    testWidgets('usar sugestão preenche o identificador', (tester) async {
      await abrir(tester);
      await limparCampo(tester, 'IDENTIFICADOR DO TERMINAL (X-DEVICE-ID)');
      expect(find.text(sugestaoDoAparelho), findsOneWidget);

      await tester.tap(find.text('USAR SUGESTÃO'));
      await tester.pumpAndSettle();

      // Volta ao campo, e segue no rótulo do botão de sugestão.
      expect(find.text(sugestaoDoAparelho), findsNWidgets(2));
    });
  });

  group('teclado do aplicativo', () {
    testWidgets('tocar no campo abre o teclado da tela, não o do Android',
        (tester) async {
      await abrir(tester);

      expect(find.widgetWithText(FilledButton, 'PRONTO'), findsNothing);
      await tester.tap(find.text('LOJA (ID)').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'PRONTO'), findsOneWidget);
      // Numérico para a loja: sem letras.
      expect(find.widgetWithText(FilledButton, 'Q'), findsNothing);
      expect(find.widgetWithText(FilledButton, '0'), findsOneWidget);
      // E nenhum campo nativo, que chamaria o teclado do sistema.
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('o campo de texto usa o teclado alfanumérico', (tester) async {
      await abrir(tester);
      await tester.tap(find.text('ENDEREÇO DA API').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Q'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'ESPAÇO'), findsOneWidget);
    });

    testWidgets('PRONTO fecha o teclado', (tester) async {
      await abrir(tester);
      await tester.tap(find.text('LOJA (ID)').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'PRONTO'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'PRONTO'), findsNothing);
    });

    testWidgets('tocar fora do teclado também fecha', (tester) async {
      await abrir(tester);
      await tester.tap(find.text('LOJA (ID)').first);
      await tester.pumpAndSettle();

      // O véu ocupa tudo acima do teclado.
      await tester.tapAt(const Offset(40, 80));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'PRONTO'), findsNothing);
    });
  });

  group('salvar', () {
    testWidgets('servidor que não responde não deixa gravar', (tester) async {
      final deps = await abrir(tester, transporte: _semRede());
      await digitar(tester, 'LOJA (ID)', '1');

      await tester.tap(find.text('SALVAR E ABRIR TERMINAL'));
      await tester.pumpAndSettle();

      // Continua na tela, com o motivo à vista, e nada foi gravado.
      expect(find.text('SALVAR E ABRIR TERMINAL'), findsOneWidget);
      expect(find.textContaining('Sem conexão'), findsWidgets);
      expect(deps.session.storeId, isNull);
    });

    testWidgets('servidor que responde grava e abre a senha do terminal',
        (tester) async {
      final deps = await abrir(
        tester,
        transporte: RecordingTransport(
          // 401 é resposta: o servidor está de pé e recusou por falta de token,
          // que é o esperado antes de o terminal autenticar.
          (_) => jsonResponse(const {'detail': 'sem token'}, statusCode: 401),
        ),
      );
      await digitar(tester, 'LOJA (ID)', '1');

      await tester.tap(find.text('SALVAR E ABRIR TERMINAL'));
      await tester.pumpAndSettle();

      expect(find.textContaining('configurado'), findsOneWidget);
      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(deps.session.storeId, 1);
      expect(deps.session.deviceId, sugestaoDoAparelho);
      expect(find.text('rota: /terminal'), findsOneWidget);
    });
  });
}
