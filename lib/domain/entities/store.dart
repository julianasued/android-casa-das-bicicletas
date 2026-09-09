/// Loja (RF03). O `code` (`L1`, `L2`) compõe o código de barras da venda.
class Store {
  const Store({
    required this.id,
    required this.code,
    required this.name,
    this.document = '',
    this.address = '',
  });

  final int id;
  final String code;
  final String name;
  final String document;
  final String address;
}
