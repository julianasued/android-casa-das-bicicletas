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
import '../data/local/local_database.dart';
import '../data/local/operation_queue.dart';
import '../domain/repositories/sync_queue.dart';
import '../domain/rules/offline_sale_context.dart';
import '../data/repositories/sync_repository_impl.dart';
import '../domain/usecases/sync_pending_operations.dart';
import '../platform/connectivity/sync_scheduler.dart';
import '../data/local/reference_cache.dart';
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

/// Junta sessão, identidade aprendida e serialização para a venda sem rede.
///
/// Devolve `null` quando falta o que não se inventa — vendedor logado, código da
/// loja, ou identidade aprendida. Aí a falha de rede segue seu caminho, e o
/// vendedor sabe que não deu.
Future<OfflineSaleContext?> _offlineContextFrom({
  required ReferenceCache cache,
  required SessionManager session,
  required SaleRepository sales,
}) async {
  final seller = session.seller;
  final storeCode = session.storeCode;
  final storeId = session.storeId;
  if (seller == null || storeCode == null || storeId == null) return null;

  final identity = await cache.identity();
  if (identity == null) return null;

  return OfflineSaleContext(
    identity: identity,
    seller: seller,
    storeCode: storeCode,
    storeId: storeId,
    payload: sales.payloadFor,
  );
}

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
    this.syncQueue,
    this.referenceCache,
    this.syncScheduler,
  })  : openTerminal = OpenTerminal(auth),
        selectSeller = SelectSeller(auth),
        createSale = CreateSale(
          sales: sales,
          printer: printer,
          queue: syncQueue,
          // Lido na hora da venda, e não aqui: a identidade é aprendida ao longo
          // do uso, e o grafo é montado antes da primeira venda.
          offlineContext: syncQueue == null || referenceCache == null
              ? null
              : () => _offlineContextFrom(
                    cache: referenceCache,
                    session: session,
                    sales: sales,
                  ),
        ),
        reprintDocument = ReprintDocument(sales: sales, printer: printer),
        findSaleByBarcode = FindSaleByBarcode(sales);

  /// A fila de operações pendentes (RF35). Ausente nos testes que não precisam
  /// de banco, e aí a venda offline simplesmente não acontece.
  final SyncQueue? syncQueue;

  /// O cache de referência, de onde sai a identidade do terminal.
  final ReferenceCache? referenceCache;

  /// Quem manda a fila ao servidor quando a rede volta (§13.10). Ausente nos
  /// testes que não precisam de sincronização.
  final SyncScheduler? syncScheduler;

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

    // Uma instância só do banco, pela mesma razão: abrir o mesmo arquivo duas
    // vezes é como se perde transação em Android. O arquivo é aberto na
    // primeira consulta, não aqui — subir o aplicativo não deve esperar disco.
    final banco = LocalDatabase();
    final cache = ReferenceCache(banco);
    final fila = OperationQueue(banco);
    final connectivity = ConnectivityChannel();

    // A fila enche sozinha, mas não esvazia sozinha: este é o gatilho.
    final scheduler = SyncScheduler(
      connectivity: connectivity,
      sync: SyncPendingOperations(
        queue: fila,
        sync: SyncRepositoryImpl(api),
      ),
    );

    return AppDependencies(
      environment: env,
      secureStore: secureStore,
      session: session,
      transport: transport,
      apiClient: api,
      auth: AuthRepositoryImpl(api: api, session: session, cache: cache),
      catalog: CatalogRepositoryImpl(api, cache: cache),
      customers: CustomerRepositoryImpl(api, cache: cache),
      sales: SaleRepositoryImpl(api, cache: cache),
      printer: printer,
      printerDiagnostics: printer,
      scanner: ScannerChannel(),
      customerDisplay: M10CustomerDisplay(),
      connectivity: connectivity,
      device: const DeviceChannel(),
      syncQueue: fila,
      referenceCache: cache,
      syncScheduler: scheduler,
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
