/// Cliente (RF05). Obrigatório na venda em notinha (RF14).
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.document,
    this.phone,
    this.address,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? document;
  final String? phone;
  final String? address;
  final bool isActive;
}
