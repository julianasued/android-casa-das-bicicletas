/// Configuração do terminal: a primeira tela de um aparelho novo.
///
/// O que se garante aqui é o que dói quando falha em campo: endereço `http://`
/// aceito (RNF01), configuração gravada apontando para um servidor que não
/// responde — o terminal não abre e quem descobre é o balcão —, e o
/// identificador do aparelho escondido justamente quando o suporte precisa
/// ouvi-lo pelo telefone.
///
/// Os campos são nativos, com o teclado do Android: os testes digitam por
/// `enterText`, que é o caminho do teclado do sistema — passa pelos
/// `inputFormatters` do campo, que é onde mora o limite da loja.
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
  void usarTela(WidgetTester tester, Size tamanho) {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<AppDependencies> abrir(
    WidgetTester tester, {
    HttpTransport? transporte,
    Size tamanho = const Size(1280, 800),
    double escalaDaFonte = 1,
  }) async {
    usarTela(tester, tamanho);
    final deps = transporte is RecordingTransport || transporte == null
        ? buildTestDependencies(transport: transporte as RecordingTransport?)
        : buildTestDependencies(transport: RecordingTransport.empty());

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(escalaDaFonte)),
            child: child!,
          ),
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

  /// Cada campo pelo nome que a tela deu a ele.
  Finder campo(String nome) => find.byKey(Key('campo-$nome'));

  /// Digita no campo, como quem usa o teclado do Android.
  Future<void> digitar(
    WidgetTester tester,
    String nomeDoCampo,
    String texto,
  ) async {
    await tester.enterText(campo(nomeDoCampo), texto);
    await tester.pumpAndSettle();
  }

  Future<void> limparCampo(WidgetTester tester, String nomeDoCampo) =>
      digitar(tester, nomeDoCampo, '');

  TextField campoNativo(WidgetTester tester, String nome) =>
      tester.widget<TextField>(campo(nome));

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
      await digitar(tester, 'api', 'http://192.168.0.9:8000');

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
      await limparCampo(tester, 'loja');

      expect(salvar(tester).onPressed, isNull);
      expect(find.textContaining('Preencha loja'), findsOneWidget);
    });

    testWidgets('com tudo preenchido, a faixa diz o que vai acontecer',
        (tester) async {
      await abrir(tester);
      await digitar(tester, 'loja', '1');

      expect(salvar(tester).onPressed, isNotNull);
      expect(
        find.textContaining('será vinculado à loja 1'),
        findsOneWidget,
      );
    });

    testWidgets('a loja aceita só dígitos, no máximo quatro', (tester) async {
      await abrir(tester);
      await digitar(tester, 'loja', '12345');

      // O quinto dígito não entra: o limite viaja no campo, não no teclado.
      expect(campoNativo(tester, 'loja').controller!.text, '1234');

      await digitar(tester, 'loja', '1a2');
      expect(campoNativo(tester, 'loja').controller!.text, '12');
    });
  });

  group('sugestão do aparelho', () {
    testWidgets('usar sugestão preenche o identificador', (tester) async {
      await abrir(tester);
      await limparCampo(tester, 'terminal');
      expect(find.text(sugestaoDoAparelho), findsOneWidget);

      await tester.tap(find.text('USAR SUGESTÃO'));
      await tester.pumpAndSettle();

      // Volta ao campo, e segue no rótulo do botão de sugestão.
      expect(find.text(sugestaoDoAparelho), findsNWidgets(2));
    });
  });

  group('teclado do sistema', () {
    testWidgets('os três campos são nativos e não bloqueiam a digitação',
        (tester) async {
      await abrir(tester);

      for (final nome in ['api', 'loja', 'terminal']) {
        final nativo = campoNativo(tester, nome);
        // `readOnly` é o que impediria o teclado do Android de abrir — era
        // assim que a tela protegia o teclado próprio.
        expect(nativo.readOnly, isFalse, reason: nome);
        expect(nativo.enabled, isNot(false), reason: nome);
      }
      expect(find.byType(EditableText), findsNWidgets(3));
    });

    testWidgets('cada campo pede o teclado certo ao sistema', (tester) async {
      await abrir(tester);

      expect(campoNativo(tester, 'api').keyboardType, TextInputType.url);
      expect(campoNativo(tester, 'loja').keyboardType, TextInputType.number);
      expect(campoNativo(tester, 'terminal').keyboardType, TextInputType.text);
    });

    testWidgets('o identificador nunca é mascarado', (tester) async {
      await abrir(tester);

      // É o valor que o suporte pede ao telefone.
      expect(campoNativo(tester, 'terminal').obscureText, isFalse);
      expect(find.text(sugestaoDoAparelho), findsWidgets);
    });

    testWidgets('tocar no cartão põe o foco no campo daquele cartão',
        (tester) async {
      await abrir(tester);

      await tester.tap(find.text('LOJA (ID)').first);
      await tester.pumpAndSettle();

      // Com o foco no campo é o Android que abre o teclado; o que se verifica
      // aqui é que o toque em qualquer parte do cartão chega ao campo certo.
      expect(campoNativo(tester, 'loja').focusNode!.hasFocus, isTrue);
      expect(campoNativo(tester, 'api').focusNode!.hasFocus, isFalse);
    });

    testWidgets('o avanço do teclado vai ao campo seguinte e o último fecha',
        (tester) async {
      await abrir(tester);

      expect(campoNativo(tester, 'api').textInputAction, TextInputAction.next);
      expect(campoNativo(tester, 'loja').textInputAction, TextInputAction.next);
      expect(
        campoNativo(tester, 'terminal').textInputAction,
        TextInputAction.done,
      );

      await tester.tap(find.text('ENDEREÇO DA API').first);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      expect(campoNativo(tester, 'loja').focusNode!.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(campoNativo(tester, 'terminal').focusNode!.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(campoNativo(tester, 'terminal').focusNode!.hasFocus, isFalse);
    });
  });

  group('o teclado do sistema aberto', () {
    /// Quanto o teclado do Android ocupa embaixo, em pixels físicos.
    ///
    /// É o defeito que fez esta tela desenhar um teclado próprio: no M10 o do
    /// sistema cobre metade da área útil. Com `resizeToAvoidBottomInset` a
    /// tela encolhe para caber acima dele, e o conteúdo rola.
    void abrirOTeclado(WidgetTester tester, {double altura = 320}) {
      tester.view.viewInsets = FakeViewPadding(bottom: altura);
    }

    testWidgets('a tela encolhe sem estourar o layout', (tester) async {
      await abrir(tester);
      abrirOTeclado(tester);
      await tester.tap(find.text('LOJA (ID)').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('cabe também em tela estreita e com a fonte ampliada',
        (tester) async {
      await abrir(tester, tamanho: const Size(360, 640), escalaDaFonte: 1.3);
      abrirOTeclado(tester, altura: 260);
      await tester.tap(find.text('LOJA (ID)').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('o campo em foco continua alcançável com o teclado aberto',
        (tester) async {
      await abrir(tester, tamanho: const Size(360, 640));
      abrirOTeclado(tester, altura: 260);

      // O último campo é o que ficava escondido atrás do teclado.
      await tester.tap(find.text('IDENTIFICADOR DO TERMINAL (X-DEVICE-ID)').first);
      await tester.pumpAndSettle();

      expect(campoNativo(tester, 'terminal').focusNode!.hasFocus, isTrue);
      // Visível de fato: o retângulo do campo está dentro da área que sobrou.
      final campoNaTela = tester.getRect(campo('terminal'));
      final sobrou = tester.view.physicalSize.height - 260;
      expect(campoNaTela.bottom, lessThanOrEqualTo(sobrou));
      expect(tester.takeException(), isNull);
    });
  });

  group('salvar', () {
    testWidgets('servidor que não responde não deixa gravar', (tester) async {
      final deps = await abrir(tester, transporte: _semRede());
      await digitar(tester, 'loja', '1');

      await tester.tap(find.text('SALVAR E ABRIR TERMINAL'));
      await tester.pumpAndSettle();

      // Continua na tela, com o motivo à vista, e nada foi gravado.
      expect(find.text('SALVAR E ABRIR TERMINAL'), findsOneWidget);
      expect(find.textContaining('Sem conexão'), findsWidgets);
      expect(deps.session.storeId, isNull);
    });

    testWidgets('servidor que responde grava e volta ao repouso',
        (tester) async {
      final deps = await abrir(
        tester,
        transporte: RecordingTransport(
          // 401 é resposta: o servidor está de pé e recusou por falta de token,
          // que é o esperado antes de o terminal autenticar.
          (_) => jsonResponse(const {'detail': 'sem token'}, statusCode: 401),
        ),
      );
      await digitar(tester, 'loja', '1');

      await tester.tap(find.text('SALVAR E ABRIR TERMINAL'));
      await tester.pumpAndSettle();

      expect(find.textContaining('configurado'), findsOneWidget);
      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(deps.session.storeId, 1);
      expect(deps.session.deviceId, sugestaoDoAparelho);
      // Volta ao repouso: daqui quem chega escolhe o nome e digita o PIN.
      expect(find.text('rota: /inicial'), findsOneWidget);
    });
  });
}
