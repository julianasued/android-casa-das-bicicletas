/// Cliente da API v1.
///
/// Concentra o que o §1 da especificação da API exige de **toda** requisição:
/// o Bearer certo para a identidade atual (§1.1), os cabeçalhos de loja,
/// dispositivo e hora do cliente (§1.2), a chave de idempotência nos POSTs que
/// criam recurso (§1.5) e a leitura do envelope de erro padrão (§1.4).
///
/// Nenhum repositório monta cabeçalho por conta própria. Esquecer o
/// `X-Idempotency-Key` num POST significa venda duplicada quando a rede cair no
/// meio — não é o tipo de detalhe que se deixa para cada chamada lembrar.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/env.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../core/uuid.dart';
import '../session/session_manager.dart';
import 'api_endpoints.dart';
import 'http_transport.dart';

/// Corpo JSON já decodificado, com o status da resposta.
class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.data,
    required this.isIdempotentReplay,
  });

  final int statusCode;
  final Map<String, Object?> data;
  final bool isIdempotentReplay;
}

class ApiClient {
  ApiClient({
    required AppEnvironment environment,
    required SessionManager session,
    required HttpTransport transport,
  })  : _environment = environment,
        _session = session,
        _transport = transport;

  final AppEnvironment _environment;
  final SessionManager _session;
  final HttpTransport _transport;

  /// URL efetiva: a configurada no terminal tem precedência sobre a compilada.
  String get baseUrl {
    final override = _session.baseUrlOverride;
    final url = (override == null || override.isEmpty)
        ? _environment.apiBaseUrl
        : override;
    return url.endsWith('/') ? url : '$url/';
  }

  Future<Result<ApiResponse>> get(
    String path, {
    Map<String, String>? query,
    bool requiresStore = true,
  }) =>
      _send('GET', path, query: query, requiresStore: requiresStore);

  /// O servidor daquele endereço responde?
  ///
  /// Serve à tela de configuração, que precisa saber se o endereço digitado
  /// leva a algum lugar **antes** de gravá-lo — um erro de digitação ali deixa
  /// o terminal sem conseguir abrir, e quem descobre é o balcão.
  ///
  /// Só isso: conexão, não credencial. `401` é resposta — o servidor está lá e
  /// recusou por falta de token, que é o esperado nesta altura. O que reprova é
  /// não chegar: rede fora, DNS errado, certificado inválido, tempo esgotado.
  ///
  /// Não usa `baseUrl` de propósito: o endereço ainda não foi salvo, e é
  /// justamente ele que está sendo testado.
  Future<Result<void>> probe(String baseUrl) async {
    final normalizada = baseUrl.trim().endsWith('/')
        ? baseUrl.trim()
        : '${baseUrl.trim()}/';

    if (_environment.violatesTransportSecurity(normalizada)) {
      return const Err(
        ConfigurationFailure('A comunicação com a API exige HTTPS (RNF01).'),
      );
    }

    final Uri url;
    try {
      url = Uri.parse('$normalizada${ApiEndpoints.stores}');
    } on FormatException {
      return const Err(ConfigurationFailure('Endereço da API inválido.'));
    }
    if (!url.hasAuthority) {
      return const Err(ConfigurationFailure('Endereço da API inválido.'));
    }

    try {
      await _transport
          .send(HttpRequest(
            method: 'GET',
            url: url,
            headers: const {'Accept': 'application/json'},
          ))
          .timeout(_environment.requestTimeout);
      return const Ok(null);
    } on TimeoutException {
      return const Err(
        NetworkFailure('O servidor demorou a responder. Confira o endereço.'),
      );
    } on SocketException {
      return const Err(NetworkFailure());
    } on HandshakeException {
      return const Err(
        NetworkFailure('Falha na conexão segura com o servidor (certificado).'),
      );
    } on HttpException catch (error) {
      return Err(NetworkFailure('Falha de comunicação: ${error.message}'));
    }
  }

