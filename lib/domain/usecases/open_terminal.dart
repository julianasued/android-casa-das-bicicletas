/// Abertura do terminal: autenticar o dispositivo e listar quem pode vender.
///
/// As duas coisas são um passo só na prática — a tela de senha existe para
/// chegar à tela de seleção — mas continuam separadas na API (§2.1 e §2.2)
/// porque são identidades diferentes: uma autentica, a outra apenas seleciona.
library;

import '../../core/result.dart';
import '../entities/seller.dart';
import '../repositories/auth_repository.dart';

class OpenTerminal {
  const OpenTerminal(this._auth);

  final AuthRepository _auth;

  Future<Result<List<Seller>>> call({
    required int storeId,
    required String terminalPassword,
  }) async {
    final authenticated = await _auth.authenticateTerminal(
      storeId: storeId,
      terminalPassword: terminalPassword,
    );

    return switch (authenticated) {
      Err(:final failure) => Err(failure),
      Ok() => await _auth.listTerminalSellers(),
    };
  }
}
