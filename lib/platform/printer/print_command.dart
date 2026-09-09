/// Comandos que o canal nativo sabe executar.
///
/// A camada Dart não fala ESC/POS nem chama o SDK da Elgin: ela descreve o
/// documento como uma sequência de comandos, e o lado Kotlin traduz. É essa
/// fronteira que permite trocar o modelo de impressora sem reescrever o
/// documento — e testar o documento sem impressora nenhuma.
library;

enum PrintAlign { left, center, right }

sealed class PrintCommand {
  const PrintCommand();

  /// Forma serializável para atravessar o `MethodChannel`.
  Map<String, Object?> toMap();
}

class PrintText extends PrintCommand {
  const PrintText(
    this.value, {
    this.align = PrintAlign.left,
    this.bold = false,
    this.doubleHeight = false,
  });

  final String value;
  final PrintAlign align;
  final bool bold;
  final bool doubleHeight;

  @override
  Map<String, Object?> toMap() => {
        'type': 'text',
        'value': value,
        'align': align.name,
        'bold': bold,
        'double_height': doubleHeight,
      };
}

/// Código de barras da venda (RF08) — o que o caixa vai ler (RF09).
class PrintBarcode extends PrintCommand {
  const PrintBarcode(this.data, {this.height = 60, this.showText = true});

  final String data;
  final int height;
  final bool showText;

  @override
  Map<String, Object?> toMap() => {
        'type': 'barcode',
        'data': data,
        'height': height,
        'show_text': showText,
      };
}

class PrintFeed extends PrintCommand {
  const PrintFeed([this.lines = 1]);

  final int lines;

  @override
  Map<String, Object?> toMap() => {'type': 'feed', 'lines': lines};
}

/// Corte/avanço final. O M10 Pro não tem guilhotina: o comando avança o papel
/// o suficiente para o operador destacar na serrilha.
class PrintCut extends PrintCommand {
  const PrintCut();

  @override
  Map<String, Object?> toMap() => const {'type': 'cut'};
}

List<Map<String, Object?>> encodeCommands(List<PrintCommand> commands) =>
    [for (final command in commands) command.toMap()];
