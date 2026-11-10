/// O vendedor cancela a própria venda no M10 (09/11/2026).
///
/// Substitui o "conferir pagamento" na tela da venda finalizada: o cliente
/// desistiu ou a venda saiu errada, e o vendedor resolve ali mesmo, sem PIN —
/// enquanto a venda ainda aguarda o caixa. Depois de paga, o servidor recusa e
/// o cancelamento é no computador, com o PIN do Dono ou do Gerente.
library;

import '../../core/result.dart';
import '../repositories/sale_repository.dart';

class CancelOwnSale {
  const CancelOwnSale(this._sales);

  final SaleRepository _sales;

  Future<Result<void>> call(int saleId, {required String reason}) =>
      _sales.cancelOwn(saleId, reason: reason.trim());
}
