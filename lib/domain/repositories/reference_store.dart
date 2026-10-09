/// O cache de referência, visto pelo domínio (RF34).
///
/// O caso de uso do `pull` precisa guardar catálogo, categorias e clientes, e
/// precisa saber até quando já recebeu. Como isso é gravado — SQLite, hoje — é
/// assunto da camada de dados, do mesmo jeito que acontece com a fila
/// (`SyncQueue`).
///
/// A porta é estreita de propósito: só o que o caso de uso usa. Ler o cache
/// para a busca do balcão é outro caminho, e passa pelos repositórios de
/// catálogo e de cliente.
library;

import '../entities/customer.dart';
import '../entities/product.dart';
import '../entities/store.dart';

abstract interface class ReferenceStore {
  /// Até quando o cache desta loja já recebeu dados do servidor.
  Future<DateTime?> lastReferenceSync();

  /// Guarda o `synced_at` que o servidor devolveu.
  Future<void> saveReferenceSync(DateTime syncedAt);

  Future<void> saveProducts(Iterable<Product> products);

  Future<void> saveCustomers(Iterable<Customer> customers);

  Future<void> saveCategories(Iterable<ProductCategory> categories);

  /// Dados da loja para o cabeçalho do documento impresso offline.
  Future<void> learnStore(Store store);
}
