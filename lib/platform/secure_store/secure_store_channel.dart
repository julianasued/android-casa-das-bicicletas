/// Armazenamento seguro do terminal, no canal nativo.
///
/// Do lado Kotlin é `EncryptedSharedPreferences` com chave no Keystore do
/// Android. Não é `SharedPreferences` comum porque o que se guarda aqui é o
/// token que autoriza vender no nome da loja (§12 da integração com o M10).
///
/// Quando o canal não existe — emulador, teste — cai para uma implementação em
/// memória em vez de falhar: o aplicativo continua utilizável fora do terminal,
/// e nada sensível fica gravado onde não deveria.
library;

import 'package:flutter/services.dart';

import '../../data/session/secure_store.dart';

class SecureStoreChannel implements SecureStore {
  SecureStoreChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'br.com.casadasbicicletas.vendas/secure_store';

  final MethodChannel _channel;
  final InMemorySecureStore _fallback = InMemorySecureStore();
  bool _usingFallback = false;

  /// `true` quando o canal nativo não respondeu e os dados estão só em memória.
  bool get isUsingFallback => _usingFallback;

  @override
  Future<String?> read(String key) async {
    if (_usingFallback) return _fallback.read(key);
    try {
      return await _channel.invokeMethod<String>('read', {'key': key});
    } on MissingPluginException {
      _usingFallback = true;
      return _fallback.read(key);
    } on PlatformException {
      // Leitura que falha devolve "não existe": o efeito é pedir a senha do
      // terminal de novo, que é o desfecho seguro.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (_usingFallback) return _fallback.write(key, value);
    try {
      await _channel.invokeMethod<void>('write', {'key': key, 'value': value});
    } on MissingPluginException {
      _usingFallback = true;
      await _fallback.write(key, value);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (_usingFallback) return _fallback.delete(key);
    try {
      await _channel.invokeMethod<void>('delete', {'key': key});
    } on MissingPluginException {
      _usingFallback = true;
      await _fallback.delete(key);
    }
  }

  @override
  Future<void> clear() async {
    if (_usingFallback) return _fallback.clear();
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      _usingFallback = true;
      await _fallback.clear();
    }
  }
}
