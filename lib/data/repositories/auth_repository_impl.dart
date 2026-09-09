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
import '../remote/api_client.dart';
import '../remote/api_endpoints.dart';
import '../remote/mappers.dart';
import '../remote/response_mapping.dart';
import '../session/session_manager.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required ApiClient api, required SessionManager session})
      : _api = api,
        _session = session;

  final ApiClient _api;
  final SessionManager _session;

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
  Future<Result<SellerSession>> selectSeller(int sellerId) async {
    final response = await _api.post(
      ApiEndpoints.selectSeller,
      body: {'seller_id': sellerId},
      requiresStore: false,
    );

    return mapApiResponse(response, (result) async {
      final data = result.data;
      final seller = _knownSellers[sellerId] ??
          Seller(id: sellerId, name: 'Vendedor $sellerId');
      final session = sellerSessionFromJson(data, seller: seller);
      await _session.saveSession(session);
      return session;
    });
  }

  @override
  Future<Result<void>> logout() async {
    // A revogação no servidor é o que encerra a sessão de fato (§2.6); a
    // limpeza local acontece de qualquer jeito, inclusive sem rede — deixar o
    // token no aparelho seria pior do que a sessão sobreviver no servidor até
    // vencer.
    final response = await _api.post(ApiEndpoints.logout, requiresStore: false);
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
      return store;
    });
  }
}
