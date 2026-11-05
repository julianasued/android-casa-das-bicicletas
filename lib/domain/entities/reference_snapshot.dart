/// O que o `GET /sync/pull/` devolve para o cache local (RF34, API §3.9).
///
/// É a cópia de referência que o terminal aplica sem pedir licença a ninguém:
/// catálogo, categorias e clientes da loja. Percentual de comissão fica de fora
/// por sigilo (RF18, RNF03) — e o terminal não precisa dele, porque a comissão é
/// calculada no servidor quando a venda chega.
///
/// **Produto desativado chega aqui como atualização**, com `isActive: false`, e
/// não como ausência. É o que permite ao cache tirá-lo da vitrine: enquanto o
/// terminal só se alimentava das buscas online — que filtram ativos —, um
/// produto desativado no servidor ficava no cache para sempre, e a venda offline
/// saía com ele.
library;

import 'customer.dart';
import 'product.dart';
import 'store.dart';

class ReferenceSnapshot {
  const ReferenceSnapshot({
    required this.syncedAt,
    this.store,
    this.products = const <Product>[],
    this.customers = const <Customer>[],
    this.categories = const <ProductCategory>[],
    this.nextCursor,
  });

  /// Hora **do servidor** em que este retrato foi tirado.
  ///
  /// Vai de volta em `?since=` na próxima chamada. Guardar a hora do servidor,
  /// e não a do terminal, é o que evita perder mudança por relógio adiantado ou
  /// atrasado (ver OFF-004).
  final DateTime syncedAt;

  /// A loja do terminal, como o servidor a descreve — alimenta o cabeçalho do
  /// documento impresso offline.
  final Store? store;

  final List<Product> products;
  final List<Customer> customers;
  final List<ProductCategory> categories;

  /// Valor opaco para pedir a página seguinte, ou nulo quando acabou (§3.9.3).
  ///
  /// A carga de uma loja grande não cabe numa resposta — o terminal desiste em
  /// 20 segundos. O cursor é do servidor e o terminal só o devolve: ele leva o
  /// `since`, o instante congelado e a posição exata em que a página parou, e é
  /// o que permite parar no meio e continuar depois.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  bool get isEmpty => products.isEmpty && customers.isEmpty && categories.isEmpty;

  int get total => products.length + customers.length + categories.length;
}
