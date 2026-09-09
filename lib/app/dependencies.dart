/// Injeção de dependências do aplicativo.
///
/// Um objeto montado uma vez no arranque e distribuído pela árvore de widgets.
/// Não há contêiner de terceiros nem localizador de serviço global: as
/// dependências são poucas, o grafo é conhecido em tempo de compilação e um
/// `InheritedWidget` resolve isso sem esconder de onde cada coisa vem — o que
/// importa quando alguém for trocar SQLite ou cliente HTTP na Sprint 9.
library;

import 'package:flutter/widgets.dart';

import '../core/env.dart';
import '../data/remote/api_client.dart';
import '../data/remote/http_transport.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/catalog_repository_impl.dart';
import '../data/repositories/customer_repository_impl.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../data/session/secure_store.dart';
import '../data/session/session_manager.dart';
import '../domain/ports/barcode_scanner.dart';
import '../domain/ports/customer_display.dart';
import '../domain/ports/document_printer.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/customer_repository.dart';
import '../domain/repositories/sale_repository.dart';
import '../domain/usecases/create_sale.dart';
import '../domain/usecases/find_sale_by_barcode.dart';
import '../domain/usecases/open_terminal.dart';
import '../domain/usecases/reprint_document.dart';
import '../domain/usecases/select_seller.dart';
import '../platform/connectivity/connectivity_channel.dart';
import '../platform/device/device_channel.dart';
import '../platform/display/customer_display_channel.dart';
import '../platform/printer/printer_channel.dart';
import '../platform/printer/printer_diagnostics.dart';
import '../platform/scanner/scanner_channel.dart';
import '../platform/secure_store/secure_store_channel.dart';

class AppDependencies {
  AppDependencies({
    required this.environment,
    required this.secureStore,
    required this.session,
    required this.transport,
    required this.apiClient,
    required this.auth,
    required this.catalog,
    required this.customers,
    required this.sales,
    required this.printer,
    required this.printerDiagnostics,
    required this.scanner,
    required this.customerDisplay,
    required this.connectivity,
    required this.device,
  })  : openTerminal = OpenTerminal(auth),
        selectSeller = SelectSeller(auth),
        createSale = CreateSale(sales: sales, printer: printer),
        reprintDocument = ReprintDocument(sales: sales, printer: printer),
        findSaleByBarcode = FindSaleByBarcode(sales);

  /// Grafo real do terminal: canais nativos e HTTP de verdade.
  factory AppDependencies.production({AppEnvironment? environment}) {
    final env = environment ?? AppEnvironment.fromDefines();
    final secureStore = SecureStoreChannel();
    final session = SessionManager(secureStore);
    final transport = IoHttpTransport(timeout: env.requestTimeout);
    final api = ApiClient(environment: env, session: session, transport: transport);

    // Uma instância só da impressora: é um aparelho só, e duas conexões
    // concorrentes ao mesmo SDK é problema que não precisa existir.
    final printer = PrinterChannel();

    return AppDependencies(
      environment: env,
      secureStore: secureStore,
      session: session,
      transport: transport,
      apiClient: api,
      auth: AuthRepositoryImpl(api: api, session: session),
      catalog: CatalogRepositoryImpl(api),
      customers: CustomerRepositoryImpl(api),
      sales: SaleRepositoryImpl(api),
      printer: printer,
      printerDiagnostics: printer,
      scanner: ScannerChannel(),
      customerDisplay: M10CustomerDisplay(),
      connectivity: ConnectivityChannel(),
      device: const DeviceChannel(),
    );
  }

  final AppEnvironment environment;
  final SecureStore secureStore;
  final SessionManager session;
  final HttpTransport transport;
  final ApiClient apiClient;

  final AuthRepository auth;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final SaleRepository sales;

  final DocumentPrinter printer;

  /// Mesma impressora, pelo contrato de diagnóstico — é o que a tela do POC usa.
  final PrinterDiagnostics printerDiagnostics;

  final BarcodeScanner scanner;
  final CustomerDisplay customerDisplay;
  final ConnectivityChannel connectivity;
  final DeviceChannel device;

  final OpenTerminal openTerminal;
  final SelectSeller selectSeller;
  final CreateSale createSale;
  final ReprintDocument reprintDocument;
  final FindSaleByBarcode findSaleByBarcode;

  void dispose() {
    transport.close();
    connectivity.dispose();
    session.dispose();
  }
}

/// Disponibiliza o grafo para a árvore de widgets.
class DependenciesScope extends InheritedWidget {
  const DependenciesScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DependenciesScope>();
    assert(scope != null, 'DependenciesScope ausente acima deste widget.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(DependenciesScope oldWidget) =>
      oldWidget.dependencies != dependencies;
}

extension DependenciesContext on BuildContext {
  AppDependencies get deps => DependenciesScope.of(this);
}
