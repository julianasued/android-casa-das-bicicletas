/// Clientes (API §3.3), com cache local de leitura (RF34, §13.9).
///
/// Necessário para a venda em notinha (RF14) — e é justamente a notinha que
/// mais precisa de cache: ela exige cliente cadastrado, e sem rede não haveria
/// como escolher um.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/receivable.dart';
import '../../domain/repositories/customer_repository.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';
import '../local/reference_cache.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  const CustomerRepositoryImpl(this._api, {ReferenceCache? cache})
      : _cache = cache;

  final ApiClient _api;
  final ReferenceCache? _cache;

  @override
  Future<Result<List<Customer>>> search({String query = ''}) async {
    final response = await _api.get(
      ApiEndpoints.customers,
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'is_active': 'true',
        'ordering': 'name',
        'page_size': '50',
      },
    );

    final resultado = await mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) customerFromJson(item),
      ],
    );

    switch (resultado) {
      case Ok(:final value):
        await _cache?.saveCustomers(value);
        return resultado;

      case Err(failure: NetworkFailure()):
        final local = await _cache?.searchCustomers(query: query);
        return local == null || local.isEmpty ? resultado : Ok(local);

      case Err():
        return resultado;
    }
  }

  @override
  Future<Result<Customer>> create({
    required String name,
    String? document,
    String? phone,
    String? address,
  }) async {
    final response = await _api.post(
      ApiEndpoints.customers,
      body: {
        'name': name.trim(),
        if (document != null && document.trim().isNotEmpty) 'document': document.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
      },
      // §1.5 — o cadastro nasce no balcão, onde o toque duplo no botão é comum.
      idempotencyKey: ApiClient.newIdempotencyKey(),
    );

    final resultado =
        await mapApiResponse(response, (result) => customerFromJson(result.data));

    // Quem acabou de ser cadastrado é quem o vendedor vai usar na venda que
    // está montando; deixá-lo fora do cache faria ele desaparecer se a rede
    // caísse no minuto seguinte.
    if (resultado case Ok(:final value)) {
      await _cache?.saveCustomers([value]);
    }
    return resultado;
  }

  @override
  Future<Result<List<Receivable>>> receivables(int customerId) async {
    final response = await _api.get(ApiEndpoints.customerReceivables(customerId));

    return mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) receivableFromJson(item),
      ],
    );
  }
}
