/// Formatação de data, hora e documento para a tela e para o papel.
///
/// Sem `intl`: o aplicativo tem uma localidade só (pt-BR) e um fuso só (o da
/// loja). Carregar um pacote de internacionalização para formatar `dd/MM/yyyy`
/// custaria mais em manutenção do que as vinte linhas abaixo.
library;

String _two(int value) => value.toString().padLeft(2, '0');

/// `05/08/2026` — a data já no fuso local do terminal.
String formatDate(DateTime moment) {
  final local = moment.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

/// `14:32`.
String formatTime(DateTime moment) {
  final local = moment.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// `05/08/2026 14:32` — o carimbo dos documentos impressos (§7 da integração).
String formatDateTime(DateTime moment) =>
    '${formatDate(moment)} ${formatTime(moment)}';

/// ISO 8601 com fuso, como o cabeçalho `X-Client-Timestamp` exige (§1.2).
String formatIsoTimestamp(DateTime moment) =>
    moment.toUtc().toIso8601String();

/// `123.456.789-09` / `12.345.678/0001-90`, conforme o tamanho.
String formatDocument(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.'
        '${digits.substring(6, 9)}-${digits.substring(9)}';
  }
  if (digits.length == 14) {
    return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.'
        '${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
  }
  return raw ?? '';
}

/// Percentual com duas casas, como a API espera (`"5.00"`).
String formatPercentApi(int hundredths) {
  final whole = hundredths ~/ 100;
  final fraction = (hundredths % 100).toString().padLeft(2, '0');
  return '$whole.$fraction';
}

/// Percentual para a tela: `5%`, `2,5%`.
String formatPercentDisplay(int hundredths) {
  if (hundredths % 100 == 0) return '${hundredths ~/ 100}%';
  final fraction =
      (hundredths % 100).toString().padLeft(2, '0').replaceAll(RegExp(r'0+$'), '');
  return '${hundredths ~/ 100},$fraction%';
}

/// Lê `"5"`, `"5,5"` ou `"5.50"` como centésimos de percentual.
int? parsePercentHundredths(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return 0;
  final value = double.tryParse(text);
  if (value == null || value.isNaN || value < 0) return null;
  return (value * 100).round();
}
