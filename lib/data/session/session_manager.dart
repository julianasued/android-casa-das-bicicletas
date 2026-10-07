/// Estado de identidade do terminal (§1.1 e §1.2 da API).
///
/// Reúne o que todo cabeçalho de requisição precisa saber: qual loja, qual
/// dispositivo e qual token vale agora. Fica em um lugar só porque a regra de
/// precedência entre `terminal_token` e `session_token` é sutil — o primeiro
/// abre o aparelho, mas só o segundo autoriza operação — e reimplementá-la em
/// cada repositório seria reimplementá-la um pouco diferente em cada um.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/entities/seller.dart';
import '../../domain/entities/terminal_session.dart';
import 'secure_store.dart';

class _Keys {
  static const String baseUrl = 'config.base_url';
  static const String deviceId = 'config.device_id';
  static const String storeId = 'config.store_id';
  static const String storeCode = 'config.store_code';
  static const String terminal = 'auth.terminal';
  static const String session = 'auth.session';
}

class SessionManager extends ChangeNotifier {
  SessionManager(this._store);

  final SecureStore _store;

  String? _baseUrlOverride;
  String? _deviceId;
  int? _storeId;
  String? _storeCode;
  TerminalAuth? _terminal;
  SellerSession? _session;

  String? get baseUrlOverride => _baseUrlOverride;

  /// `X-Device-Id` — o identificador cadastrado em `Terminal.device_identifier`.
  String? get deviceId => _deviceId;

  int? get storeId => _storeId;

  /// Código da loja (`L1`), usado para compor o código de barras localmente.
  String? get storeCode => _storeCode;

  TerminalAuth? get terminal => _terminal;
  SellerSession? get session => _session;
  Seller? get seller => _session?.seller;

  /// O terminal já sabe para onde falar e com que identidade?
  bool get isConfigured =>
      (_deviceId?.isNotEmpty ?? false) && _storeId != null;

  bool get hasTerminalAuth => _terminal != null && !_terminal!.isExpired;
  bool get hasSellerSession => _session != null && !_session!.isExpired;

  /// Token a usar na requisição.
  ///
  /// A sessão do vendedor tem precedência: é ela que carrega loja, terminal e
  /// vendedor, e é a única que o backend aceita para criar venda (§3.4.1). O
  /// token do terminal só responde pelas duas rotas de seleção (§2.2, §2.3).
  String? get bearerToken {
    if (hasSellerSession) return _session!.sessionToken;
    if (hasTerminalAuth) return _terminal!.terminalToken;
    return null;
  }

  Future<void> restore() async {
    _baseUrlOverride = await _store.read(_Keys.baseUrl);
    _deviceId = await _store.read(_Keys.deviceId);
    _storeCode = await _store.read(_Keys.storeCode);

    final rawStoreId = await _store.read(_Keys.storeId);
    _storeId = rawStoreId == null ? null : int.tryParse(rawStoreId);

    _terminal = _decodeTerminal(await _store.read(_Keys.terminal));
    _session = _decodeSession(await _store.read(_Keys.session));

    // Token vencido não vale como sessão restaurada: melhor pedir a senha do
    // terminal na abertura do que descobrir o 401 no meio de uma venda.
    if (_terminal?.isExpired ?? false) await clearTerminal();
    if (_session?.isExpired ?? false) await clearSession();

    notifyListeners();
  }

  Future<void> saveConfiguration({
    required String deviceId,
    required int storeId,
    String? baseUrl,
  }) async {
    _deviceId = deviceId;
    _storeId = storeId;
    _baseUrlOverride = (baseUrl?.trim().isEmpty ?? true) ? null : baseUrl!.trim();

    await _store.write(_Keys.deviceId, deviceId);
    await _store.write(_Keys.storeId, storeId.toString());
    if (_baseUrlOverride == null) {
      await _store.delete(_Keys.baseUrl);
    } else {
      await _store.write(_Keys.baseUrl, _baseUrlOverride!);
    }

    notifyListeners();
  }

  Future<void> saveStoreCode(String code) async {
    _storeCode = code;
    await _store.write(_Keys.storeCode, code);
    notifyListeners();
  }

  Future<void> saveTerminal(TerminalAuth auth) async {
    _terminal = auth;
    _storeId = auth.storeId;
    await _store.write(_Keys.terminal, jsonEncode(_encodeTerminal(auth)));
    await _store.write(_Keys.storeId, auth.storeId.toString());
    notifyListeners();
  }

  Future<void> saveSession(SellerSession session) async {
    _session = session;
    await _store.write(_Keys.session, jsonEncode(_encodeSession(session)));
    notifyListeners();
  }

  /// Troca de vendedor: encerra a sessão e mantém o terminal aberto.
  Future<void> clearSession() async {
    _session = null;
    await _store.delete(_Keys.session);
    notifyListeners();
  }

  /// Fecha o aparelho por completo — sessão e terminal.
  Future<void> clearTerminal() async {
    _session = null;
    _terminal = null;
    await _store.delete(_Keys.session);
    await _store.delete(_Keys.terminal);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Serialização
  // -------------------------------------------------------------------------

  Map<String, Object?> _encodeTerminal(TerminalAuth auth) => {
        'terminal_token': auth.terminalToken,
        'terminal_id': auth.terminalId,
        'store_id': auth.storeId,
        'expires_at': auth.expiresAt.toIso8601String(),
      };

  TerminalAuth? _decodeTerminal(String? raw) {
    final data = _decodeMap(raw);
    if (data == null) return null;
    return TerminalAuth(
      terminalToken: data['terminal_token']! as String,
      terminalId: data['terminal_id']! as int,
      storeId: data['store_id']! as int,
      expiresAt: DateTime.parse(data['expires_at']! as String),
    );
  }

  Map<String, Object?> _encodeSession(SellerSession session) => {
        'session_token': session.sessionToken,
        'seller_id': session.seller.id,
        'seller_name': session.seller.name,
        'store_id': session.storeId,
        'terminal_id': session.terminalId,
        'expires_at': session.expiresAt.toIso8601String(),
      };

  SellerSession? _decodeSession(String? raw) {
    final data = _decodeMap(raw);
    if (data == null) return null;
    return SellerSession(
      sessionToken: data['session_token']! as String,
      seller: Seller(
        id: data['seller_id']! as int,
        name: data['seller_name']! as String,
      ),
      storeId: data['store_id']! as int,
      terminalId: data['terminal_id']! as int,
      expiresAt: DateTime.parse(data['expires_at']! as String),
    );
  }

  Map<String, Object?>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      // Dado corrompido no armazenamento não pode travar a abertura do
      // terminal: vale mais pedir a senha de novo do que não abrir.
      return null;
    }
  }
}
