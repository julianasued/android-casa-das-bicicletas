import '../../core/money.dart';

/// Categoria usada no cálculo de comissão (RF04/RF17).
///
/// O terminal a exibe e a envia como código (`PNEUS`), mas **não** conhece
/// percentual nenhum: comissão é sigilo do dono (RF18/RNF03) e o `/sync/pull/`
/// não a envia ao dispositivo.
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  final int id;
  final String code;
  final String name;
  final bool isActive;
}

/// Produto do catálogo da loja (RF04). Sem estoque: identificação e preço.
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.categoryCode,
    required this.categoryName,
    required this.price,
    this.barcode,
    this.isActive = true,
  });

  final int id;
  final String sku;
  final String name;
  final String categoryCode;
  final String categoryName;
  final Money price;

  /// Código de barras do produto — o leitor do M10 também serve para montar a
  /// venda, não só para o caixa localizar a venda pronta.
  final String? barcode;

  final bool isActive;
}
