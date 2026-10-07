/// Formas de pagamento aceitas (RF10, `core/enums.py` do backend).
enum PaymentMethod {
  pix('PIX', 'PIX'),
  dinheiro('DINHEIRO', 'Dinheiro'),
  credito('CREDITO', 'Crédito'),
  debito('DEBITO', 'Débito'),
  notinha('NOTINHA', 'Notinha');

  const PaymentMethod(this.code, this.label);

  /// Valor enviado e recebido na API.
  final String code;

  /// Texto do botão e do documento impresso.
  final String label;

  /// RF14 — notinha é venda fiada: exige cliente identificado.
  bool get requiresCustomer => this == PaymentMethod.notinha;

  /// A notinha não passa pelo caixa: vira pendência do cliente (RF13/RF14).
  bool get isReceivedAtCashier => this != PaymentMethod.notinha;

  static PaymentMethod fromCode(String code) => PaymentMethod.values.firstWhere(
        (method) => method.code == code,
        orElse: () => throw ArgumentError('Forma de pagamento desconhecida: $code'),
      );

  static PaymentMethod? tryFromCode(String? code) {
    if (code == null) return null;
    for (final method in PaymentMethod.values) {
      if (method.code == code) return method;
    }
    return null;
  }
}
