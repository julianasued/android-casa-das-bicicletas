/// Modo offline: ligado, nada vai ao servidor e tudo responde na hora.
///
/// O automático entra quando a rede cai e sai sozinho quando o servidor volta a
/// responder. O manual, ligado pelo vendedor, só sai pelo botão.
library;

import 'dart:io';

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/remote/api_client.dart';
import 'package:casa_das_bicicletas/data/repositories/auth_repository_impl.dart';
import 'package:casa_das_bicicletas/data/session/offline_pin_store.dart';
import 'package:casa_das_bicicletas/data/session/secure_store.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_session.dart';
import 'package:casa_das_bicicletas/platform/connectivity/connectivity_channel.dart';
import 'package:casa_das_bicicletas/platform/connectivity/offline_mode.dart';
import 'package:casa_das_bicicletas/presentation/shared/modo_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Rede controlada pelo teste, sem canal nativo.
class _Rede extends ConnectivityChannel {
  bool online = true;

  @override
  bool get isOnline => online;

  void mudar(bool valor) {
    online = valor;
    notifyListeners();
  }
}

void main() {
  late _Rede rede;
  late InMemorySecureStore store;
  late bool servidorResponde;
  late int perguntas;

  OfflineMode novoModo() => OfflineMode(
        connectivity: rede,
        store: store,
        probeInterval: const Duration(hours: 1),
      )..probe = () async {
          perguntas++;
          return servidorResponde;
        };

  setUp(() {
    rede = _Rede();
    store = InMemorySecureStore();
    servidorResponde = true;
    perguntas = 0;
  });

  group('automático', () {
    test('nasce ligado quando o aparelho abre sem rede', () async {
      rede.online = false;
      final modo = novoModo();
      await modo.start();

      expect(modo.isOffline, isTrue);
      expect(modo.isManual, isFalse);
      modo.dispose();
    });

    test('liga quando a rede cai e desliga quando o servidor responde',
        () async {
      final modo = novoModo();
      await modo.start();
      expect(modo.isOffline, isFalse);

      rede.mudar(false);
      expect(modo.isOffline, isTrue);

      rede.mudar(true);
      await pumpEventQueue();
      expect(perguntas, 1);
      expect(modo.isOffline, isFalse);
      modo.dispose();
    });

    test('rede de volta mas servidor fora: continua offline', () async {
      final modo = novoModo();
      await modo.start();
      servidorResponde = false;

      modo.reportNetworkFailure();
      rede.mudar(true);
      await pumpEventQueue();

      expect(modo.isOffline, isTrue);
      expect(await modo.retryNow(), isFalse);

      servidorResponde = true;
      expect(await modo.retryNow(), isTrue);
      modo.dispose();
    });
  });

  group('manual', () {
    test('não sai sozinho, nem com a rede e o servidor bem', () async {
      final modo = novoModo();
      await modo.start();
      await modo.enterManual();

      rede.mudar(false);
      rede.mudar(true);
      await pumpEventQueue();
      await modo.retryNow();

      expect(modo.isOffline, isTrue);
      expect(modo.isManual, isTrue);
      modo.dispose();
    });

    test('sobrevive a reabrir o aplicativo', () async {
      final primeiro = novoModo();
      await primeiro.start();
      await primeiro.enterManual();
      primeiro.dispose();

      final segundo = novoModo();
      await segundo.start();
      expect(segundo.isManual, isTrue);
      segundo.dispose();
    });

    test('"Voltar ao online" sai quando o servidor responde', () async {
      final modo = novoModo();
      await modo.start();
      await modo.enterManual();

      expect(await modo.leaveManual(), isTrue);
      expect(modo.isOffline, isFalse);
      expect(await store.read('config.offline_manual'), isNull);
      modo.dispose();
    });

    test('"Voltar ao online" sem servidor fica no automático', () async {
      final modo = novoModo();
      await modo.start();
      await modo.enterManual();
      servidorResponde = false;

      expect(await modo.leaveManual(), isFalse);
      expect(modo.isOffline, isTrue);
      expect(modo.isManual, isFalse);
      modo.dispose();
    });
  });

  group('cliente HTTP', () {
    test('no modo offline responde na hora, sem ir à rede', () async {
      final http = RecordingTransport.empty();
      final deps = buildTestDependencies(transport: http);
      deps.apiClient.forcedOffline = () => true;

      final r = await deps.apiClient.get('products/');

      expect(http.requests, isEmpty);
      final falha = (r as Err<ApiResponse>).failure;
      expect(falha, isA<NetworkFailure>());
      expect(falha.message, ApiClient.offlineModeMessage);
    });

    test('falha de rede avisa, e é isso que liga o automático', () async {
      final deps = buildTestDependencies(
        transport: RecordingTransport((_) => throw const SocketException('x')),
      );
      var avisos = 0;
      deps.apiClient.onNetworkFailure = () => avisos++;

      await deps.apiClient.get('products/');

      expect(avisos, 1);
    });

    test('teste do servidor usa /health/ e ignora o modo offline', () async {
      final http = RecordingTransport.empty();
      final deps = buildTestDependencies(transport: http);
      deps.apiClient.forcedOffline = () => true;

      expect(await deps.apiClient.isServerReachable(), isTrue);
      expect(http.lastRequest.url.path, endsWith('/health/'));

      final fora = buildTestDependencies(
        transport: RecordingTransport((_) => throw const SocketException('x')),
      );
      expect(await fora.apiClient.isServerReachable(), isFalse);
    });
  });

  test('PIN no modo offline: conferido no aparelho, sem chamada de rede',
      () async {
    final http = RecordingTransport.empty();
    final deps = buildTestDependencies(transport: http);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    final pins = OfflinePinStore(InMemorySecureStore(), iteracoes: 50);
    await pins.remember(const Seller(id: 12, name: 'João Silva'), '4321');
    final auth = AuthRepositoryImpl(
      api: deps.apiClient,
      session: deps.session,
      offlinePins: pins,
    );
    deps.apiClient.forcedOffline = () => true;

    final r = await auth.selectSeller(
      seller: const Seller(id: 12, name: 'João Silva'),
      password: '4321',
    );

    expect(r, isA<Ok<SellerSession>>());
    expect(deps.session.session!.offline, isTrue);
    expect(http.requests, isEmpty);
  });

  group('na tela', () {
    Future<OfflineMode> montar(WidgetTester tester, {bool manual = false}) async {
      final modo = novoModo();
      await modo.start();
      if (manual) await modo.enterManual();
      final deps = buildTestDependencies(offlineMode: modo);

      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            builder: (context, child) => FaixaDoModoOffline(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => ItemDoModoOffline(
                  onTap: () => alternarModoOffline(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return modo;
    }

    testWidgets('sem modo offline, não há faixa', (tester) async {
      await montar(tester);
      expect(find.byKey(const Key('faixa-modo-offline')), findsNothing);
      expect(find.text('Usar modo offline'), findsOneWidget);
    });

    testWidgets('ligar pelo menu pede confirmação e mostra a faixa',
        (tester) async {
      final modo = await montar(tester);

      await tester.tap(find.byKey(const Key('item-modo-offline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar-modo-offline')));
      await tester.pumpAndSettle();

      expect(modo.isManual, isTrue);
      expect(find.byKey(const Key('faixa-modo-offline')), findsOneWidget);
      expect(find.text('VOLTAR AO ONLINE'), findsOneWidget);
    });

    testWidgets('"Voltar ao online" na faixa desliga e some com ela',
        (tester) async {
      final modo = await montar(tester, manual: true);

      await tester.tap(find.byKey(const Key('botao-da-faixa-offline')));
      await tester.pumpAndSettle();

      expect(modo.isOffline, isFalse);
      expect(find.byKey(const Key('faixa-modo-offline')), findsNothing);
    });

    testWidgets('no automático, a faixa oferece tentar reconectar',
        (tester) async {
      final modo = await montar(tester);
      modo.reportNetworkFailure();
      await tester.pump();

      expect(find.text('TENTAR RECONECTAR'), findsOneWidget);
      // O teste periódico do servidor está correndo: para antes do fim.
      modo.dispose();
    });
  });
}
