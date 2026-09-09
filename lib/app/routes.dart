/// Rotas do aplicativo.
///
/// Nomeadas e resolvidas em um lugar só: o fluxo do terminal é linear
/// (configuração → senha do terminal → seleção do vendedor → venda) e cada
/// tela precisa saber para onde volta quando a sessão cai.
library;

class AppRoutes {
  const AppRoutes._();

  static const String bootstrap = '/';
  static const String setup = '/configuracao';
  static const String terminalLogin = '/terminal';
  static const String sellerSelection = '/vendedores';
  static const String home = '/inicio';
  static const String newSale = '/venda';
  static const String saleFinished = '/venda/concluida';
  static const String scanner = '/leitor';
  static const String printerDiagnostics = '/impressora';

  /// Prova de integração com o hardware do M10, fora do fluxo de venda.
  static const String m10Poc = '/m10';
}
