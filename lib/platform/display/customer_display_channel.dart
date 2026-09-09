/// Display do cliente do M10, atrás de um canal de método.
///
/// ## Estado: PENDENTE DE VALIDAÇÃO
///
/// Não existe API pública da Elgin para este display (ver
/// `domain/ports/customer_display.dart`). Este canal **não inventa comandos**:
/// `show` e `clear` respondem com uma falha explicando a pendência, e `probe`
/// devolve o que a API padrão do Android sabe — quantas telas o aparelho expõe
/// e quais são as secundárias.
///
/// Esse `probe` não é enfeite: é o dado que decide o caminho da implementação.
/// Se o display aparecer como `Display` secundário, dá para escrever nele com
/// `Presentation`, sem SDK nenhum. Se não aparecer, o controle é proprietário e
/// depende do `.aar` de display e da documentação correspondente.
library;

import 'package:flutter/services.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/ports/customer_display.dart';

/// Código combinado com o lado Kotlin para "ainda não implementado".
const String customerDisplayUnsupportedCode = 'DISPLAY_UNSUPPORTED';

class M10CustomerDisplay implements CustomerDisplay {
  const M10CustomerDisplay({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'br.com.casadasbicicletas.vendas/customer_display';

  final MethodChannel _channel;

  @override
  Future<Result<CustomerDisplayStatus>> probe() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('probe');
      if (raw == null) {
        return const Ok(
          CustomerDisplayStatus.unavailable('O canal do display não respondeu.'),
        );
      }

      final displays = raw['secondary_displays'];
      return Ok(
        CustomerDisplayStatus(
          available: raw['sdk_available'] as bool? ?? false,
          hasSecondaryDisplay: raw['has_secondary_display'] as bool? ?? false,
          secondaryDisplays: _describeDisplays(displays),
          detail: raw['detail']?.toString() ?? '',
        ),
      );
    } on PlatformException catch (error) {
      return Ok(
        CustomerDisplayStatus.unavailable(
          error.message ?? 'Falha ao consultar o display.',
        ),
      );
    } on MissingPluginException {
      return const Ok(
        CustomerDisplayStatus.unavailable(
          'Canal do display indisponível neste aparelho.',
        ),
      );
    }
  }

  List<String> _describeDisplays(Object? value) {
    if (value is! List) return const <String>[];

    return [
      for (final item in value)
        if (item is Map)
          '#${item['id']} ${item['name'] ?? ''}'.trim(),
    ];
  }

  @override
  Future<Result<void>> show(List<String> lines) =>
      _unsupported('escrever no display');

  @override
  Future<Result<void>> clear() => _unsupported('limpar o display');

  Future<Result<void>> _unsupported(String operation) async => Err(
        BusinessRuleFailure(
          'Não é possível $operation: a Elgin não publica API para o display do '
          'cliente. Pendente de validação no M10 físico.',
        ),
      );
}
