/// Impressora térmica interna do M10 Pro.
///
/// A API é estática porque o SDK é estático: `com.elgin.e1.Impressora.Termica`
/// não tem instância, e fingir que tem — devolvendo objetos que na verdade
/// compartilham a mesma conexão — só criaria a ilusão de isolamento.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'elgin_exception.dart';

/// Simbologias de `ImpressaoCodigoBarras`, com o código do SDK.
///
/// O comprimento aceito é do fabricante e está anotado: mandar 13 dígitos num
/// EAN-8 devolve erro do SDK, não código torto no papel.
enum BarcodeType {
  upcA(0, 'UPC-A (11–12 dígitos)'),
  upcE(1, 'UPC-E (6–12 dígitos)'),
  ean13(2, 'EAN-13 (12–13 dígitos)'),
  ean8(3, 'EAN-8 (7–8 dígitos)'),
  code39(4, 'CODE 39'),
  itf(5, 'ITF (quantidade par de dígitos)'),
  codebar(6, 'CODEBAR'),
  code93(7, 'CODE 93'),
  code128(8, 'CODE 128');

  const BarcodeType(this.sdkValue, this.label);

  final int sdkValue;
  final String label;
}

/// Posição do texto legível do código de barras (`HRI`).
enum HriPosition {
  above(1),
  below(2),
  both(3),
  none(4);

  const HriPosition(this.sdkValue);

  final int sdkValue;
}

/// Alinhamento do texto (`posicao` de `ImpressaoTexto`).
class PrinterAlign {
  static const int left = 0;
  static const int center = 1;
  static const int right = 2;
}

/// `estilo` de `ImpressaoTexto` — soma de bits, não valor único.
class PrinterStyle {
  static const int fontA = 0;
  static const int fontB = 1;
  static const int underline = 2;
  static const int reverse = 4;
  static const int bold = 8;

  /// Compõe o inteiro somando os atributos pedidos.
  static int of({
    bool fontB = false,
    bool underline = false,
    bool reverse = false,
    bool bold = false,
  }) =>
      (fontB ? PrinterStyle.fontB : 0) +
      (underline ? PrinterStyle.underline : 0) +
      (reverse ? PrinterStyle.reverse : 0) +
      (bold ? PrinterStyle.bold : 0);
}

/// `tamanho` de `ImpressaoTexto` — altura (0–8) somada à largura.
class PrinterSize {
  static const int normal = 0;

  static const int height2x = 1;
  static const int width2x = 16;

  static int of({int height = 0, int width = 0}) => height + width;
}

/// Estado bruto de `StatusImpressora`, por assunto.
///
/// A Elgin publica o significado do **parâmetro** (1 gaveta, 2 tampa, 3 papel,
/// 4 ejetor, 5 geral), mas não o dos valores devolvidos. Nada é interpretado
/// aqui: os números sobem como vieram, para o mapeamento sair do aparelho.
class PrinterStatus {
  const PrinterStatus({
    required this.drawer,
    required this.cover,
    required this.paper,
    required this.ejector,
    required this.general,
  });

  factory PrinterStatus.fromMap(Map<Object?, Object?> map) => PrinterStatus(
        drawer: map['drawer'] as int? ?? 0,
        cover: map['cover'] as int? ?? 0,
        paper: map['paper'] as int? ?? 0,
        ejector: map['ejector'] as int? ?? 0,
        general: map['general'] as int? ?? 0,
      );

  final int drawer;
  final int cover;
  final int paper;
  final int ejector;
  final int general;

  Map<String, int> toMap() => {
        'drawer': drawer,
        'cover': cover,
        'paper': paper,
        'ejector': ejector,
        'general': general,
      };

  @override
  String toString() => toMap().toString();
}

class ElginPrinter {
  const ElginPrinter._();

  static const MethodChannel _channel = MethodChannel('elgin_m10/printer');

  /// Abre a conexão com a impressora interna.
  ///
  /// Os quatro parâmetros de `AbreConexaoImpressora` estão expostos porque o
  /// valor certo de `type` não é consenso: a documentação pública da Elgin
  /// descreve 1 a 5 (5 = impressoras embarcadas) e o exemplo oficial em Flutter
  /// usa `(5, "")`, enquanto o pacote 02.34.04 indica `(6, "M8")`. O padrão
  /// segue o pacote; trocar para testar a outra combinação não exige recompilar.
  static Future<void> open({
    int type = 6,
    String model = 'M8',
    String connection = '',
    int parameter = 0,
  }) =>
      invokeElgin<void>(_channel, 'printer.open', {
        'type': type,
        'model': model,
        'connection': connection,
        'parameter': parameter,
      });

  static Future<void> close() => invokeElgin<void>(_channel, 'printer.close');

  /// `InicializaImpressora` — limpa o buffer e prepara para novas tarefas.
  static Future<void> initialize() =>
      invokeElgin<void>(_channel, 'printer.initialize');

  static Future<void> printText(
    String text, {
    int align = PrinterAlign.left,
    int style = PrinterStyle.fontA,
    int size = PrinterSize.normal,
  }) =>
      invokeElgin<void>(_channel, 'printer.printText', {
        'text': text,
        'align': align,
        'style': style,
        'size': size,
      });

  static Future<void> printBarcode(
    String data, {
    required BarcodeType type,
    int height = 60,
    int width = 2,
    HriPosition hri = HriPosition.below,
  }) =>
      invokeElgin<void>(_channel, 'printer.printBarcode', {
        'type': type.sdkValue,
        'data': data,
        'height': height,
        'width': width,
        'hri': hri.sdkValue,
      });

  /// `tamanho` vai de 1 a 6; `correction` de 0 a 4 conforme a versão do SDK.
  static Future<void> printQrCode(
    String data, {
    int size = 4,
    int correction = 0,
  }) =>
      invokeElgin<void>(_channel, 'printer.printQrCode', {
        'data': data,
        'size': size,
        'correction': correction,
      });

  /// Imprime a imagem a partir dos bytes, sem arquivo temporário em disco.
  static Future<void> printImageFromBytes(Uint8List bytes) =>
      invokeElgin<void>(_channel, 'printer.printImage', {'bytes': bytes});

  static Future<void> feed(int lines) =>
      invokeElgin<void>(_channel, 'printer.feed', {'lines': lines});

  /// Corte parcial por padrão; `full` usa `CorteTotal`.
  static Future<void> cut({int feed = 0, bool full = false}) =>
      invokeElgin<void>(_channel, 'printer.cut', {'feed': feed, 'full': full});

  static Future<PrinterStatus> status() async {
    final raw = await invokeElgin<Map<Object?, Object?>>(_channel, 'printer.status');
    return PrinterStatus.fromMap(raw ?? const <Object?, Object?>{});
  }

  /// `DirectIO` — ESC/POS cru, para o que a API não cobre.
  static Future<void> raw(Uint8List escPos) =>
      invokeElgin<void>(_channel, 'printer.raw', {'bytes': escPos});

  static Future<void> beep({int times = 1, int onMs = 100, int offMs = 100}) =>
      invokeElgin<void>(_channel, 'printer.beep', {
        'times': times,
        'onMs': onMs,
        'offMs': offMs,
      });

  /// Versão do SDK e número de série do equipamento.
  static Future<Map<String, String>> info() async {
    final raw = await invokeElgin<Map<Object?, Object?>>(_channel, 'printer.info');
    return {
      for (final entry in (raw ?? const <Object?, Object?>{}).entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  }
}
