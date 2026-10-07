import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/remote/api_client.dart';
import 'package:casa_das_bicicletas/data/remote/http_transport.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late RecordingTransport transport;
  late ApiClient api;

  Future<void> configure({bool authenticated = true}) async {
    final deps = buildTestDependencies(transport: transport);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

    if (authenticated) {
      await deps.session.saveSession(
        SellerSession(
          sessionToken: 'token-de-sessao',
          seller: const Seller(id: 12, name: 'João Silva'),
          storeId: 1,
          terminalId: 7,
          expiresAt: DateTime.now().add(const Duration(hours: 8)),
        ),
      );
    }
    api = deps.apiClient;
  }

  group('cabeçalhos obrigatórios (§1.2)', () {
    test('envia loja, dispositivo, hora do cliente e Bearer', () async {
      transport = RecordingTransport.empty();
      await configure();

      await api.get('products/');

      final headers = transport.lastRequest.headers;
      expect(headers['X-Store-Id'], '1');
      expect(headers['X-Device-Id'], 'M10-0001');
      expect(headers['Authorization'], 'Bearer token-de-sessao');
      expect(headers['X-Client-Timestamp'], isNotNull);
    });

    test('rotas de autenticação vão sem X-Store-Id', () async {
      transport = RecordingTransport.empty();
      await configure(authenticated: false);

      await api.post('auth/terminal/', body: const {}, requiresStore: false);

      expect(transport.lastRequest.headers.containsKey('X-Store-Id'), isFalse);
    });

    test('a sessão do vendedor tem precedência sobre o token do terminal', () async {
      transport = RecordingTransport.empty();
      final deps = buildTestDependencies(transport: transport);

      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
      await deps.session.saveTerminal(
        TerminalAuth(
          terminalToken: 'token-do-terminal',
          terminalId: 7,
          storeId: 1,
          expiresAt: DateTime.now().add(const Duration(hours: 12)),
        ),
      );

      await deps.apiClient.get('products/');
      expect(
        transport.lastRequest.headers['Authorization'],
        'Bearer token-do-terminal',
        reason: 'sem vendedor selecionado, vale o token do aparelho',
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

      await deps.apiClient.get('products/');
      expect(
        transport.lastRequest.headers['Authorization'],
        'Bearer token-de-sessao',
      );
    });
  });

  group('idempotência (§1.5)', () {
    test('POST com chave leva X-Idempotency-Key', () async {
      transport = RecordingTransport.empty();
      await configure();

      await api.post('sales/', body: const {}, idempotencyKey: 'chave-1');

      expect(transport.lastRequest.headers['X-Idempotency-Key'], 'chave-1');
    });

    test('POST sem chave não inventa uma', () async {
      transport = RecordingTransport.empty();
      await configure();

      await api.post('sales/10482/document-1/print/');

      expect(
        transport.lastRequest.headers.containsKey('X-Idempotency-Key'),
        isFalse,
        reason: 'reimpressão precisa gerar via nova, não repetir a anterior',
      );
    });

    test('reconhece a resposta guardada pelo cabeçalho de replay', () async {
      transport = RecordingTransport(
        (_) => jsonResponse(
          const {'id': 1},
          headers: const {'x-idempotent-replay': 'true'},
        ),
      );
      await configure();

      final result = await api.post('sales/', idempotencyKey: 'chave-1');

      expect((result as Ok<ApiResponse>).value.isIdempotentReplay, isTrue);
    });
  });

  group('envelope de erro (§1.4)', () {
    test('401 vira sessão expirada', () async {
      transport = RecordingTransport(
        (_) => errorResponse(statusCode: 401, code: 'UNAUTHENTICATED'),
      );
      await configure();

      final result = await api.get('sales/');
      expect(result.failureOrNull, isA<UnauthenticatedFailure>());
    });

    test('403 vira falha de permissão com a mensagem do servidor', () async {
      transport = RecordingTransport(
        (_) => errorResponse(
          statusCode: 403,
          code: 'PERMISSION_DENIED',
          message: 'Perfil sem permissão.',
        ),
      );
      await configure();

      final failure = (await api.get('commissions/')).failureOrNull;
      expect(failure, isA<PermissionFailure>());
      expect(failure!.message, 'Perfil sem permissão.');
    });

    test('422 preserva código e detalhes por campo', () async {
      transport = RecordingTransport(
        (_) => errorResponse(
          statusCode: 422,
          code: 'INVALID_STATE_TRANSITION',
          message: 'Venda já confirmada.',
          details: const {'status': 'PAGA'},
        ),
      );
      await configure();

      final failure = (await api.post('sales/1/cancel/')).failureOrNull;
      expect(failure, isA<ApiFailure>());

      final apiFailure = failure! as ApiFailure;
      expect(apiFailure.isInvalidTransition, isTrue);
      expect(apiFailure.details, const {'status': 'PAGA'});
    });

    test('corpo vazio em erro ainda produz mensagem utilizável', () async {
      transport = RecordingTransport(
        (_) => const HttpResponse(statusCode: 500, body: ''),
      );
      await configure();

      final failure = (await api.get('sales/')).failureOrNull;
      expect(failure, isA<ApiFailure>());
      expect(failure!.message, isNotEmpty);
    });
  });

  test('recusa endereço sem HTTPS antes de abrir conexão (RNF01)', () async {
    transport = RecordingTransport.empty();
    final deps = buildTestDependencies(
      transport: transport,
      baseUrl: 'http://api.insegura.local/api/v1/',
    );
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);

    final result = await deps.apiClient.get('products/');

    expect(result.failureOrNull, isA<ConfigurationFailure>());
    expect(transport.requests, isEmpty, reason: 'nada pode sair em texto claro');
  });
}
