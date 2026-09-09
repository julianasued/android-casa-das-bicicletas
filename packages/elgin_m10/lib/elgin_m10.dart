/// Ponte Flutter para os periféricos internos do Elgin Mini PDV M10 Pro.
///
/// Três módulos, um por periférico, sobre o SDK E1 da Elgin:
///
///  - [ElginPrinter] — impressora térmica interna;
///  - [ElginDisplay] — display do cliente de 2,4";
///  - [ElginScanner] — leitor de código de barras 1D/2D.
///
/// Todo erro do SDK chega como [ElginException], com o código numérico
/// preservado. Nada aqui funciona fora do aparelho: o serviço
/// `net.nyx.printerservice` não existe em emulador, e a abertura de conexão
/// falha por isso.
library;

export 'src/elgin_display.dart';
export 'src/elgin_exception.dart' hide invokeElgin;
export 'src/elgin_printer.dart';
export 'src/elgin_scanner.dart';
