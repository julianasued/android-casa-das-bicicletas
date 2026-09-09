/// Clientes (API §3.3). Necessário para a venda em notinha (RF14).
library;

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  const CustomerRepositoryImpl(this._api);

  final ApiClient _api;

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

    return mapApiResponse(
      response,
      (result) => [
        for (final item in readResults(result.data)) customerFromJson(item),
      ],
    );
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

    return mapApiResponse(response, (result) => customerFromJson(result.data));
  }
}
