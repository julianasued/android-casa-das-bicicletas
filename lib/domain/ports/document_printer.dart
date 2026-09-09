import '../../core/result.dart';
import '../entities/printed_document.dart';

/// Estado da impressora térmica (§4 e §11 da integração com o M10 Pro).
class PrinterStatus {
  const PrinterStatus({
    required this.available,
    required this.outOfPaper,
    this.detail = '',
  });

  const PrinterStatus.unavailable([this.detail = 'SDK da impressora não disponível'])
      : available = false,
        outOfPaper = false;

  /// A impressora respondeu e está pronta para receber comandos.
  final bool available;

  /// Falta de papel — quando o hardware sabe informar.
  final bool outOfPaper;

  /// Texto do fabricante, útil no diagnóstico e no registro de erro.
  final String detail;

  bool get canPrint => available && !outOfPaper;
}

/// Porta de impressão do domínio.
///
/// O domínio manda imprimir um documento; não sabe que existe SDK da Elgin,
/// canal de método ou ESC/POS. Trocar o terminal por outro modelo troca a
/// implementação desta interface e nada mais (regra de dependência, §10.2).
abstract interface class DocumentPrinter {
  /// Verifica disponibilidade antes de prometer impressão ao operador.
  Future<Result<PrinterStatus>> status();

  /// Imprime o documento 1 ou 2 (RF08, RF12).
  Future<Result<void>> printDocument(PrintedDocument document);

  /// Avanço de papel — pedido explícito do §4 da integração.
  Future<Result<void>> feed({int lines = 3});

  /// Impressão de teste, para conferir a bobina e o hardware na instalação.
  Future<Result<void>> printTestPage({required String terminalName});
}
