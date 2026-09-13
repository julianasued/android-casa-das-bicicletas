/// Acesso direto às funções da impressora, para diagnóstico e para o POC.
///
/// Existe **separada** de `DocumentPrinter` de propósito, e mora na camada de
/// plataforma, não no domínio. O domínio manda imprimir *um documento de venda*
/// e não deveria conhecer "avançar 3 linhas" nem "cortar o papel": essas são
/// operações de hardware, úteis na instalação do terminal e na prova de
/// integração, não na regra de negócio. Colocá-las no domínio obrigaria a
/// camada de dentro a conhecer `PrintCommand`, que é formato de canal nativo.
///
/// Quem implementa as duas interfaces é a mesma classe (`PrinterChannel`), o
/// que evita duas conexões com o mesmo aparelho; quem *depende* de cada uma é
/// que muda: a venda depende de `DocumentPrinter`, a tela do POC desta.
library;

import '../../core/result.dart';
import '../../domain/ports/document_printer.dart';
import 'print_command.dart';

abstract interface class PrinterDiagnostics {
  /// Estado consultado no hardware, com os valores crus de `StatusImpressora`.
  Future<Result<PrinterStatus>> status();

  /// Envia uma sequência arbitrária de comandos — o caminho do POC.
  Future<Result<void>> sendCommands(List<PrintCommand> commands);

  /// `AvancaPapel(linhas)`.
  Future<Result<void>> feed({int lines = 3});

  /// `Corte(avanco)` — corte parcial, precedido do avanço informado.
  Future<Result<void>> cut({int advance = 3});

  /// `InicializaImpressora()` — limpa o buffer e reinicia a impressora.
  Future<Result<void>> reset();

  /// `FechaConexaoImpressora()` — usado para provar a reabertura após erro.
  Future<Result<void>> disconnect();
}
