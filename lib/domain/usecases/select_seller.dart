import '../../core/result.dart';
import '../entities/seller.dart';
import '../entities/terminal_session.dart';
import '../repositories/auth_repository.dart';

/// Identificação do vendedor no terminal (API §2.3).
///
/// O PIN é **dele**, não do aparelho. Antes bastava tocar no nome: o que a
/// venda carimbava era quem tinha sido tocado na lista, não quem tinha provado
/// ser aquela pessoa — e com a comissão saindo do vendedor da venda (RF19),
/// nome errado é dinheiro no bolso errado.
///
/// Continua sem conceder permissão administrativa (§12 da integração): o que
/// sai daqui é o `session_token`, que só autoriza registrar venda.
class SelectSeller {
  const SelectSeller(this._auth);

  final AuthRepository _auth;

  Future<Result<SellerSession>> call({
    required Seller seller,
    required String password,
  }) =>
      _auth.selectSeller(seller: seller, password: password);
}
