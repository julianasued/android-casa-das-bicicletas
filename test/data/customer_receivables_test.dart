/// Pendências do cliente (RF15), do §3.3 da API até a entidade.
///
/// O que se confere aqui é o contrato: a rota certa, os valores em dinheiro
/// chegando sem perder centavo e o status virando algo que a tela sabe exibir —
/// inclusive um status que este aplicativo ainda não conhece.
library;

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/repositories/customer_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/receivable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Map<String, Object?> _pendencia({
  int id = 501,
  int saleId = 10482,
  String original = '1500.00',
  String paid = '0.00',
  String pending = '1500.00',
  String status = 'ABERTA',
}) =>
    {
      'id': id,
      'sale_id': saleId,
      'original_amount': original,
      'paid_amount': paid,
      'pending_amount': pending,
      'status': status,
      'created_at': '2026-08-05T14:32:00Z',
    };

void main() {
  late RecordingTransport transport;
  late CustomerRepositoryImpl repository;

  Future<void> prepare(RecordingTransport http) async {
    transport = http;
    final deps = buildTestDependencies(transport: http);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    repository = CustomerRepositoryImpl(deps.apiClient);
  }

  group('GET /customers/{id}/receivables/', () {
    test('usa a rota do cliente pedido', () async {
      await prepare(
        RecordingTransport((_) => jsonResponse({'results': <Object?>[]})),
      );

      await repository.receivables(77);

      expect(transport.lastRequest.method, 'GET');
      expect(
        transport.lastRequest.url.path,
        contains('customers/77/receivables/'),
      );
    });

    test('lê os três valores do §3.3 sem perder centavo', () async {
      await prepare(
        RecordingTransport(
          (_) => jsonResponse({
            'results': [
              _pendencia(original: '1500.00', paid: '499.99', pending: '1000.01'),
            ],
          }),
        ),
      );

      final result = await repository.receivables(77);

      expect(result, isA<Ok<List<Receivable>>>());
      final pendencia = (result as Ok<List<Receivable>>).value.single;

      expect(pendencia.id, 501);
      expect(pendencia.saleId, 10482);
      expect(pendencia.originalAmount, const Money.fromCents(150000));
      expect(pendencia.paidAmount, const Money.fromCents(49999));
      expect(pendencia.pendingAmount, const Money.fromCents(100001));
      expect(pendencia.status, ReceivableStatus.aberta);
      expect(pendencia.createdAt.toUtc().hour, 14);
    });

    test('status que o aplicativo não conhece não quebra a lista', () async {
      // O backend pode ganhar estados antes deste terminal ser atualizado.
      await prepare(
        RecordingTransport(
          (_) => jsonResponse({
            'results': [_pendencia(status: 'RENEGOCIADA_EM_CARTORIO')],
          }),
        ),
      );

      final result = await repository.receivables(77);
      final pendencia = (result as Ok<List<Receivable>>).value.single;

      expect(pendencia.status, ReceivableStatus.desconhecido);
      expect(pendencia.status.label, 'Desconhecida');
      // Desconhecido não conta como dívida: melhor omitir do total do que
      // afirmar um número errado na frente do cliente.
      expect(pendencia.status.isOutstanding, isFalse);
    });

    test('sem pendência alguma devolve lista vazia, não erro', () async {
      await prepare(
        RecordingTransport((_) => jsonResponse({'results': <Object?>[]})),
      );

      final result = await repository.receivables(77);

      expect(result, isA<Ok<List<Receivable>>>());
      expect((result as Ok<List<Receivable>>).value, isEmpty);
    });
  });

  group('resumo para o balcão', () {
    test('soma só o que ainda está devendo', () async {
      final pendencias = [
        _receivable(pending: 100000, status: ReceivableStatus.aberta),
        _receivable(pending: 50000, status: ReceivableStatus.vencida),
        // Quitada e cancelada não entram: a pergunta é quanto ele deve agora.
        _receivable(pending: 0, status: ReceivableStatus.quitada),
        _receivable(pending: 999900, status: ReceivableStatus.cancelada),
      ];

      expect(pendencias.totalOutstanding, const Money.fromCents(150000));
      expect(pendencias.outstanding, hasLength(2));
    });

    test('reconhece pendência vencida, que é o caso que importa', () {
      expect(
        [_receivable(pending: 100, status: ReceivableStatus.aberta)].hasOverdue,
        isFalse,
      );
      expect(
        [_receivable(pending: 100, status: ReceivableStatus.vencida)].hasOverdue,
        isTrue,
      );
    });

    test('cliente sem pendência tem total zero', () {
      expect(const <Receivable>[].totalOutstanding, const Money.zero());
      expect(const <Receivable>[].hasOverdue, isFalse);
    });

    test('pagamento parcial aparece como tal', () {
      expect(
        _receivable(original: 150000, paid: 50000, pending: 100000)
            .isPartiallyPaid,
        isTrue,
      );
      expect(_receivable(original: 150000, pending: 150000).isPartiallyPaid,
          isFalse);
      expect(
        _receivable(original: 150000, paid: 150000, pending: 0).isPartiallyPaid,
        isFalse,
      );
    });
  });
}

Receivable _receivable({
  int original = 150000,
  int paid = 0,
  int pending = 150000,
  ReceivableStatus status = ReceivableStatus.aberta,
}) =>
    Receivable(
      id: 1,
      saleId: 10482,
      originalAmount: Money.fromCents(original),
      paidAmount: Money.fromCents(paid),
      pendingAmount: Money.fromCents(pending),
      status: status,
      createdAt: DateTime.utc(2026, 8, 5),
    );
