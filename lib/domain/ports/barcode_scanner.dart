import '../../core/result.dart';
import '../entities/barcode_read.dart';

/// Porta do leitor de código de barras integrado (§5 e §6 da integração).
///
/// Um `Stream`, e não um `Future`, porque o leitor não é chamado: ele dispara.
/// O caixa aponta e atira, e a tela reage — é a diferença entre "digitar o
/// número da venda" e o que a RF09 pede.
abstract interface class BarcodeScanner {
  /// Leituras do leitor integrado, na ordem em que chegam.
  Stream<BarcodeRead> get reads;

  /// Liga o leitor (registra o receptor nativo). Idempotente.
  Future<Result<void>> start();

  /// Desliga o leitor ao sair da tela — o receptor nativo não fica pendurado.
  Future<Result<void>> stop();

  /// O terminal tem leitor integrado disponível?
  Future<bool> isAvailable();
}
