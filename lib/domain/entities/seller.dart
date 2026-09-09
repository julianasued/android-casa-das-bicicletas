/// Vendedor habilitado no terminal (API §2.2).
///
/// Só nome e id: a tela de seleção não é autenticação, e não há credencial a
/// carregar. Quem seleciona não ganha permissão administrativa (§12 da
/// integração com o M10).
class Seller {
  const Seller({required this.id, required this.name});

  final int id;
  final String name;
}
