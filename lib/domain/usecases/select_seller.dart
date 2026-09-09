import '../../core/result.dart';
import '../entities/terminal_session.dart';
import '../repositories/auth_repository.dart';

/// Seleção do vendedor no terminal (API §2.3).
///
/// Não pede senha e não concede permissão administrativa (§12 da integração):
/// é só o carimbo de quem responde pela venda (RF06).
class SelectSeller {
  const SelectSeller(this._auth);

  final AuthRepository _auth;

  Future<Result<SellerSession>> call(int sellerId) => _auth.selectSeller(sellerId);
}
