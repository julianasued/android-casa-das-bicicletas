/// Estado da rede no terminal.
///
/// A Sprint 4 usa isto para uma coisa só: dizer ao operador, na barra da tela,
/// que o aparelho está sem rede — porque nesta sprint a venda ainda depende do
/// servidor, e é melhor saber antes de montar o carrinho. A fila local que
/// torna a operação de fato offline é da Sprint 9 (RF33–RF37), e vai assinar
/// este mesmo stream para disparar a sincronização quando a conexão voltar.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ConnectivityChannel extends ChangeNotifier {
  ConnectivityChannel({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName);

  static const String methodChannelName =
      'br.com.casadasbicicletas.vendas/connectivity';
  static const String eventChannelName =
      'br.com.casadasbicicletas.vendas/connectivity/status';

  final MethodChannel _methods;
  final EventChannel _events;
  StreamSubscription<Object?>? _subscription;

  bool _online = true;

  /// Otimista por padrão: fora do terminal (emulador, teste), presumir "sem
  /// rede" encheria a tela de aviso falso.
  bool get isOnline => _online;

  Future<void> start() async {
    _online = await _readOnce();
    notifyListeners();

    _subscription ??= _events.receiveBroadcastStream().listen(
      (event) {
        final online = event is bool ? event : _online;
        if (online != _online) {
          _online = online;
          notifyListeners();
        }
      },
      onError: (Object _) {
        // Canal indisponível não é sinal de rede indisponível.
      },
    );
  }

  Future<bool> _readOnce() async {
    try {
      return await _methods.invokeMethod<bool>('isOnline') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
