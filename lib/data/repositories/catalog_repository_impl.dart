/// Catálogo da loja (API §3.2).
///
/// A busca vai ao servidor a cada consulta. Cache local de catálogo é assunto
/// da Sprint 9 (`GET /sync/pull/`): implementá-lo agora significaria manter
/// duas fontes de verdade antes de existir a fila que as reconcilia.
library;

import '../../core/result.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  const CatalogRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<Product>>> searchProducts({
    String query = '',
    String? categoryCode,
  }) async {
    final response = await _api.get(
      ApiEndpoints.products,
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (categoryCode != null && categoryCode.isNotEmpty) 'category': categoryCode,
        'is_active': 'true',
        'ordering': 'name',
        'page_size': '50',
      },
    );

    return mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) productFromJson(item),
      ],
    );
  }

  @override
  Future<Result<Product?>> findByBarcode(String barcode) async {
    // `?q=` procura em nome, SKU e código de barras (`search_fields` da view);
    // a conferência exata acontece aqui, porque a busca é textual e traria o
    // produto cujo SKU apenas contém o código lido.
    final response = await searchProducts(query: barcode);

    return response.map((products) {
      for (final product in products) {
        if (product.barcode == barcode) return product;
      }
      return null;
    });
  }

  @override
  Future<Result<List<ProductCategory>>> listCategories() async {
    final response = await _api.get(
      ApiEndpoints.productCategories,
      query: const {'is_active': 'true'},
      // A categoria não pertence a uma loja: a matriz de comissão é vendedor ×
      // categoria, e o backend não escopa esta rota.
      requiresStore: false,
    );

    return mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) categoryFromJson(item),
      ],
    );
  }
}
