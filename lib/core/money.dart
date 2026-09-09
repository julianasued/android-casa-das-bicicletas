/// Aritmética monetária do aplicativo.
///
/// O valor é guardado em **centavos inteiros**, e não em `double`. Um preço de
/// R$ 0,10 não existe em binário: somar dez vezes esse valor em ponto flutuante
/// dá R$ 0,9999999999999999, e um documento impresso com um centavo de
/// diferença do que o servidor registrou é um documento que o caixa vai
/// contestar.
///
/// O arredondamento é o mesmo do backend (`core/money.py`): meia unidade para
/// cima, fechando em centavos a cada etapa. Sem isso o total exibido no
/// terminal e o total gravado no Postgres divergiriam no rateio do desconto
/// (13.3).
library;

/// Divisão inteira com arredondamento de meia unidade para cima.
///
/// `(2*n + d) ~/ (2*d)` é `floor(n/d + 0.5)` sem passar por ponto flutuante.
int roundHalfUp(int numerator, int denominator) {
  assert(denominator > 0, 'denominador deve ser positivo');
  if (numerator < 0) {
    return -roundHalfUp(-numerator, denominator);
  }
  return (2 * numerator + denominator) ~/ (2 * denominator);
}

/// Valor monetário em centavos.
class Money implements Comparable<Money> {
  const Money.fromCents(this.cents);

  const Money.zero() : cents = 0;

  /// Converte a string decimal do JSON (`"1500.00"`) sem passar por `double`.
  factory Money.parse(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      throw FormatException('Valor monetário vazio', raw);
    }

    final negative = text.startsWith('-');
    final digits = negative ? text.substring(1) : text;
    final parts = digits.split('.');
    if (parts.length > 2) {
      throw FormatException('Valor monetário inválido', raw);
    }

    final whole = int.parse(parts.first.isEmpty ? '0' : parts.first);
    var fraction = 0;
    if (parts.length == 2) {
      // Terceira casa em diante é arredondada, não truncada: o servidor manda
      // duas casas, mas um cálculo local pode chegar aqui com mais.
      final decimals = parts[1].padRight(3, '0');
      final milli = int.parse(decimals.substring(0, 3));
      fraction = roundHalfUp(milli, 10);
    }

    final value = whole * 100 + fraction;
    return Money.fromCents(negative ? -value : value);
  }

  /// Aceita `null` como zero — campos opcionais do JSON chegam assim.
  factory Money.tryParse(Object? raw) {
    if (raw == null) return const Money.zero();
    if (raw is num) return Money.parse(raw.toString());
    return Money.parse(raw.toString());
  }

  final int cents;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money.fromCents(cents + other.cents);
  Money operator -(Money other) => Money.fromCents(cents - other.cents);

  /// Multiplica por uma quantidade em milésimos, fechando em centavos (13.3).
  Money timesThousandths(int thousandths) =>
      Money.fromCents(roundHalfUp(cents * thousandths, 1000));

  /// Percentual sobre o valor, fechado em centavos — o `percent_of` do backend.
  ///
  /// `percentHundredths` é o percentual com duas casas (5% → 500), a mesma
  /// precisão que o campo `discount_percent` da API aceita.
  Money percent(int percentHundredths) =>
      Money.fromCents(roundHalfUp(cents * percentHundredths, 10000));

  /// Fração proporcional deste valor dentro de um todo — usado no rateio.
  Money proportion({required Money part, required Money whole}) {
    if (whole.cents == 0) return const Money.zero();
    return Money.fromCents(roundHalfUp(cents * part.cents, whole.cents));
  }

  /// Formato aceito pela API: ponto decimal, duas casas, sem separador de milhar.
  String toApiString() {
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    return '$sign${absolute ~/ 100}.$fraction';
  }

  /// Formato do balcão: `R$ 1.500,00`.
  String toDisplayString({bool symbol = true}) {
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    final whole = (absolute ~/ 100).toString();
    final fraction = (absolute % 100).toString().padLeft(2, '0');

    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
      buffer.write(whole[i]);
    }

    final prefix = symbol ? 'R\$ ' : '';
    return '$sign$prefix$buffer,$fraction';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => toApiString();
}

/// Soma de uma lista de valores — evita `fold` repetido em cinco lugares.
Money sumMoney(Iterable<Money> values) {
  var total = 0;
  for (final value in values) {
    total += value.cents;
  }
  return Money.fromCents(total);
}
