/// Autenticação do terminal e seleção do vendedor (API §2).
///
/// Os tokens são gravados no armazenamento seguro assim que chegam, e não ao
/// final do fluxo: se o aplicativo for encerrado entre a autenticação do
/// aparelho e a seleção do vendedor, o terminal continua aberto e o operador
/// não digita a senha de novo.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/seller.dart';
import '../../domain/entities/store.dart';
import '../../domain/entities/terminal_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/reference_cache.dart';
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';
import '../session/offline_pin_store.dart';
import '../session/session_manager.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required ApiClient api,
    required SessionManager session,
    ReferenceCache? cache,
    OfflinePinStore? offlinePins,
  })  : _api = api,
        _session = session,
        _cache = cache,
        _offlinePins = offlinePins;

  /// Prova da senha de quem já entrou com internet. Ausente nos testes que não
  /// tratam de entrada offline — aí sem rede ninguém entra, como antes.
  final OfflinePinStore? _offlinePins;

  /// Quem entrou sem internet e com que senha, para trocar a sessão offline por
  /// uma do servidor quando a rede voltar. Só na memória, nunca no disco.
  ({Seller seller, String pin})? _aRenovar;

  /// Duração da sessão aberta offline — o expediente, como a do servidor.
  static const Duration _duracaoOffline = Duration(hours: 8);

  final ApiClient _api;
  final SessionManager _session;

  /// Opcional: o repositório funciona sem cache, e é assim que os testes que só
  /// olham o contrato REST seguem sem banco.
  final ReferenceCache? _cache;

  /// Guardados da última listagem: a resposta da seleção (§2.3) devolve
  /// `seller_id`, e o nome que aparece no documento impresso vem daqui.
  final Map<int, Seller> _knownSellers = <int, Seller>{};

  @override
  Future<Result<TerminalAuth>> authenticateTerminal({
    required int storeId,
    required String terminalPassword,
  }) async {
    final deviceId = _session.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return const Err(
        ConfigurationFailure(
          'Terminal sem identificador configurado. Informe o X-Device-Id cadastrado.',
        ),
      );
    }

    final response = await _api.post(
      ApiEndpoints.terminalAuth,
      body: {'store_id': storeId, 'terminal_password': terminalPassword},
      // A loja ainda não está definida na sessão: ela vem no corpo, e o
      // cabeçalho `X-Store-Id` seria redundante antes de existir token.
      requiresStore: false,
    );

    return mapApiResponse(response, (result) async {
      final data = result.data;
      final auth = terminalAuthFromJson(data);
      await _session.saveTerminal(auth);
      return auth;
    });
  }

  @override
  Future<Result<List<Seller>>> listTerminalSellers() async {
    final response = await _api.get(ApiEndpoints.terminalSellers, requiresStore: false);

    // Sem internet, a lista é de quem pode entrar offline neste aparelho.
    if (response case Err(failure: NetworkFailure())) {
      final conhecidos = await _offlinePins?.knownSellers() ?? const <Seller>[];
      if (conhecidos.isNotEmpty) {
        _knownSellers
          ..clear()
          ..addEntries(conhecidos.map((s) => MapEntry(s.id, s)));
        return Ok(conhecidos);
      }
    }

    return mapApiResponse(response, (result) async {
      final data = result.data;
      final sellers = [
        for (final item in readResults(data)) sellerFromJson(item),
      ];
      _knownSellers
        ..clear()
        ..addEntries(sellers.map((seller) => MapEntry(seller.id, seller)));
      return sellers;
    });
  }

  @override
  Future<Result<SellerSession>> selectSeller({
    required Seller seller,
    required String password,
  }) async {
    final online = await _selectSellerOnline(seller: seller, password: password);
    if (online case Err(failure: NetworkFailure())) {
      final offline = await _selectSellerOffline(seller: seller, password: password);
      if (offline != null) return offline;
    }
    return online;
  }

  Future<Result<SellerSession>> _selectSellerOnline({
    required Seller seller,
    required String password,
  }) async {
    final response = await _api.post(
      ApiEndpoints.selectSeller,
      body: {'seller_id': seller.id, 'password': password},
      requiresStore: false,
    );

    final resultado = await mapApiResponse(response, (result) async {
      // Quem chama já sabe de quem é o PIN que acabou de ser digitado. Tirar o
      // nome de um cache de listagem fazia a sessão carimbar "Vendedor 12" na
      // venda quando a lista não estava em memória.
      final session = sellerSessionFromJson(result.data, seller: seller);
      await _session.saveSession(session);
      return session;
    });

    switch (resultado) {
      case Ok():
        // O servidor aceitou: é esta senha que vale para a próxima entrada sem
        // internet.
        _aRenovar = null;
        await _offlinePins?.remember(seller, password);
      case Err(failure: UnauthenticatedFailure() || PermissionFailure()):
        // Recusada pelo servidor: a prova guardada pode ser de uma senha que
        // já foi trocada, e não pode continuar abrindo o terminal offline.
        await _offlinePins?.forget(seller.id);
      case Err():
        break;
    }
    return resultado;
  }

  /// Confere a senha no aparelho. `null` quando não há como entrar offline —
  /// aí a falha de rede segue seu caminho.
  Future<Result<SellerSession>?> _selectSellerOffline({
    required Seller seller,
    required String password,
  }) async {
    final pins = _offlinePins;
    final storeId = _session.storeId;
    if (pins == null || storeId == null) return null;

    switch (await pins.verify(seller.id, password)) {
      case OfflinePinCheck.ok:
        final session = SellerSession(
          sessionToken: '',
          seller: seller,
          storeId: storeId,
          terminalId: _session.terminal?.terminalId ?? 0,
          expiresAt: DateTime.now().add(_duracaoOffline),
          offline: true,
        );
        await _session.saveSession(session);
        _aRenovar = (seller: seller, pin: password);
        return Ok(session);

      case OfflinePinCheck.wrong:
        final restam = await pins.remainingAttempts(seller.id);
        return Err(
          UnauthenticatedFailure(
            'Senha incorreta. Sem internet, restam $restam '
            '${restam == 1 ? 'tentativa' : 'tentativas'}.',
          ),
        );

      case OfflinePinCheck.locked:
        return const Err(
          BusinessRuleFailure(
            'Muitas tentativas erradas sem internet. A entrada deste vendedor '
            'só volta quando houver internet.',
          ),
        );

      case OfflinePinCheck.unknown:
        return const Err(
          NetworkFailure(
            'Sem internet, e este vendedor ainda não entrou neste aparelho com '
            'internet nos últimos 7 dias. Entre uma vez com internet para '
            'liberar a entrada offline.',
          ),
        );
    }
  }

  /// Troca a sessão aberta offline por uma do servidor.
  ///
  /// Chamada antes de qualquer requisição enquanto a sessão for offline — é o
  /// que faz a fila subir sozinha quando a rede volta. Sem rede, nada muda.
  /// Se o servidor recusar a senha (trocada, vendedor desligado), a sessão
  /// offline cai: vender no nome de quem o servidor não reconhece não pode
  /// continuar.
  Future<void> renewOfflineSession() async {
    final atual = _session.session;
    final pendente = _aRenovar;
    if (atual == null || !atual.offline) return;
    if (pendente == null || pendente.seller.id != atual.seller.id) return;

    final resultado = await _selectSellerOnline(
      seller: pendente.seller,
      password: pendente.pin,
    );
    if (resultado case Err(failure: UnauthenticatedFailure() || PermissionFailure())) {
      _aRenovar = null;
      await _session.clearSession();
    }
  }

  @override
  Future<Result<void>> logout() async {
    // A revogação no servidor é o que encerra a sessão de fato (§2.6); a
    // limpeza local acontece de qualquer jeito, inclusive sem rede — deixar o
    // token no aparelho seria pior do que a sessão sobreviver no servidor até
    // vencer.
    final response = await _api.post(ApiEndpoints.logout, requiresStore: false);
    _aRenovar = null;
    await _session.clearTerminal();

    return switch (response) {
      Err(:final failure) when failure is NetworkFailure => const Ok<void>(null),
      Err(:final failure) => Err<void>(failure),
      Ok() => const Ok<void>(null),
    };
  }

  @override
  Future<Result<Store>> currentStore() async {
    final storeId = _session.storeId;
    if (storeId == null) {
      return const Err(ConfigurationFailure('Terminal sem loja definida.'));
    }

    final response = await _api.get(ApiEndpoints.store(storeId));
    return mapApiResponse(response, (result) async {
      final data = result.data;
      final store = storeFromJson(data);
      await _session.saveStoreCode(store.code);
      // Guardar nome, CNPJ e endereço: é o cabeçalho da notinha, e sem isto o
      // terminal não monta documento sozinho (Sprint 9, Fase 2).
      await _cache?.learnStore(store);
      return store;
    });
  }
}
