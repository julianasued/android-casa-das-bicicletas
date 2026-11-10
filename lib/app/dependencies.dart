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
import '../domain/entities/terminal_identity.dart';
import '../domain/rules/offline_sale_context.dart';
import '../data/repositories/sync_repository_impl.dart';
import '../domain/usecases/pull_reference_data.dart';
import '../domain/usecases/sync_pending_operations.dart';
import '../platform/connectivity/sync_scheduler.dart';
import '../data/local/reference_cache.dart';
import '../data/remote/api_client.dart';
import '../data/remote/http_transport.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/catalog_repository_impl.dart';
import '../data/repositories/customer_repository_impl.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../data/session/offline_pin_store.dart';
import '../data/session/secure_store.dart';
import '../data/session/session_manager.dart';
import '../domain/ports/barcode_scanner.dart';
import '../domain/ports/customer_display.dart';
import '../domain/ports/document_printer.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/customer_repository.dart';
import '../domain/repositories/sale_repository.dart';
import '../domain/usecases/cancel_own_sale.dart';
import '../domain/usecases/check_payment.dart';
import '../domain/usecases/create_sale.dart';
import '../domain/usecases/find_sale_by_barcode.dart';
import '../domain/usecases/open_terminal.dart';
import '../domain/usecases/receive_offline_payment.dart';
import '../domain/usecases/reprint_document.dart';
import '../domain/usecases/select_seller.dart';
import '../platform/connectivity/connectivity_channel.dart';
import '../platform/connectivity/offline_mode.dart';
import '../platform/device/device_channel.dart';
import '../platform/display/customer_display_channel.dart';
import '../platform/printer/printer_channel.dart';
import '../platform/printer/printer_diagnostics.dart';
import '../platform/scanner/scanner_channel.dart';
import '../platform/secure_store/secure_store_channel.dart';

/// Junta sessão, identidade aprendida e serialização para a venda sem rede.
///
/// Devolve `null` quando falta o que não se inventa — vendedor logado ou loja
/// configurada. Sem identidade aprendida (nome, CNPJ, endereço), a venda segue
/// mesmo assim: o documento sai com o código da loja.
Future<OfflineSaleContext?> _offlineContextFrom({
  required ReferenceCache cache,
  required SessionManager session,
  required SaleRepository sales,
}) async {
  final seller = session.seller;
  final storeCode = session.storeCode;
  final storeId = session.storeId;
  if (seller == null || storeCode == null || storeId == null) return null;

  final identity = await cache.identity() ??
      TerminalIdentity(storeCode: storeCode, learnedAt: DateTime.now());

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
    this.offlineMode,
    bool receiveAtTerminalWhenOffline = false,
  })  : openTerminal = OpenTerminal(auth),
        receiveOfflinePayment = syncQueue == null || !receiveAtTerminalWhenOffline
            ? null
            : ReceiveOfflinePayment(queue: syncQueue, printer: printer),
        selectSeller = SelectSeller(auth),
        createSale = CreateSale(
          sales: sales,
          printer: printer,
          queue: syncQueue,
          // Lido na hora da venda, e não aqui: a identidade é aprendida ao longo
          // do uso, e o grafo é montado antes da primeira venda.
          // Recebendo no PDV, o papel da venda offline espera a escolha do
          // vendedor: comprovante de retirada ou encaminhamento ao caixa.
          holdOfflineDocument: receiveAtTerminalWhenOffline && syncQueue != null,
          offlineContext: syncQueue == null || referenceCache == null
              ? null
              : () => _offlineContextFrom(
                    cache: referenceCache,
                    session: session,
                    sales: sales,
                  ),
        ),
        reprintDocument = ReprintDocument(sales: sales, printer: printer),
        findSaleByBarcode = FindSaleByBarcode(sales),
        checkPayment = CheckPayment(sales),
        cancelOwnSale = CancelOwnSale(sales);

  /// Recebimento no próprio PDV quando não há internet. Ausente sem fila.
  final ReceiveOfflinePayment? receiveOfflinePayment;

  /// A fila de operações pendentes (RF35). Ausente nos testes que não precisam
  /// de banco, e aí a venda offline simplesmente não acontece.
  final SyncQueue? syncQueue;

  /// O cache de referência, de onde sai a identidade do terminal.
  final ReferenceCache? referenceCache;

  /// Quem manda a fila ao servidor quando a rede volta (§13.10). Ausente nos
  /// testes que não precisam de sincronização.
  final SyncScheduler? syncScheduler;

  /// Modo offline: com ele ligado, nada vai ao servidor (ver `OfflineMode`).
  /// Ausente nos testes que não tratam disso — aí o app sempre tenta a rede.
  final OfflineMode? offlineMode;

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
    // O cache é escopado pela loja do terminal: reconfigurar o aparelho para
    // outra loja não pode deixar o catálogo e os clientes da anterior
    // aparecendo na busca offline.
    final cache = ReferenceCache(banco, lojaAtual: () => session.storeId);
    final fila = OperationQueue(banco);
    final connectivity = ConnectivityChannel();

    // Ligado, nada sai para a rede: cada ação vai direto ao aparelho, na hora,
    // em vez de esperar o tempo-limite de uma internet que caiu.
    final modoOffline = OfflineMode(connectivity: connectivity, store: secureStore);
    api
      ..forcedOffline = (() => modoOffline.isOffline)
      ..onNetworkFailure = modoOffline.reportNetworkFailure;
    modoOffline.probe = api.isServerReachable;

    // A fila enche sozinha, mas não esvazia sozinha: este é o gatilho.
    final sincronizacao = SyncRepositoryImpl(api);
    final scheduler = SyncScheduler(
      connectivity: connectivity,
      sync: SyncPendingOperations(
        queue: fila,
        sync: sincronizacao,
      ),
      // Mesma janela de rede do envio: é o `pull` que corrige o cache, porque a
      // busca online filtra ativos e nunca traria de volta um produto
      // desativado no servidor (RF34).
      pull: PullReferenceData(sync: sincronizacao, cache: cache),
      offlineMode: modoOffline,
    );

    // A senha conferida no aparelho quando não há internet, e a troca dessa
    // sessão por uma do servidor quando a rede volta.
    final auth = AuthRepositoryImpl(
      api: api,
      session: session,
      cache: cache,
      offlinePins: OfflinePinStore(secureStore),
    );
    session.renewer = auth.renewOfflineSession;

    return AppDependencies(
      environment: env,
      secureStore: secureStore,
      session: session,
      transport: transport,
      apiClient: api,
      auth: auth,
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
      receiveAtTerminalWhenOffline: true,
      offlineMode: modoOffline,
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

  /// Confere se o caixa já recebeu a venda — leitura, nunca recebimento.
  final CheckPayment checkPayment;
  final CancelOwnSale cancelOwnSale;

  void dispose() {
    transport.close();
    offlineMode?.dispose();
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
    final scope = context.dependOnInheritedWidgetOfExactType<DependenciesScope>();
    assert(scope != null, 'DependenciesScope ausente acima deste widget.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(DependenciesScope oldWidget) => oldWidget.dependencies != dependencies;
}

extension DependenciesContext on BuildContext {
  AppDependencies get deps => DependenciesScope.of(this);
}
