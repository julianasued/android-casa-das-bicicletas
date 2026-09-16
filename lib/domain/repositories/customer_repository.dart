import '../../core/result.dart';
import '../entities/customer.dart';
import '../entities/receivable.dart';

/// Clientes (API §3.3). Necessário para a venda em notinha (RF14).
abstract interface class CustomerRepository {
  Future<Result<List<Customer>>> search({String query = ''});

  Future<Result<Customer>> create({
    required String name,
    String? document,
    String? phone,
    String? address,
    String? notes,
  });

  /// Pendências do cliente (RF15).
  ///
  /// O vendedor consulta antes de fiar: notinha vira dívida, e vender de novo
  /// para quem já está devendo é decisão que precisa do número na tela.
  Future<Result<List<Receivable>>> receivables(int customerId);
}
