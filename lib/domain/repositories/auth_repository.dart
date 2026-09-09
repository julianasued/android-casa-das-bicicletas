import '../../core/result.dart';
import '../entities/seller.dart';
import '../entities/store.dart';
import '../entities/terminal_session.dart';

/// Autenticação do terminal e seleção do vendedor (API §2.1–§2.3).
///
/// Contrato no domínio, implementação nos dados: quem chama não sabe se o token
/// veio da rede ou do armazenamento seguro do aparelho.
abstract interface class AuthRepository {
  /// §2.1 — autentica o dispositivo com a senha do terminal.
  Future<Result<TerminalAuth>> authenticateTerminal({
    required int storeId,
    required String terminalPassword,
  });

  /// §2.2 — vendedores habilitados neste terminal.
  Future<Result<List<Seller>>> listTerminalSellers();

  /// §2.3 — seleciona o vendedor e abre a sessão de venda.
  Future<Result<SellerSession>> selectSeller(int sellerId);

  /// §2.6 — encerra a sessão e limpa os tokens do aparelho.
  Future<Result<void>> logout();

  /// Loja do terminal, para o cabeçalho dos documentos impressos.
  Future<Result<Store>> currentStore();
}
