/// Localização da venda pelo código lido (RF09).
///
/// A leitura vem do leitor integrado; o caixa não digita número de venda
/// nenhum. Um código que não tem a forma de código de venda falha aqui, sem ir
/// à rede — o leitor pega qualquer etiqueta que apareça na frente dele,
/// inclusive a do produto.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../entities/barcode_read.dart';
import '../entities/sale.dart';
import '../repositories/sale_repository.dart';

class FindSaleByBarcode {
  const FindSaleByBarcode(this._sales);

  final SaleRepository _sales;

  Future<Result<Sale>> call(BarcodeRead read) {
    if (!read.looksLikeSaleBarcode) {
      return Future.value(
        Err(
          ScannerFailure(
            'O código lido não é de uma venda: "${read.code}".',
          ),
        ),
      );
    }
    return _sales.findByBarcode(read.code.toUpperCase());
  }
}
