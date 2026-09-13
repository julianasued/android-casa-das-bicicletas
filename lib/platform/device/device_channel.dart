/// Identificação do aparelho.
///
/// O `X-Device-Id` (§1.2) precisa ser o mesmo em toda instalação do mesmo
/// terminal e diferente entre aparelhos. O `ANDROID_ID` cumpre isso e serve de
/// sugestão na tela de configuração — mas quem manda é o valor cadastrado em
/// `Terminal.device_identifier` no backend, e por isso o campo continua
/// editável.
library;

import 'package:flutter/services.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.androidId,
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
  });

  const DeviceInfo.unknown()
      : androidId = '',
        model = '',
        manufacturer = '',
        androidVersion = '';

  final String androidId;
  final String model;
  final String manufacturer;
  final String androidVersion;

  String get displayName =>
      [manufacturer, model].where((part) => part.isNotEmpty).join(' ');

  /// O terminal homologado é o M10 Pro (§2 da integração).
  bool get looksLikeM10 => model.toUpperCase().contains('M10');
}

class DeviceChannel {
  const DeviceChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'br.com.casadasbicicletas.vendas/device';

  final MethodChannel _channel;

  Future<DeviceInfo> read() async {
    try {
      final data = await _channel.invokeMapMethod<String, Object?>('info');
      if (data == null) return const DeviceInfo.unknown();

      return DeviceInfo(
        androidId: data['android_id']?.toString() ?? '',
        model: data['model']?.toString() ?? '',
        manufacturer: data['manufacturer']?.toString() ?? '',
        androidVersion: data['android_version']?.toString() ?? '',
      );
    } on MissingPluginException {
      return const DeviceInfo.unknown();
    } on PlatformException {
      return const DeviceInfo.unknown();
    }
  }
}
