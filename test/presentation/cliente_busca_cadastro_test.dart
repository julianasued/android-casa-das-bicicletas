/// Etapas 7 e 8 — buscar e cadastrar cliente (§7 e §8 do fluxo).
///
/// O que estas telas decidem é se a venda sai fiada, então o que o vendedor vê
/// antes de confirmar importa: quem é, o que já deve na loja, e se há vencida.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/customer_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Map<String, Object?> cliente({
    String nome = 'Maria Oliveira',
    String? telefone = '11999990000',
    String? documento = '12345678909',
    String endereco = 'Rua das Flores, 120',
  }) =>
      {
        'id': 77,
        'name': nome,
        'document': documento,
        'phone': telefone,
        'address': endereco,
        'is_active': true,
      };

  Map<String, Object?> pendencia({
    String pendente = '1500.00',
    String status = 'ABERTA',
  }) =>
      {
        'id': 501,
        'sale_id': 10482,
        'original_amount': '1500.00',
        'paid_amount': '0.00',
        'pending_amount': pendente,
        'status': status,
        'created_at': '2026-08-05T14:32:00Z',
      };

  RecordingTransport servidor({
    List<Map<String, Object?>>? clientes,
    List<Map<String, Object?>>? pendencias,
  }) =>
      RecordingTransport((request) {
        if (request.url.path.contains('receivables')) {
          return jsonResponse({'results': pendencias ?? const []});
        }
        if (request.url.path.contains('customers')) {
          if (request.method == 'POST') {
            return jsonResponse(cliente(nome: 'Cliente Novo'), statusCode: 201);
          }
          return jsonResponse({'results': clientes ?? [cliente()]});
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  Future<CustomerSelection?> abrir(
    WidgetTester tester, {
    RecordingTransport? transport,
    bool exigeCliente = false,
  }) async {
    CustomerSelection? escolhido;
    final deps = buildTestDependencies(transport: transport ?? servidor());

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    escolhido =
                        await Navigator.of(context).push<CustomerSelection>(
                      MaterialPageRoute(
                        builder: (_) =>
                            CustomerPickerPage(exigeCliente: exigeCliente),
                      ),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return escolhido;
  }

  group('busca (§7)', () {
    testWidgets('traz título, instrução e o campo de pesquisa',
        (tester) async {
      await abrir(tester);

      expect(find.text('BUSCAR CLIENTE'), findsOneWidget);
      expect(find.text('PESQUISE POR NOME OU TELEFONE'), findsOneWidget);
      expect(find.text('VOLTAR'), findsOneWidget);
      expect(find.text('CADASTRAR CLIENTE'), findsOneWidget);
    });

    testWidgets('pesquisa por nome vai ao servidor', (tester) async {
      final http = servidor();
      await abrir(tester, transport: http);

      await tester.enterText(find.byType(TextField).first, 'Maria');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final busca =
          http.requests.lastWhere((r) => r.url.path.contains('customers'));
      expect(busca.url.queryParameters['q'], 'Maria');
    });

    testWidgets('pesquisa por telefone usa o mesmo parâmetro', (tester) async {
      final http = servidor();
      await abrir(tester, transport: http);

      await tester.enterText(find.byType(TextField).first, '11999990000');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final busca =
          http.requests.lastWhere((r) => r.url.path.contains('customers'));
      expect(busca.url.queryParameters['q'], '11999990000');
    });

    testWidgets('sem resultado, explica e oferece cadastrar', (tester) async {
      await abrir(tester, transport: servidor(clientes: const []));

      expect(find.textContaining('BUSCA SEM RESULTADO'), findsOneWidget);
      expect(find.text('CADASTRAR CLIENTE'), findsOneWidget);
    });

    testWidgets('na notinha não há atalho de vender sem cliente',
        (tester) async {
      await abrir(tester, exigeCliente: true);
      expect(find.text('VENDA SEM CLIENTE'), findsNothing);
    });
  });

  group('cliente escolhido (§7)', () {
    Future<void> abrirCliente(
      WidgetTester tester, {
      List<Map<String, Object?>>? pendencias,
    }) async {
      await abrir(tester, transport: servidor(pendencias: pendencias));
      await tester.tap(find.text('Maria Oliveira'));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra nome, telefone, documento e endereço', (tester) async {
      await abrirCliente(tester);

      expect(find.text('Maria Oliveira'), findsWidgets);
      expect(find.text('11999990000'), findsWidgets);
      expect(find.text('DOCUMENTO'), findsOneWidget);
      expect(find.text('ENDEREÇO'), findsOneWidget);
      expect(find.text('Rua das Flores, 120'), findsOneWidget);
    });

    testWidgets('cliente sem dívida diz isso, e não fica em branco',
        (tester) async {
      await abrirCliente(tester);
      expect(find.textContaining('não deve nada'), findsOneWidget);
    });

    testWidgets('total em aberto vem do endpoint de pendências',
        (tester) async {
      await abrirCliente(tester, pendencias: [pendencia()]);

      expect(
        find.textContaining('Total em aberto: R\$ 1.500,00'),
        findsOneWidget,
      );
    });

    testWidgets('pendência vencida é anunciada', (tester) async {
      await abrirCliente(tester, pendencias: [pendencia(status: 'VENCIDA')]);
      expect(find.text('Há pendência vencida.'), findsOneWidget);
    });

    testWidgets('confirmar devolve o cliente com as pendências',
        (tester) async {
      CustomerSelection? escolhido;
      final deps = buildTestDependencies(
        transport: servidor(pendencias: [pendencia()]),
      );

      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      escolhido =
                          await Navigator.of(context).push<CustomerSelection>(
                        MaterialPageRoute(
                          builder: (_) => const CustomerPickerPage(),
                        ),
                      );
                    },
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maria Oliveira'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USAR ESTE CLIENTE'));
      await tester.pumpAndSettle();

      expect(escolhido?.customer.name, 'Maria Oliveira');
      // As pendências viajam junto: a venda não consulta de novo.
      expect(escolhido?.receivables, hasLength(1));
    });
  });

  group('cadastro (§8)', () {
    testWidgets('os campos são os do contrato, só o nome obrigatório',
        (tester) async {
      await abrir(tester);
      await tester.tap(find.text('CADASTRAR CLIENTE'));
      await tester.pumpAndSettle();

      expect(find.text('NOME'), findsOneWidget);
      for (final campo in [
        'TELEFONE (opcional)',
        'CPF / CNPJ (opcional)',
        'ENDEREÇO (opcional)',
        'OBSERVAÇÃO (opcional)',
      ]) {
        expect(find.text(campo), findsOneWidget, reason: campo);
      }
    });

    testWidgets('sem nome, não salva', (tester) async {
      final http = servidor();
      await abrir(tester, transport: http);
      await tester.tap(find.text('CADASTRAR CLIENTE'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SALVAR E USAR NA VENDA'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome.'), findsOneWidget);
      expect(
        http.requests.any((r) => r.method == 'POST'),
        isFalse,
      );
    });

    testWidgets('envia os campos preenchidos no contrato do backend',
        (tester) async {
      final http = servidor();
      await abrir(tester, transport: http);
      await tester.tap(find.text('CADASTRAR CLIENTE'));
      await tester.pumpAndSettle();

      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'Antonio Carlos');
      await tester.enterText(campos.at(1), '11988887777');
      await tester.enterText(campos.at(3), 'Rua A, 10');
      await tester.enterText(campos.at(4), 'Casa dos fundos');
      await tester.tap(find.text('SALVAR E USAR NA VENDA'));
      await tester.pumpAndSettle();

      final criado =
          http.requests.lastWhere((r) => r.method == 'POST');
      final corpo = criado.body! as Map;
      expect(corpo['name'], 'Antonio Carlos');
      expect(corpo['phone'], '11988887777');
      expect(corpo['address'], 'Rua A, 10');
      expect(corpo['notes'], 'Casa dos fundos');
      // Campo vazio não é enviado: o contrato aceita ausência, não string vazia.
      expect(corpo.containsKey('document'), isFalse);
    });

    testWidgets('cadastrado volta para a venda já selecionado', (tester) async {
      CustomerSelection? escolhido;
      final deps = buildTestDependencies(transport: servidor());

      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      escolhido =
                          await Navigator.of(context).push<CustomerSelection>(
                        MaterialPageRoute(
                          builder: (_) => const CustomerPickerPage(),
                        ),
                      );
                    },
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CADASTRAR CLIENTE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Cliente Novo');
      await tester.tap(find.text('SALVAR E USAR NA VENDA'));
      await tester.pumpAndSettle();

      // Sem passar pela busca de novo.
      expect(escolhido?.customer.name, 'Cliente Novo');
      // Recém-cadastrado não tem pendência: lista vazia, não desconhecida.
      expect(escolhido?.receivables, isEmpty);
    });
  });
}
