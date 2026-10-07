/// Display do cliente do M10, sobre o plugin `elgin_m10`.
///
/// A porta `CustomerDisplay` nasceu como abstração vazia, quando a
/// documentação pública da Elgin não descrevia display algum. O SDK descreve:
/// `com.elgin.e1.Display.E1_Display` tem `M10_PRO` entre os aparelhos
/// suportados, e é o plugin quem fala com ele. Esta classe é a tradução entre a
/// porta do domínio e o plugin.
///
/// O `probe` continua vindo do canal legado (`CustomerDisplayChannel.kt`),
/// porque ele responde outra pergunta: quantas telas o **Android** enxerga.
/// Serve de diagnóstico quando `open()` falha — se não há tela secundária nem
/// serviço, o problema é o aparelho, não o código.
library;

import 'package:elgin_m10/elgin_m10.dart';
import 'package:flutter/services.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/ports/customer_display.dart';

class M10CustomerDisplay implements CustomerDisplay {
  M10CustomerDisplay({MethodChannel? probeChannel})
      : _probeChannel = probeChannel ?? const MethodChannel(probeChannelName);

  /// Canal legado, usado só para o levantamento de telas do Android.
  static const String probeChannelName =
      'br.com.casadasbicicletas.vendas/customer_display';

  final MethodChannel _probeChannel;

  bool _open = false;

  @override
  Future<Result<CustomerDisplayStatus>> probe() async {
    Map<String, Object?> android = const <String, Object?>{};
    try {
      android = await _probeChannel.invokeMapMethod<String, Object?>('probe') ??
          const <String, Object?>{};
    } on PlatformException {
      // Levantamento é acessório: sem ele ainda dá para tentar abrir.
    } on MissingPluginException {
      // Fora do terminal.
    }

    // Abrir e fechar é a única prova real de que o display responde: o SDK só
    // diz que existe quando o serviço aceita a conexão.
    try {
      await ElginDisplay.open();
      await ElginDisplay.close();

      return Ok(
        CustomerDisplayStatus(
          available: true,
          hasSecondaryDisplay: android['has_secondary_display'] as bool? ?? false,
          secondaryDisplays: _describe(android['secondary_displays']),
          detail: 'Display respondeu pelo SDK da Elgin (M10_PRO).',
        ),
      );
    } on ElginException catch (error) {
      return Ok(
        CustomerDisplayStatus(
          available: false,
          hasSecondaryDisplay: android['has_secondary_display'] as bool? ?? false,
          secondaryDisplays: _describe(android['secondary_displays']),
          detail: 'SDK: ${error.message}',
        ),
      );
    }
  }

  @override
  Future<Result<void>> show(List<String> lines) async {
    try {
      await _ensureOpen();
      // O SDK escreve uma chamada por linha; juntar com quebra de linha
      // dependeria de um comportamento que a Elgin não documenta.
      for (final line in lines) {
        await ElginDisplay.showText(line);
      }
      return const Ok(null);
    } on ElginException catch (error) {
      return Err(_failureFor(error));
    }
  }

  @override
  Future<Result<void>> clear() async {
    try {
      await _ensureOpen();
      // Não há "limpar" na API: reinicializar é o que devolve o display ao
      // estado inicial sem derrubar a conexão.
      await ElginDisplay.reinitialize();
      return const Ok(null);
    } on ElginException catch (error) {
      return Err(_failureFor(error));
    }
  }

  Future<void> _ensureOpen() async {
    if (_open) return;
    await ElginDisplay.open();
    _open = true;
  }

  Failure _failureFor(ElginException error) {
    _open = false;
    if (error.isUnavailable) {
      return BusinessRuleFailure(
        'Display do cliente indisponível neste terminal: ${error.message}',
      );
    }
    return BusinessRuleFailure('Falha no display do cliente: ${error.message}');
  }

  List<String> _describe(Object? value) {
    if (value is! List) return const <String>[];
    return [
      for (final item in value)
        if (item is Map) '#${item['id']} ${item['name'] ?? ''}'.trim(),
    ];
  }
}