  /// POST de criação: leva `X-Idempotency-Key` salvo indicação em contrário.
  ///
  /// A chave é passada pelo chamador quando a operação precisa sobreviver a uma
  /// nova tentativa — reenviar a **mesma** chave é o que faz o servidor
  /// devolver a resposta original em vez de criar outra venda (§1.5).
  Future<Result<ApiResponse>> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool requiresStore = true,
    DateTime? occurredAt,
  }) =>
      _send(
        'POST',
        path,
        body: body ?? const <String, Object?>{},
        idempotencyKey: idempotencyKey,
        requiresStore: requiresStore,
        occurredAt: occurredAt,
      );

  Future<Result<ApiResponse>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? idempotencyKey,
    bool requiresStore = true,
    DateTime? occurredAt,
  }) async {
    final Uri url;
    try {
      url = Uri.parse('$baseUrl$path').replace(
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );
    } on FormatException {
      return const Err(
        ConfigurationFailure('Endereço da API inválido. Revise a configuração do terminal.'),
      );
    }

    if (_environment.violatesTransportSecurity(url.toString())) {
      // RNF01 — a checagem é local de propósito: um endereço `http://` digitado
      // por engano na configuração mandaria o token do terminal em texto claro.
      return const Err(
        ConfigurationFailure('A comunicação com a API exige HTTPS (RNF01).'),
      );
    }

    final headers = _headers(
      method: method,
      idempotencyKey: idempotencyKey,
      requiresStore: requiresStore,
      occurredAt: occurredAt,
    );

    try {
      final response = await _transport
          .send(HttpRequest(method: method, url: url, headers: headers, body: body))
          .timeout(_environment.requestTimeout);
      return _interpret(response);
    } on TimeoutException {
      return const Err(
        NetworkFailure('O servidor demorou a responder. A operação não foi concluída.'),
      );
    } on SocketException {
      return const Err(NetworkFailure());
    } on HandshakeException {
      return const Err(
        NetworkFailure('Falha na conexão segura com o servidor (certificado).'),
      );
    } on HttpException catch (error) {
      return Err(NetworkFailure('Falha de comunicação: ${error.message}'));
    }
  }

  Map<String, String> _headers({
    required String method,
    String? idempotencyKey,
    required bool requiresStore,
    DateTime? occurredAt,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      // §1.2 — a hora do evento é a do balcão. Vale para a venda feita agora e
      // valerá para a que ficou na fila até a rede voltar (RF37).
      'X-Client-Timestamp': formatIsoTimestamp(occurredAt ?? DateTime.now()),
    };

    final token = _session.bearerToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final deviceId = _session.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) headers['X-Device-Id'] = deviceId;

    final storeId = _session.storeId;
    if (requiresStore && storeId != null) {
      headers['X-Store-Id'] = storeId.toString();
    }

    if (method == 'POST' && idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }

    return headers;
  }

  Result<ApiResponse> _interpret(HttpResponse response) {
    final data = _decodeBody(response.body);

    if (response.isSuccess) {
      return Ok(
        ApiResponse(
          statusCode: response.statusCode,
          data: data,
          isIdempotentReplay: response.isIdempotentReplay,
        ),
      );
    }

    return Err(_failureFrom(response.statusCode, data));
  }

  Map<String, Object?> _decodeBody(String body) {
    if (body.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
      // Listas simples (`/auth/terminal/sellers/` devolve objeto, mas nem toda
      // rota devolveria) chegam embrulhadas para o chamador não ter dois casos.
      return <String, Object?>{'results': decoded};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  /// Traduz o envelope `{"error": {...}}` do §1.4 para uma falha do domínio.
  Failure _failureFrom(int statusCode, Map<String, Object?> data) {
    final error = data['error'];
    final envelope = error is Map<String, Object?> ? error : const <String, Object?>{};

    final code = (envelope['code'] as String?) ?? _codeForStatus(statusCode);
    final message = (envelope['message'] as String?) ?? _messageForStatus(statusCode);
    final details = envelope['details'] is Map<String, Object?>
        ? envelope['details']! as Map<String, Object?>
        : null;

    return switch (statusCode) {
      401 => const UnauthenticatedFailure(),
      403 => PermissionFailure(message),
      404 => NotFoundFailure(message),
      _ => ApiFailure(
          code: code,
          message: message,
          statusCode: statusCode,
          details: details,
        ),
    };
  }

  String _codeForStatus(int statusCode) => switch (statusCode) {
        400 => 'VALIDATION_ERROR',
        409 => 'CONFLICT',
        422 => 'INVALID_STATE_TRANSITION',
        429 => 'RATE_LIMITED',
        >= 500 => 'INTERNAL_ERROR',
        _ => 'VALIDATION_ERROR',
      };

  String _messageForStatus(int statusCode) => switch (statusCode) {
        >= 500 => 'O servidor não conseguiu concluir a operação. Tente novamente.',
        429 => 'Excesso de requisições. Aguarde alguns instantes.',
        _ => 'Não foi possível concluir a operação.',
      };

  /// Chave nova para uma tentativa nova de criação (§1.5).
  static String newIdempotencyKey() => generateUuidV4();
}
