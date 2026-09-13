/// Display do cliente de 2,4" do M10 Pro.
///
/// A sequência que o SDK espera é `open()` → comandos → `close()`. Por dentro,
/// `open()` faz `init` + `AbreConexaoDisplay` + `InicializaDisplay`: são três
/// chamadas que sempre andam juntas, e separá-las na API só criaria a chance de
/// esquecer uma.
library;

import 'package:flutter/services.dart';

import 'elgin_exception.dart';

/// Aparelhos que o SDK 02.34.04 reconhece (`E1_Display.DisplayDevices`).
///
/// O padrão é [m10Pro], e não [auto], por determinismo: o `AUTO` decide lendo
/// propriedades de build, que podem mudar entre firmwares.
enum DisplayDevice {
  auto('AUTO'),
  pix4('PIX4'),
  tpro('TPRO'),
  m10Pro('M10_PRO'),
  m11('M11');

  const DisplayDevice(this.code);

  final String code;
}

class ElginDisplay {
  const ElginDisplay._();

  static const MethodChannel _channel = MethodChannel('elgin_m10/display');

  /// Inicializa e conecta.
  ///
  /// A falha típica aqui é "Serviço M11 indisponível": o display faz bind no
  /// mesmo serviço AIDL da impressora (`net.nyx.printerservice`), que não
  /// existe fora do aparelho.
  static Future<void> open({DisplayDevice device = DisplayDevice.m10Pro}) =>
      invokeElgin<void>(_channel, 'display.open', {'device': device.code});

  static Future<void> close() => invokeElgin<void>(_channel, 'display.close');

  static Future<void> reinitialize() =>
      invokeElgin<void>(_channel, 'display.reinitialize');

  /// Texto no display. Com [color] preenchida usa `ApresentaTextoColorido`.
  ///
  /// `a`, `b`, `c` e `d` são os parâmetros posicionais do SDK — a Elgin não
  /// publica o significado deles, então ficam expostos com o nome que têm em
  /// vez de ganharem um nome inventado aqui.
  static Future<void> showText(
    String text, {
    int a = 0,
    int b = 0,
    int c = 0,
    int d = 0,
    String? color,
  }) =>
      invokeElgin<void>(_channel, 'display.showText', {
        'text': text,
        'a': a,
        'b': b,
        'c': c,
        'd': d,
        if (color != null) 'color': color,
      });

  static Future<void> showQrCode(
    String data, {
    int a = 0,
    int b = 0,
    int c = 0,
  }) =>
      invokeElgin<void>(_channel, 'display.showQrCode', {
        'data': data,
        'a': a,
        'b': b,
        'c': c,
      });

  /// Imagem a partir dos bytes, decodificada no lado nativo.
  static Future<void> showImage(Uint8List bytes) =>
      invokeElgin<void>(_channel, 'display.showImage', {'bytes': bytes});

  static Future<void> setInverted(int mode) =>
      invokeElgin<void>(_channel, 'display.setInverted', {'mode': mode});

  static Future<int> firmwareVersion() async =>
      await invokeElgin<int>(_channel, 'display.firmwareVersion') ?? 0;
}
