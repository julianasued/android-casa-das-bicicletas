/// A consulta de pendências na tela de escolha do cliente (RF15).
///
/// O que importa aqui é o que o vendedor vê antes de fiar: o total devido, o
/// aviso de vencida, e a diferença entre "não deve nada" e "não deu para
/// consultar" — que num balcão sem rede é a confusão mais cara.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/customer_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<void> abrirPendencias(
    WidgetTester tester,
    RecordingTransport transport,
  ) async {
    final deps = buildTestDependencies(transport: transport);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: const MaterialApp(home: CustomerPickerPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
    await tester.pumpAndSettle();
  }

  RecordingTransport comPendencias(List<Map<String, Object?>> pendencias) =>
      RecordingTransport((request) {
        if (request.url.path.contains('receivables')) {
          return jsonResponse({'results': pendencias});
        }
        return jsonResponse({
          'results': [
            {'id': 77, 'name': 'João Silva', 'is_active': true},
          ],
        });
      });

  Map<String, Object?> pendencia({
    String original = '1500.00',
    String paid = '0.00',
    String pending = '1500.00',
    String status = 'ABERTA',
  }) =>
      {
        'id': 501,
        'sale_id': 10482,
        'original_amount': original,
        'paid_amount': paid,
        'pending_amount': pending,
        'status': status,
        'created_at': '2026-08-05T14:32:00Z',
      };

  testWidgets('mostra quanto o cliente está devendo', (tester) async {
    await abrirPendencias(tester, comPendencias([pendencia()]));

    expect(find.text('Devendo R\$ 1.500,00'), findsOneWidget);
    expect(find.textContaining('Venda 10482'), findsOneWidget);
  });

  testWidgets('soma apenas o que ainda está em aberto', (tester) async {
    await abrirPendencias(
      tester,
      comPendencias([
        pendencia(pending: '1000.00'),
        pendencia(pending: '500.00', status: 'VENCIDA'),
        // Quitada não entra no total.
        pendencia(pending: '0.00', paid: '1500.00', status: 'QUITADA'),
      ]),
    );

    expect(find.text('Devendo R\$ 1.500,00'), findsOneWidget);
  });

  testWidgets('avisa quando há pendência vencida', (tester) async {
    await abrirPendencias(
      tester,
      comPendencias([pendencia(status: 'VENCIDA')]),
    );

    expect(find.text('Há pendência vencida.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('cliente sem pendência diz isso, e não fica vazio',
      (tester) async {
    await abrirPendencias(tester, comPendencias(const []));

    expect(find.textContaining('não deve nada'), findsOneWidget);
  });

  testWidgets('pagamento parcial mostra o que já foi pago', (tester) async {
    // Sem isto, um saldo menor que o valor da venda parece erro de cálculo.
    await abrirPendencias(
      tester,
      comPendencias([
        pendencia(original: '1500.00', paid: '500.00', pending: '1000.00'),
      ]),
    );

    expect(find.textContaining('pagou R\$ 500,00'), findsOneWidget);
    expect(find.text('R\$ 1.000,00'), findsOneWidget);
  });

  testWidgets('falha na consulta não se confunde com não ter dívida',
      (tester) async {
    await abrirPendencias(
      tester,
      RecordingTransport((request) {
        if (request.url.path.contains('receivables')) {
          return errorResponse(statusCode: 500, code: 'INTERNAL');
        }
        return jsonResponse({
          'results': [
            {'id': 77, 'name': 'João Silva', 'is_active': true},
          ],
        });
      }),
    );

    expect(find.textContaining('não deve nada'), findsNothing);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
