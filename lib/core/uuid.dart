/// Geração de UUID v4 sem dependência externa.
///
/// O identificador da venda nasce **no terminal** (RF36 e o documento de
/// arquitetura, seção B): é ele que forma o código de barras impresso no
/// documento 1 e é ele que permite reenviar a mesma venda sem duplicá-la, com
/// ou sem internet. Uma dependência de terceiros para trinta linhas de código
/// seria uma dependência a manter em campo, num terminal que fica meses sem
/// atualização.
library;

import 'dart:math';

final Random _random = Random.secure();

/// UUID v4 em minúsculas, no formato canônico com hífens.
String generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

  // Versão 4 e variante RFC 4122 — o servidor valida o formato (§1.5).
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Código de barras da venda, na forma que o backend gera (`identifiers.py`).
///
/// O terminal calcula o mesmo código que o servidor calcularia, a partir do
/// `uuid` que ele próprio gerou. É isso que permite imprimir o documento 1 no
/// balcão antes de qualquer sincronização.
String saleBarcodeFor({required String storeCode, required String saleUuid}) {
  final token = saleUuid.replaceAll('-', '').substring(0, 8).toUpperCase();
  return 'SALE-$storeCode-$token';
}
