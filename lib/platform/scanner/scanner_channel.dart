/// Leitor de código de barras integrado do M10 Pro (§5 e §6 da integração).
///
/// O leitor não é chamado, ele dispara: o operador aponta e atira, e a leitura
/// chega por um `EventChannel`. Do lado Kotlin, um receptor de broadcast escuta
/// o serviço de scanner do aparelho; deste lado, as leituras viram um `Stream`
/// que qualquer tela pode ouvir.
///
/// O `broadcast` do stream não é detalhe: a tela do caixa e um indicador de
/// diagnóstico podem estar ouvindo ao mesmo tempo, e um stream de assinante
/// único faria a segunda escuta explodir.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/remote/mappers.dart';
import '../../domain/entities/barcode_read.dart';
import '../../domain/ports/barcode_scanner.dart';

class ScannerChannel implements BarcodeScanner {
  ScannerChannel({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName) {
    _controller = StreamController<BarcodeRead>.broadcast(
      onListen: _attach,
      onCancel: _detach,
    );
  }

  static const String methodChannelName = 'br.com.casadasbicicletas.vendas/scanner';
  static const String eventChannelName =
      'br.com.casadasbicicletas.vendas/scanner/reads';

  final MethodChannel _methods;
  final EventChannel _events;

  late final StreamController<BarcodeRead> _controller;
  StreamSubscription<Object?>? _subscription;

  @override
  Stream<BarcodeRead> get reads => _controller.stream;

  /// Leituras que não vêm do hardware — modo teclado e digitação manual.
  ///
  /// Entram no mesmo stream de propósito: para a tela, "chegou um código" é um
  /// evento só, e o modo do leitor é configuração do aparelho, não regra de
  /// negócio.
  void emitExternalRead(BarcodeRead read) {
    if (!_controller.isClosed) _controller.add(read);
  }

  void _attach() {
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final read = barcodeReadFromChannel(event);
          if (read.code.isNotEmpty) _controller.add(read);
        }
      },
      onError: (Object error) {
        // Falha do canal não fecha o stream: o leitor pode voltar, e a tela
        // continua aceitando digitação enquanto isso.
        _controller.addError(
          ScannerFailure(
            error is PlatformException
                ? (error.message ?? 'Falha no leitor de código de barras.')
                : 'Falha no leitor de código de barras.',
          ),
        );
      },
    );
  }

  void _detach() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  Future<Result<void>> start() async {
    try {
      await _methods.invokeMethod<void>('start');
      return const Ok(null);
    } on PlatformException catch (error) {
      return Err(ScannerFailure(error.message ?? 'Não foi possível iniciar o leitor.'));
    } on MissingPluginException {
      return const Err(
        ScannerFailure('Leitor indisponível: canal nativo ausente neste aparelho.'),
      );
    }
  }

  @override
  Future<Result<void>> stop() async {
    try {
      await _methods.invokeMethod<void>('stop');
      return const Ok(null);
    } on PlatformException catch (error) {
      return Err(ScannerFailure(error.message ?? 'Falha ao encerrar o leitor.'));
    } on MissingPluginException {
      return const Ok(null);
    }
  }

  /// Diagnóstico do leitor, para o POC responder com fato o que a documentação
  /// deixa em aberto.
  ///
  /// A Elgin publica módulo de scanner apenas para o **SmartPOS**
  /// (`com.elgin.e1.Scanner.Scanner`); para o M10 não há API documentada. Este
  /// levantamento diz quais ações estão sendo escutadas, se algum pacote
  /// candidato de serviço existe no aparelho e se a classe do SmartPOS está
  /// presente — que é o dado que decide o caminho da integração.
  Future<Map<String, Object?>> probe() async {
    try {
      final raw = await _methods.invokeMapMethod<String, Object?>('probe');
      return raw ?? const <String, Object?>{};
    } on PlatformException catch (error) {
      return <String, Object?>{'error': error.message};
    } on MissingPluginException {
      return const <String, Object?>{
        'error': 'Canal do leitor indisponível neste aparelho.',
      };
    }
  }

  /// Troca as ações de broadcast escutadas, sem nova versão do aplicativo.
  ///
  /// Existe porque a ação real do M10 não está documentada: descoberta no
  /// aparelho, ela é aplicada aqui.
  Future<void> configure({
    List<String>? actions,
    List<String>? extraKeys,
  }) async {
    try {
      await _methods.invokeMethod<void>('configure', {
        if (actions != null) 'actions': actions,
        if (extraKeys != null) 'extra_keys': extraKeys,
      });
    } on PlatformException {
      // Configuração recusada não derruba a tela: as ações anteriores seguem.
    } on MissingPluginException {
      // Fora do terminal não há o que configurar.
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> dispose() async {
    _detach();
    await _controller.close();
  }
}
