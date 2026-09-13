/// Rotas da API v1 (`config/api_urls.py` do backend).
///
/// Centralizadas para que uma mudança de contrato apareça em um arquivo só, e
/// não espalhada por repositórios.
class ApiEndpoints {
  const ApiEndpoints._();

  // §2 — autenticação e sessão
  static const String terminalAuth = 'auth/terminal/';
  static const String terminalSellers = 'auth/terminal/sellers/';
  static const String selectSeller = 'auth/select-seller/';
  static const String logout = 'auth/logout/';

  // §3.1 a §3.4
  static const String stores = 'stores/';
  static const String products = 'products/';
  static const String productCategories = 'product-categories/';
  static const String customers = 'customers/';
  static const String sales = 'sales/';

  /// Envia o lote de operações feitas offline (RF33–RF37, API §3.9).
  static const String syncPush = 'sync/push/';

  static String store(int id) => 'stores/$id/';
  static String sale(int id) => 'sales/$id/';
  /// Pendências do cliente (RF15). O vendedor pode consultar.
  static String customerReceivables(int customerId) =>
      'customers/$customerId/receivables/';

  static String saleByBarcode(String barcode) => 'sales/by-barcode/$barcode/';
  static String printDocument1(int saleId) => 'sales/$saleId/document-1/print/';
  static String printDocument2(int saleId) => 'sales/$saleId/document-2/print/';
}
