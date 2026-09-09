/// Transporte HTTP mínimo, atrás de uma interface.
///
/// A interface existe para o teste: o `ApiClient` carrega as regras que
/// importam — cabeçalhos obrigatórios (§1.2), idempotência (§1.5), envelope de
/// erro (§1.4) — e todas elas podem ser verificadas sem abrir socket nenhum.
///
/// A implementação usa o `HttpClient` do `dart:io` em vez de um pacote de
/// terceiros: o aplicativo faz requisições JSON simples, e um pacote a menos é
/// uma atualização a menos para empurrar a um terminal que fica meses no
/// balcão sem ninguém mexer.
library;

import 'dart:convert';
import 'dart:io';

class HttpRequest {
  const HttpRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Object? body;
}

class HttpResponse {
  const HttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// `true` quando o servidor devolveu a resposta guardada (§1.5).
  bool get isIdempotentReplay =>
      headers['x-idempotent-replay']?.toLowerCase() == 'true';
}

abstract interface class HttpTransport {
  Future<HttpResponse> send(HttpRequest request);

  void close();
}

class IoHttpTransport implements HttpTransport {
  IoHttpTransport({required this.timeout}) : _client = HttpClient() {
    _client.connectionTimeout = timeout;
  }

  final Duration timeout;
  final HttpClient _client;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final connection = await _client.openUrl(request.method, request.url);

    request.headers.forEach(
      (name, value) => connection.headers.set(name, value),
    );
    if (request.body != null) {
      connection.headers.contentType = ContentType.json;
      connection.write(jsonEncode(request.body));
    }

    final response = await connection.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join();

    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });

    return HttpResponse(
      statusCode: response.statusCode,
      body: body,
      headers: headers,
    );
  }

  @override
  void close() => _client.close(force: true);
}
