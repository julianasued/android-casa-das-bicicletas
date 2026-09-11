/// Catálogo da loja (API §3.2), com cache local de leitura (RF34, §13.9).
///
/// A busca vai ao servidor e o resultado é guardado no caminho de volta. Quando
/// a rede falha, responde o que está no cache — porque no balcão um catálogo de
/// ontem vale mais que uma tela de erro, e o §13.9 põe consulta de produto
/// entre as operações que devem funcionar offline.
///
/// **Só falha de rede cai para o cache.** Erro do servidor (`422`, `403`) é
/// resposta legítima e precisa chegar a quem chamou; disfarçá-la de sucesso
/// esconderia problema de permissão ou de contrato.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';
import '../local/reference_cache.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  const CatalogRepositoryImpl(this._api, {ReferenceCache? cache})
      : _cache = cache;

  final ApiClient _api;

  /// Opcional: sem cache o repositório se comporta como antes, e é assim que os
  /// testes que só olham o contrato REST continuam simples.
  final ReferenceCache? _cache;

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

    final resultado = await mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) productFromJson(item),
      ],
    );

    switch (resultado) {
      case Ok(:final value):
        // Guardar no caminho de volta: o que o vendedor consulta é o que ele
        // vende, então o cache se enche do catálogo que importa sem precisar
        // baixar a loja inteira.
        await _cache?.saveProducts(value);
        return resultado;

      case Err(failure: NetworkFailure()):
        final local = await _cache?.searchProducts(
          query: query,
          categoryCode: categoryCode,
        );
        return local == null || local.isEmpty ? resultado : Ok(local);

      case Err():
        return resultado;
    }
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

    final resultado = await mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) categoryFromJson(item),
      ],
    );

    switch (resultado) {
      case Ok(:final value):
        await _cache?.saveCategories(value);
        return resultado;

      case Err(failure: NetworkFailure()):
        final local = await _cache?.listCategories();
        return local == null || local.isEmpty ? resultado : Ok(local);

      case Err():
        return resultado;
    }
  }
}
