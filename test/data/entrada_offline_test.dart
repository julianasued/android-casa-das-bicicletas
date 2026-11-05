/// Entrada do vendedor sem internet.
///
/// Quem já entrou com internet neste aparelho entra de novo sem ela — a senha
/// é conferida contra a prova guardada (PBKDF2), nunca contra a senha em si. A
/// sessão aberta assim não tem token, e vira sessão do servidor sozinha quando
/// a rede volta: é isso que faz a fila subir.
library;

import 'dart:io';

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/remote/http_transport.dart';
import 'package:casa_das_bicicletas/data/repositories/auth_repository_impl.dart';
import 'package:casa_das_bicicletas/data/session/offline_pin_store.dart';
import 'package:casa_das_bicicletas/data/session/secure_store.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _joao = Seller(id: 12, name: 'João Silva');
const _maria = Seller(id: 15, name: 'Maria Costa');

void main() {
  group('prova da senha', () {
    late InMemorySecureStore store;
    late DateTime agora;
    late OfflinePinStore pins;

    setUp(() {
      store = InMemorySecureStore();
      agora = DateTime(2026, 11, 5, 9);
      pins = OfflinePinStore(store, clock: () => agora, iteracoes: 50);
    });

    test('a senha não é gravada, só a prova', () async {
      await pins.remember(_joao, '4321');
      final gravado = await store.read('auth.offline_pins');
      expect(gravado, isNot(contains('4321')));
    });

    test('confere a senha certa e recusa a errada', () async {
      await pins.remember(_joao, '4321');
      expect(await pins.verify(12, '4321'), OfflinePinCheck.ok);
      expect(await pins.verify(12, '1234'), OfflinePinCheck.wrong);
    });

    test('quem nunca entrou com internet não entra offline', () async {
      expect(await pins.verify(12, '4321'), OfflinePinCheck.unknown);
    });

    test('a prova vence em 7 dias', () async {
      await pins.remember(_joao, '4321');
      agora = agora.add(const Duration(days: 8));
      expect(await pins.verify(12, '4321'), OfflinePinCheck.unknown);
      expect(await pins.knownSellers(), isEmpty);
    });

    test('5 erros travam, e nem a senha certa destrava', () async {
      await pins.remember(_joao, '4321');
      for (var i = 0; i < 4; i++) {
        expect(await pins.verify(12, '0000'), OfflinePinCheck.wrong);
      }
      expect(await pins.verify(12, '0000'), OfflinePinCheck.locked);
      expect(await pins.verify(12, '4321'), OfflinePinCheck.locked);
    });

    test('entrar com internet destrava', () async {
      await pins.remember(_joao, '4321');
      for (var i = 0; i < 5; i++) {
        await pins.verify(12, '0000');
      }
      await pins.remember(_joao, '4321');
      expect(await pins.verify(12, '4321'), OfflinePinCheck.ok);
    });

    test('um erro seguido de acerto zera a contagem', () async {
      await pins.remember(_joao, '4321');
      await pins.verify(12, '0000');
      await pins.verify(12, '4321');
      expect(await pins.remainingAttempts(12), OfflinePinStore.tentativasMaximas);
    });

    test('lista quem pode entrar offline, em ordem de nome', () async {
      await pins.remember(_maria, '1111');
      await pins.remember(_joao, '2222');
      final nomes = [for (final s in await pins.knownSellers()) s.name];
      expect(nomes, ['João Silva', 'Maria Costa']);
    });
  });

  group('entrada no terminal', () {
    late bool online;
    late RecordingTransport http;
    late OfflinePinStore pins;

    HttpResponse responder(HttpRequest request) {
      if (!online) throw const SocketException('sem rede');
      final caminho = request.url.path;
      if (caminho.contains('select-seller')) {
        final corpo = request.body! as Map<String, Object?>;
        if (corpo['password'] != '4321') {
          return errorResponse(statusCode: 401, code: 'UNAUTHENTICATED');
        }
        return jsonResponse(const {
          'session_token': 'token-de-sessao',
          'seller_id': 12,
          'store_id': 1,
          'terminal_id': 7,
          'expires_in': 28800,
        });
      }
      if (caminho.contains('sellers')) {
        return jsonResponse(const {
          'results': [
            {'id': 12, 'name': 'João Silva'},
          ],
        });
      }
      return jsonResponse(const {'results': <Object?>[]});
    }

    Future<(AuthRepositoryImpl, AppDependencies)> montar() async {
      online = true;
      http = RecordingTransport(responder);
      final deps = buildTestDependencies(transport: http);
      await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
      await deps.session.saveTerminal(
        TerminalAuth(
          terminalToken: 'token-do-terminal',
          terminalId: 7,
          storeId: 1,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      pins = OfflinePinStore(InMemorySecureStore(), iteracoes: 50);
      final auth = AuthRepositoryImpl(
        api: deps.apiClient,
        session: deps.session,
        offlinePins: pins,
      );
      deps.session.renewer = auth.renewOfflineSession;
      return (auth, deps);
    }

    test('sem nunca ter entrado com internet, offline não entra', () async {
      final (auth, _) = await montar();
      online = false;

      final r = await auth.selectSeller(seller: _joao, password: '4321');
      expect(r, isA<Err<SellerSession>>());
      expect((r as Err<SellerSession>).failure, isA<NetworkFailure>());
    });

    test('depois de entrar com internet, entra sem ela', () async {
      final (auth, deps) = await montar();
      expect(await auth.selectSeller(seller: _joao, password: '4321'),
          isA<Ok<SellerSession>>());

      await deps.session.clearSession();
      online = false;

      final r = await auth.selectSeller(seller: _joao, password: '4321');
      expect(r, isA<Ok<SellerSession>>());
      expect(deps.session.session!.offline, isTrue);
      expect(deps.session.seller!.id, 12);
    });

    test('senha errada offline diz quantas tentativas restam', () async {
      final (auth, deps) = await montar();
      await auth.selectSeller(seller: _joao, password: '4321');
      await deps.session.clearSession();
      online = false;

      final r = await auth.selectSeller(seller: _joao, password: '0000');
      expect((r as Err<SellerSession>).failure.message, contains('restam 4'));
      expect(deps.session.hasSellerSession, isFalse);
    });

    test('a lista de vendedores vem do aparelho quando não há rede', () async {
      final (auth, _) = await montar();
      await auth.selectSeller(seller: _joao, password: '4321');
      online = false;

      final r = await auth.listTerminalSellers();
      expect(r, isA<Ok<List<Seller>>>());
      expect((r as Ok<List<Seller>>).value.single.name, 'João Silva');
    });

    test('a sessão offline não vai ao disco', () async {
      final (auth, deps) = await montar();
      await auth.selectSeller(seller: _joao, password: '4321');
      await deps.session.clearSession();
      online = false;
      await auth.selectSeller(seller: _joao, password: '4321');

      expect(await deps.secureStore.read('auth.session'), isNull);
    });

    test('a rede voltou: a próxima requisição troca a sessão pela do servidor',
        () async {
      final (auth, deps) = await montar();
      await auth.selectSeller(seller: _joao, password: '4321');
      await deps.session.clearSession();
      online = false;
      await auth.selectSeller(seller: _joao, password: '4321');

      online = true;
      await deps.apiClient.get('sync/pull/');

      expect(deps.session.session!.offline, isFalse);
      expect(
        http.lastRequest.headers['Authorization'],
        'Bearer token-de-sessao',
      );
    });

    test('senha recusada pelo servidor derruba a prova guardada', () async {
      final (auth, _) = await montar();
      await auth.selectSeller(seller: _joao, password: '4321');
      await auth.selectSeller(seller: _joao, password: '9999');

      expect(await pins.verify(12, '4321'), OfflinePinCheck.unknown);
    });
  });
}
