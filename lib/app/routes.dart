/// Rotas do aplicativo.
///
/// Nomeadas e resolvidas em um lugar só: o fluxo do terminal é linear
/// (configuração → tela inicial → seleção do vendedor → PIN dele → venda) e
/// cada tela precisa saber para onde volta quando a sessão cai.
///
/// A tela de PIN não tem rota nomeada de propósito: ela exige um `Seller`, e
/// um argumento tipado atrás de um nome vira `null` no gerador quando o `is`
/// erra — que é a falha de rota que derruba a tela. Quem a abre é a seleção de
/// vendedor, empurrando a rota direta.
library;

class AppRoutes {
  const AppRoutes._();

  static const String bootstrap = '/';
  static const String setup = '/configuracao';

  /// Repouso do terminal: sem ninguém autenticado, uma ação só.
  static const String welcome = '/inicial';
  static const String sellerSelection = '/vendedores';
  static const String home = '/inicio';
  static const String newSale = '/venda';
  static const String saleFinished = '/venda/concluida';
  static const String scanner = '/leitor';
  static const String printerDiagnostics = '/impressora';

  /// Prova de integração com o hardware do M10, fora do fluxo de venda.
  static const String m10Poc = '/m10';
}
