import '../../core/result.dart';
import '../entities/product.dart';

/// Catálogo da loja (API §3.2).
abstract interface class CatalogRepository {
  /// Busca por nome, SKU ou código de barras (`?q=`).
  Future<Result<List<Product>>> searchProducts({
    String query = '',
    String? categoryCode,
  });

  /// Produto pelo código de barras lido no leitor integrado.
  Future<Result<Product?>> findByBarcode(String barcode);

  Future<Result<List<ProductCategory>>> listCategories();
}
