/// Conferência da senha do vendedor sem internet.
///
/// Sem rede, `POST /auth/select-seller/` não responde, e sem ele ninguém entra
/// no terminal — o balcão parava numa troca de turno. Aqui o aparelho guarda,
/// a cada entrada **com** internet, uma prova da senha: PBKDF2-HMAC-SHA256 com
/// sal aleatório por vendedor. A senha em si nunca é gravada.
///
/// **Limites, de propósito.**
/// - Só entra offline quem já entrou com internet neste aparelho.
/// - A prova vale [validade] desde a última entrada com internet: senha trocada
///   ou vendedor desligado no servidor deixam de valer aqui em poucos dias.
/// - [tentativasMaximas] erros seguidos travam a entrada offline daquele
///   vendedor até a próxima entrada com internet — o PIN é curto, e sem trava
///   quem tivesse o aparelho na mão poderia testar todos.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/entities/seller.dart';
import 'secure_store.dart';

/// Resultado da conferência offline.
enum OfflinePinCheck {
  /// Senha confere: pode abrir a sessão offline.
  ok,

  /// Senha não confere. A tentativa foi contada.
  wrong,

  /// Erros demais: só a entrada com internet libera.
  locked,

  /// Este vendedor nunca entrou com internet neste aparelho, ou faz tempo.
  unknown,
}

class OfflinePinStore {
  OfflinePinStore(
    this._store, {
    DateTime Function()? clock,
    this.iteracoes = 10000,
  }) : _agora = clock ?? DateTime.now;

  static const String _chave = 'auth.offline_pins';

  static const Duration validade = Duration(days: 7);
  static const int tentativasMaximas = 5;

  final SecureStore _store;
  final DateTime Function() _agora;

  /// Custo do PBKDF2. Alto o bastante para atrasar quem tenta adivinhar, baixo
  /// o bastante para o M10 não travar a tela no toque do "Entrar".
  final int iteracoes;

  /// Guarda a prova da senha que o servidor acabou de aceitar.
  ///
  /// Também zera os erros: a entrada com internet é o que destrava.
  Future<void> remember(Seller seller, String pin) async {
    final sal = _salAleatorio();
    final registros = await _ler();
    registros['${seller.id}'] = {
      'name': seller.name,
      'salt': base64Encode(sal),
      'hash': base64Encode(_derivar(pin, sal, iteracoes)),
      'iterations': iteracoes,
      'saved_at': _agora().toUtc().toIso8601String(),
      'failures': 0,
    };
    await _gravar(registros);
  }

  /// Confere a senha digitada sem internet.
  Future<OfflinePinCheck> verify(int sellerId, String pin) async {
    final registros = await _ler();
    final registro = registros['$sellerId'];
    if (registro is! Map<String, Object?> || !_valido(registro)) {
      return OfflinePinCheck.unknown;
    }

    final falhas = (registro['failures'] as int?) ?? 0;
    if (falhas >= tentativasMaximas) return OfflinePinCheck.locked;

    final sal = base64Decode(registro['salt']! as String);
    final esperado = base64Decode(registro['hash']! as String);
    final custo = (registro['iterations'] as int?) ?? iteracoes;

    if (_iguais(_derivar(pin, sal, custo), esperado)) {
      if (falhas != 0) {
        registro['failures'] = 0;
        await _gravar(registros);
      }
      return OfflinePinCheck.ok;
    }

    registro['failures'] = falhas + 1;
    await _gravar(registros);
    return falhas + 1 >= tentativasMaximas
        ? OfflinePinCheck.locked
        : OfflinePinCheck.wrong;
  }

  /// Quantas tentativas ainda restam antes da trava.
  Future<int> remainingAttempts(int sellerId) async {
    final registro = (await _ler())['$sellerId'];
    if (registro is! Map<String, Object?>) return 0;
    final falhas = (registro['failures'] as int?) ?? 0;
    return max(0, tentativasMaximas - falhas);
  }

  /// Quem pode entrar sem internet neste aparelho — a lista da tela de entrada
  /// quando o servidor não responde.
  Future<List<Seller>> knownSellers() async {
    final registros = await _ler();
    final vendedores = <Seller>[
      for (final MapEntry(:key, :value) in registros.entries)
        if (value is Map<String, Object?> && _valido(value))
          Seller(id: int.parse(key), name: value['name']! as String),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return vendedores;
  }

  /// Apaga a prova de um vendedor — o servidor recusou a senha dele.
  Future<void> forget(int sellerId) async {
    final registros = await _ler();
    if (registros.remove('$sellerId') != null) await _gravar(registros);
  }

  // ---------------------------------------------------------------------------

  bool _valido(Map<String, Object?> registro) {
    final quando = DateTime.tryParse(registro['saved_at'] as String? ?? '');
    if (quando == null) return false;
    return _agora().difference(quando) <= validade;
  }

  Future<Map<String, Object?>> _ler() async {
    final bruto = await _store.read(_chave);
    if (bruto == null || bruto.isEmpty) return <String, Object?>{};
    try {
      final decodificado = jsonDecode(bruto);
      return decodificado is Map<String, Object?>
          ? decodificado
          : <String, Object?>{};
    } on FormatException {
      // Dado corrompido não pode travar a entrada: na próxima vez com internet
      // a prova é refeita.
      return <String, Object?>{};
    }
  }

  Future<void> _gravar(Map<String, Object?> registros) =>
      _store.write(_chave, jsonEncode(registros));

  static Uint8List _salAleatorio() {
    final gerador = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(16, (_) => gerador.nextInt(256)),
    );
  }

  /// PBKDF2-HMAC-SHA256 com um bloco só (32 bytes), RFC 8018.
  static List<int> _derivar(String pin, List<int> sal, int iteracoes) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var u = hmac.convert([...sal, 0, 0, 0, 1]).bytes;
    final resultado = List<int>.of(u);
    for (var i = 1; i < iteracoes; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < resultado.length; j++) {
        resultado[j] ^= u[j];
      }
    }
    return resultado;
  }

  /// Comparação em tempo constante.
  static bool _iguais(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diferenca = 0;
    for (var i = 0; i < a.length; i++) {
      diferenca |= a[i] ^ b[i];
    }
    return diferenca == 0;
  }
}
