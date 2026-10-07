import 'seller.dart';

/// Autenticação do dispositivo (API §2.1).
///
/// Identifica loja + terminal, e só. Não autoriza venda: para isso é preciso o
/// token de sessão, que carrega também o vendedor.
class TerminalAuth {
  const TerminalAuth({
    required this.terminalToken,
    required this.terminalId,
    required this.storeId,
    required this.expiresAt,
  });

  final String terminalToken;
  final int terminalId;
  final int storeId;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Sessão de venda: terminal + vendedor selecionado (API §2.3).
class SellerSession {
  const SellerSession({
    required this.sessionToken,
    required this.seller,
    required this.storeId,
    required this.terminalId,
    required this.expiresAt,
  });

  final String sessionToken;
  final Seller seller;
  final int storeId;
  final int terminalId;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
