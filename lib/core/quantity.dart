/// Quantidade vendida.
///
/// A API aceita três casas decimais (`QTY` em `apps/sales/models.py`), porque
/// nem tudo na loja se vende por unidade inteira — óleo a granel é o caso
/// óbvio. Guardamos milésimos inteiros pelo mesmo motivo que o dinheiro fica em
/// centavos: a quantidade entra na multiplicação que forma o total da linha, e
/// erro de ponto flutuante aí vira centavo errado no documento.
library;

import 'money.dart';

class Quantity implements Comparable<Quantity> {
  const Quantity.fromThousandths(this.thousandths);

  const Quantity.units(int units) : thousandths = units * 1000;

  factory Quantity.parse(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      throw FormatException('Quantidade vazia', raw);
    }

    final parts = text.split('.');
    if (parts.length > 2) {
      throw FormatException('Quantidade inválida', raw);
    }

    final whole = int.parse(parts.first.isEmpty ? '0' : parts.first);
    var fraction = 0;
    if (parts.length == 2) {
      final decimals = parts[1].padRight(4, '0');
      fraction = roundHalfUp(int.parse(decimals.substring(0, 4)), 10);
    }
    return Quantity.fromThousandths(whole * 1000 + fraction);
  }

  final int thousandths;

  bool get isWhole => thousandths % 1000 == 0;
  bool get isPositive => thousandths > 0;

  Quantity operator +(Quantity other) =>
      Quantity.fromThousandths(thousandths + other.thousandths);

  Quantity operator -(Quantity other) =>
      Quantity.fromThousandths(thousandths - other.thousandths);

  /// Total bruto da linha: quantidade × preço unitário, fechado em centavos.
  Money multiply(Money unitPrice) => unitPrice.timesThousandths(thousandths);

  String toApiString() {
    final whole = thousandths ~/ 1000;
    final fraction = (thousandths % 1000).toString().padLeft(3, '0');
    return '$whole.$fraction';
  }

  /// Na tela, `2` e não `2.000`: a casa decimal só aparece quando existe.
  String toDisplayString() {
    if (isWhole) return (thousandths ~/ 1000).toString();
    final whole = thousandths ~/ 1000;
    final fraction =
        (thousandths % 1000).toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '');
    return '$whole,$fraction';
  }

  @override
  int compareTo(Quantity other) => thousandths.compareTo(other.thousandths);

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.thousandths == thousandths;

  @override
  int get hashCode => thousandths.hashCode;

  @override
  String toString() => toApiString();
}
