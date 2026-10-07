/// Confere, no servidor, se o caixa já recebeu a venda (RF10–RF12).
///
/// É **leitura**, e isso é o ponto. O terminal do vendedor não recebe
/// pagamento: quem recebe é o caixa, em outra estação, com permissão própria
/// (`POST /cash/payments/`). Aqui nada grava — nem venda, nem recebimento, nem
/// documento. Conferir dez vezes seguidas tem o mesmo efeito de conferir
/// nenhuma, que é o que permite o vendedor consultar com o cliente no balcão
/// sem risco de duplicar coisa alguma.
///
/// Usa `GET /sales/{id}/`: o vendedor já tem `sale.view`, e o recorte por
/// perfil da rota o limita às próprias vendas. Pelo código de barras seria
/// `sale.find_by_barcode`, que é permissão de caixa — o vendedor leva 403.
library;

import '../../core/result.dart';
import '../entities/sale.dart';
import '../repositories/sale_repository.dart';

class CheckPayment {
  const CheckPayment(this._sales);

  final SaleRepository _sales;

  Future<Result<Sale>> call(int saleId) => _sales.findById(saleId);
}
