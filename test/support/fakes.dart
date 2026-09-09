/// Dublês usados pelos testes.
///
/// Nenhum deles finge o domínio: o `SaleDraft`, o cálculo de totais e o layout
/// do documento são sempre os de verdade. O que se substitui aqui é a
/// fronteira — rede e hardware —, que é justamente o que não existe na máquina
/// de quem roda `flutter test`.
library;

import 'dart:convert';

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/core/env.dart';
import 'package:casa_das_bicicletas/data/remote/api_client.dart';
import 'package:casa_das_bicicletas/data/remote/http_transport.dart';
import 'package:casa_das_bicicletas/data/repositories/auth_repository_impl.dart';
import 'package:casa_das_bicicletas/data/repositories/catalog_repository_impl.dart';
import 'package:casa_das_bicicletas/data/repositories/customer_repository_impl.dart';
import 'package:casa_das_bicicletas/data/repositories/sale_repository_impl.dart';
import 'package:casa_das_bicicletas/data/session/secure_store.dart';
import 'package:casa_das_bicicletas/data/session/session_manager.dart';
import 'package:casa_das_bicicletas/domain/ports/customer_display.dart';
import 'package:casa_das_bicicletas/platform/connectivity/connectivity_channel.dart';
import 'package:casa_das_bicicletas/platform/device/device_channel.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:casa_das_bicicletas/platform/scanner/fake_barcode_scanner.dart';

/// Resposta canned para um par método/caminho.
typedef TransportHandler = HttpResponse Function(HttpRequest request);

/// Transporte que registra o que foi enviado e devolve o que o teste mandar.
class RecordingTransport implements HttpTransport {
  RecordingTransport(this.handler);

  /// Resposta 200 vazia — suficiente para os testes que só olham a requisição.
  RecordingTransport.empty()
      : handler = ((_) => const HttpResponse(statusCode: 200, body: '{}'));

  final TransportHandler handler;
  final List<HttpRequest> requests = <HttpRequest>[];

  HttpRequest get lastRequest => requests.last;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

HttpResponse jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) =>
    HttpResponse(
      statusCode: statusCode,
      body: jsonEncode(body),
      headers: headers,
    );

/// Envelope de erro do §1.4 da especificação da API.
HttpResponse errorResponse({
  required int statusCode,
  required String code,
  String message = 'Falhou.',
  Map<String, Object?> details = const <String, Object?>{},
}) =>
    jsonResponse(
      {
        'error': {'code': code, 'message': message, 'details': details},
      },
      statusCode: statusCode,
    );

/// Grafo de dependências para os testes, com rede e hardware substituídos.
AppDependencies buildTestDependencies({
  RecordingTransport? transport,
  FakeDocumentPrinter? printer,
  FakeBarcodeScanner? scanner,
  CustomerDisplay? customerDisplay,
  SecureStore? secureStore,
  String baseUrl = 'https://api.teste.local/api/v1/',
}) {
  final environment = AppEnvironment(
    apiBaseUrl: baseUrl,
    requestTimeout: const Duration(seconds: 5),
    allowInsecureHttp: false,
  );

  final store = secureStore ?? InMemorySecureStore();
  final session = SessionManager(store);
  final http = transport ?? RecordingTransport.empty();
  final api = ApiClient(environment: environment, session: session, transport: http);

  // Uma instância só: `FakeDocumentPrinter` atende os dois contratos, como a
  // `PrinterChannel` de verdade.
  final fakePrinter = printer ?? FakeDocumentPrinter();

  return AppDependencies(
    environment: environment,
    secureStore: store,
    session: session,
    transport: http,
    apiClient: api,
    auth: AuthRepositoryImpl(api: api, session: session),
    catalog: CatalogRepositoryImpl(api),
    customers: CustomerRepositoryImpl(api),
    sales: SaleRepositoryImpl(api),
    printer: fakePrinter,
    printerDiagnostics: fakePrinter,
    scanner: scanner ?? FakeBarcodeScanner(),
    customerDisplay: customerDisplay ?? FakeCustomerDisplay(),
    connectivity: ConnectivityChannel(),
    device: const DeviceChannel(),
  );
}

// ---------------------------------------------------------------------------
// Corpos de resposta reutilizados
// ---------------------------------------------------------------------------

Map<String, Object?> saleJson({
  int id = 10482,
  String uuid = '7f3a9c2b-1111-4222-8333-444455556666',
  String status = 'AGUARDANDO_CAIXA',
  bool withDocument = true,
}) {
  final sale = <String, Object?>{
    'id': id,
    'uuid': uuid,
    'store_id': 1,
    'terminal_id': 7,
    'seller_id': 12,
    'seller_name': 'João Silva',
    'customer_id': null,
    'customer_name': null,
    'status': status,
    'payment_method': 'PIX',
    'barcode': 'SALE-L1-7F3A9C2B',
    'gross_amount': '1500.00',
    'discount_amount': '0.00',
    'total_amount': '1500.00',
    'occurred_at': '2026-08-05T14:32:00Z',
    'created_offline': false,
    'items': [
      {
        'id': 1,
        'product_id': 10,
        'product_sku': 'PNEU-A15-001',
        'product_name': 'Pneu Aro 15',
        'category': 'PNEUS',
        'quantity': '2.000',
        'unit_price': '250.00',
        'discount': '0.00',
        'line_total': '500.00',
      },
      {
        'id': 2,
        'product_id': 33,
        'product_sku': 'PECA-001',
        'product_name': 'Kit de reparo',
        'category': 'PECAS',
        'quantity': '1.000',
        'unit_price': '1000.00',
        'discount': '0.00',
        'line_total': '1000.00',
      },
    ],
  };

  if (withDocument) sale['document_1'] = documentJson();
  return sale;
}

Map<String, Object?> documentJson({
  String reference = 'DOC1-L1-7F3A9C2B',
  int sequence = 1,
}) =>
    <String, Object?>{
      'reference': reference,
      'sequence': sequence,
      'is_reprint': sequence > 1,
      'printed_at': '2026-08-05T14:32:05Z',
      'printed_by_name': 'João Silva',
      'store_code': 'L1',
      'store_name': 'Casa das Bicicletas Centro',
      'store_document': '12345678000190',
      'store_address': 'Rua das Flores, 100 - Centro',
      'sale_id': 10482,
      'sale_barcode': 'SALE-L1-7F3A9C2B',
      'sale_occurred_at': '2026-08-05T14:32:00Z',
      'payment_method': 'PIX',
      'seller_id': 12,
      'seller_name': 'João Silva',
      'terminal_name': 'Caixa 1 - Loja 1',
      'customer_name': null,
      'gross_amount': '1500.00',
      'discount_amount': '0.00',
      'total_amount': '1500.00',
      'notice': 'Documento de encaminhamento ao caixa. '
          'Não é comprovante de pagamento (RF08).',
      'items': (saleJson(withDocument: false)['items']! as List<Object?>),
    };
