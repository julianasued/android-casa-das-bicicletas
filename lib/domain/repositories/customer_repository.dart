import '../../core/result.dart';
import '../entities/customer.dart';

/// Clientes (API §3.3). Necessário para a venda em notinha (RF14).
abstract interface class CustomerRepository {
  Future<Result<List<Customer>>> search({String query = ''});

  Future<Result<Customer>> create({
    required String name,
    String? document,
    String? phone,
    String? address,
  });
}
