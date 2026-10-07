/// Uma leitura do leitor integrado do M10 Pro (§5 e §6 da integração).
class BarcodeRead {
  const BarcodeRead({
    required this.code,
    required this.readAt,
    this.symbology,
    this.source = BarcodeSource.integratedScanner,
  });

  final String code;
  final DateTime readAt;

  /// Simbologia informada pelo leitor (`CODE128`, `QR_CODE`), quando informada.
  final String? symbology;

  final BarcodeSource source;

  /// Códigos de venda seguem `SALE-<loja>-<8 hex>` (`identifiers.py`).
  bool get looksLikeSaleBarcode =>
      RegExp(r'^SALE-[A-Z0-9]{1,10}-[0-9A-F]{8}$').hasMatch(code.toUpperCase());
}

/// De onde veio a leitura.
///
/// O leitor do M10 opera de dois jeitos, e os dois existem em campo: emitindo
/// um broadcast que o canal nativo escuta, ou emulando teclado. Registrar a
/// origem evita a pergunta "o leitor está configurado em qual modo?" na hora
/// de investigar uma leitura que não chegou.
enum BarcodeSource {
  integratedScanner('Leitor integrado'),
  keyboardWedge('Leitor em modo teclado'),
  manual('Digitado');

  const BarcodeSource(this.label);

  final String label;
}
