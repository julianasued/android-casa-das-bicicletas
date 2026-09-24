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

  /// §2.3 — o vendedor se identifica com o PIN dele e abre a sessão.
  ///
  /// O `Seller` inteiro, e não só o id: é este nome que fica na sessão e que a
  /// venda carimba (RF06), e o repositório não tem de onde tirá-lo quando a
  /// listagem não passou por esta instância.
  Future<Result<SellerSession>> selectSeller({
    required Seller seller,
    required String password,
  });

  /// §2.6 — encerra a sessão e limpa os tokens do aparelho.
  Future<Result<void>> logout();

  /// Loja do terminal, para o cabeçalho dos documentos impressos.
  Future<Result<Store>> currentStore();
}
