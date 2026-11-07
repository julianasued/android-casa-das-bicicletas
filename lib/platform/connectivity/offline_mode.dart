/// Modo offline do PDV: quando ligado, o aplicativo nem tenta o servidor.
///
/// Sem isto, cada ação ia primeiro à rede e só caía para o aparelho depois de
/// falhar — e com o Wi-Fi ligado mas a internet caída, a falha só vinha no
/// tempo-limite: até 20 segundos para o PIN, de novo para a busca, de novo para
/// finalizar a venda. No modo offline tudo vai direto ao aparelho, na hora.
///
/// **Dois jeitos de entrar, e eles saem de jeitos diferentes:**
///
/// - **Automático** — o Android avisa que a rede caiu, ou uma chamada ao
///   servidor falha por rede ou estoura o tempo. Sai sozinho: com a rede de
///   volta, o servidor é testado (`/health/`) de tempos em tempos, e
///   respondendo bem o modo desliga.
/// - **Manual** — o vendedor liga porque a internet está instável. Sai **só pelo
///   botão** "Voltar ao online": se saísse sozinho, a primeira resposta boa de
///   uma conexão instável o desligaria, e o balcão voltaria a travar. Fica
///   gravado no aparelho, para sobreviver a reabrir o aplicativo.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/session/secure_store.dart';
import 'connectivity_channel.dart';

class OfflineMode extends ChangeNotifier {
  OfflineMode({
    required ConnectivityChannel connectivity,
    required SecureStore store,
    this.probeInterval = const Duration(seconds: 30),
  })  : _connectivity = connectivity,
        _store = store;

  static const String _chaveManual = 'config.offline_manual';

  final ConnectivityChannel _connectivity;
  final SecureStore _store;

  /// De quanto em quanto tempo testar o servidor no modo automático.
  final Duration probeInterval;

  /// O servidor responde? Registrado na montagem do grafo — o cliente HTTP
  /// depende desta classe, e esta só precisa da pergunta.
  Future<bool> Function()? probe;

  bool _manual = false;
  bool _automatico = false;
  bool _testando = false;
  bool _iniciado = false;
  Timer? _timer;

  /// Ligado por qualquer dos dois motivos.
  bool get isOffline => _manual || _automatico;

  /// Ligado pelo vendedor — só o botão desliga.
  bool get isManual => _manual;

  /// Testando o servidor agora (para a tela mostrar que está tentando).
  bool get isProbing => _testando;

  Future<void> start() async {
    if (_iniciado) return;
    _iniciado = true;
    _manual = await _store.read(_chaveManual) == '1';
    _automatico = !_connectivity.isOnline;
    _connectivity.addListener(_aoMudarARede);
    _ajustarTimer();
    notifyListeners();
  }

  void _aoMudarARede() {
    if (!_connectivity.isOnline) {
      _definirAutomatico(true);
    } else {
      unawaited(_tentarVoltar());
    }
  }

  /// Uma chamada ao servidor falhou por rede ou tempo-limite.
  void reportNetworkFailure() => _definirAutomatico(true);

  /// "Tentar reconectar": testa o servidor agora. Devolve se voltou ao online.
  Future<bool> retryNow() async {
    await _tentarVoltar(mesmoSemRede: true);
    return !isOffline;
  }

  /// O vendedor liga o modo offline.
  Future<void> enterManual() async {
    _manual = true;
    await _store.write(_chaveManual, '1');
    notifyListeners();
  }

  /// "Voltar ao online": desliga o manual e confere o servidor na hora.
  ///
  /// Devolve se o servidor respondeu. Se não respondeu, o modo continua
  /// ligado — agora como automático, que sai sozinho quando a rede voltar.
  Future<bool> leaveManual() async {
    _manual = false;
    await _store.delete(_chaveManual);
    _definirAutomatico(true);
    await _tentarVoltar(mesmoSemRede: true);
    return !isOffline;
  }

  Future<void> _tentarVoltar({bool mesmoSemRede = false}) async {
    if (!_automatico || _testando) return;
    if (!mesmoSemRede && !_connectivity.isOnline) return;
    final pergunta = probe;
    if (pergunta == null) {
      // Sem como testar o servidor, vale o que o Android diz.
      if (_connectivity.isOnline) _definirAutomatico(false);
      return;
    }

    _testando = true;
    notifyListeners();
    bool respondeu;
    try {
      respondeu = await pergunta();
    } on Object {
      respondeu = false;
    }
    _testando = false;
    if (respondeu) {
      _definirAutomatico(false);
    } else {
      notifyListeners();
    }
  }

  void _definirAutomatico(bool valor) {
    if (_automatico == valor) return;
    _automatico = valor;
    _ajustarTimer();
    notifyListeners();
  }

  /// O teste periódico do servidor só existe enquanto o automático está
  /// ligado: online não há o que testar, e não gastar bateria à toa importa
  /// num aparelho que fica o dia inteiro no balcão.
  void _ajustarTimer() {
    if (_automatico) {
      _timer ??= Timer.periodic(probeInterval, (_) => _tentarVoltar());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_iniciado) _connectivity.removeListener(_aoMudarARede);
    super.dispose();
  }
}
