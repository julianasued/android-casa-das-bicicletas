/// Estado da tela de POC do M10.
///
/// Fala direto com o plugin `elgin_m10` — sem repositório, sem venda, sem
/// servidor. É o ponto do aplicativo onde se prova que o hardware responde, e
/// misturar regra de negócio aqui tiraria justamente isso: quando algo falha,
/// tem que ser culpa do aparelho ou da ponte, nunca de uma terceira camada.
///
/// O que interessa registrar é o desfecho de cada operação — última leitura,
/// último erro, estado de cada periférico —, porque é o que se olha depois,
/// quando alguém pergunta "o que aconteceu no aparelho?".
library;

import 'dart:async';

import 'package:elgin_m10/elgin_m10.dart';
import 'package:flutter/foundation.dart';

import 'test_image.dart';

/// Uma leitura do leitor integrado, com a hora em que chegou.
class ScanEvent {
  const ScanEvent({required this.code, required this.at});

  final String code;
  final DateTime at;
}

class M10PocController extends ChangeNotifier {
  M10PocController();

  StreamSubscription<String>? _subscription;

  PrinterStatus? _printerStatus;
  Map<String, String> _printerInfo = const <String, String>{};
  ScanEvent? _lastRead;
  int _readCount = 0;

  /// A lâmina fica três linhas acima da cabeça de impressão — medido no M10
  /// Pro em 09/2026 com uma régua de 12 linhas, das quais sobraram 9. Cortar
  /// sem avançar isto come o fim do cupom, que foi o que decepou o EAN-8.
  static const int _avancoDoCorte = 3;

  bool _printerOpen = false;
  bool _displayOpen = false;
  bool _scannerRunning = false;
  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;

  /// Parâmetros de `AbreConexaoImpressora`, editáveis na tela.
  ///
  /// O padrão `(6, "M8")` é o do pacote 02.34.04; a documentação pública
  /// descreve `tipo` de 1 a 5 e o exemplo oficial usa `(5, "")`. Como o
  /// bytecode dá a assinatura mas não os valores aceitos, quem decide é o
  /// aparelho — e trocar aqui evita uma recompilação para descobrir.
  int connectionType = 6;
  String connectionModel = 'M8';

  PrinterStatus? get printerStatus => _printerStatus;
  Map<String, String> get printerInfo => _printerInfo;
  ScanEvent? get lastRead => _lastRead;
  int get readCount => _readCount;
  bool get printerOpen => _printerOpen;
  bool get displayOpen => _displayOpen;
  bool get scannerRunning => _scannerRunning;
  bool get busy => _busy;
  String? get lastError => _lastError;
  String? get lastSuccess => _lastSuccess;

  // -------------------------------------------------------------------------
  // Impressora
  // -------------------------------------------------------------------------

  Future<void> openPrinter() => _run('Abrir impressora', () async {
        await ElginPrinter.open(type: connectionType, model: connectionModel);
        _printerOpen = true;
        _printerInfo = await ElginPrinter.info();
      });

  Future<void> closePrinter() => _run('Fechar impressora', () async {
        await ElginPrinter.close();
        _printerOpen = false;
      });

  /// Toda impressão abre a conexão antes.
  ///
  /// O estado é guardado aqui só para poupar a chamada: `AbreConexaoImpressora`
  /// devolve "conexão já ativa" quando já está aberta, e o plugin passou a
  /// tratar isso como sucesso — reabrir por engano não derruba mais a
  /// impressora.
  Future<void> _withPrinter(Future<void> Function() action) async {
    if (!_printerOpen) {
      await ElginPrinter.open(type: connectionType, model: connectionModel);
      _printerOpen = true;
    }
    await action();
  }

  Future<void> printText() => _run('Imprimir texto', () async {
        await _withPrinter(() async {
          await ElginPrinter.printText(
            'CASA DAS BICICLETAS',
            align: PrinterAlign.center,
            style: PrinterStyle.of(bold: true),
          );
          await ElginPrinter.printText('--------------------------------');
          await ElginPrinter.printText('Alinhado a esquerda');
          await ElginPrinter.printText('Centralizado', align: PrinterAlign.center);
          await ElginPrinter.printText('A direita', align: PrinterAlign.right);
          await ElginPrinter.printText(
            'Negrito',
            style: PrinterStyle.of(bold: true),
          );
          await ElginPrinter.printText(
            'Sublinhado',
            style: PrinterStyle.of(underline: true),
          );
          await ElginPrinter.printText(
            'Altura dupla',
            size: PrinterSize.of(height: PrinterSize.height2x),
          );
          await ElginPrinter.printText(
            'Largura dupla',
            size: PrinterSize.of(width: PrinterSize.width2x),
          );
          await ElginPrinter.feed(2);
          await ElginPrinter.cut(feed: _avancoDoCorte);
        });
      });

  /// Uma via por simbologia, com dado válido para cada uma.
  ///
  /// O comprimento importa: EAN-13 quer 12–13 dígitos e EAN-8 quer 7–8. Mandar
  /// o dado errado devolve erro do SDK, e é bom que o POC mostre a diferença
  /// entre "a impressora falhou" e "o dado não serve para esta simbologia".
  Future<void> printBarcodes() => _run('Imprimir código de barras', () async {
        await _withPrinter(() async {
          await ElginPrinter.printText('CODE 128', align: PrinterAlign.center);
          await ElginPrinter.printBarcode(
            'SALE-L1-7F3A9C2B',
            type: BarcodeType.code128,
          );
          await ElginPrinter.feed(1);

          await ElginPrinter.printText('EAN-13', align: PrinterAlign.center);
          await ElginPrinter.printBarcode('789123456789', type: BarcodeType.ean13);
          await ElginPrinter.feed(1);

          await ElginPrinter.printText('EAN-8', align: PrinterAlign.center);
          await ElginPrinter.printBarcode('7891234', type: BarcodeType.ean8);
          await ElginPrinter.feed(2);
          await ElginPrinter.cut(feed: _avancoDoCorte);
        });
      });

  Future<void> printQrCode() => _run('Imprimir QR Code', () async {
        await _withPrinter(() async {
          await ElginPrinter.printText('QR CODE', align: PrinterAlign.center);
          await ElginPrinter.printQrCode(
            'https://casadasbicicletas.com.br/venda/TESTE',
          );
          await ElginPrinter.feed(2);
          await ElginPrinter.cut(feed: _avancoDoCorte);
        });
      });

  Future<void> printImage() => _run('Imprimir imagem', () async {
        await _withPrinter(() async {
          await ElginPrinter.printImageFromBytes(testImageBytes());
          await ElginPrinter.feed(2);
          await ElginPrinter.cut(feed: _avancoDoCorte);
        });
      });

  Future<void> feedPaper() =>
      _run('Avançar papel', () => _withPrinter(() => ElginPrinter.feed(3)));

  Future<void> cutPaper() =>
      _run('Cortar papel', () => _withPrinter(() => ElginPrinter.cut(feed: _avancoDoCorte)));

  Future<void> checkPrinter() => _run('Consultar status', () async {
        await _withPrinter(() async {
          _printerStatus = await ElginPrinter.status();
        });
      });

  Future<void> beep() =>
      _run('Sinal sonoro', () => _withPrinter(() => ElginPrinter.beep()));

  /// Fecha e reabre — o teste de recuperação depois de um erro.
  Future<void> reconnectPrinter() => _run('Reabrir impressora', () async {
        if (_printerOpen) {
          await ElginPrinter.close();
          _printerOpen = false;
        }
        await ElginPrinter.open(type: connectionType, model: connectionModel);
        _printerOpen = true;
        await ElginPrinter.initialize();
        _printerStatus = await ElginPrinter.status();
      });

  // -------------------------------------------------------------------------
  // Leitor
  // -------------------------------------------------------------------------

  /// Assina o stream **antes** de ligar o leitor.
  ///
  /// É a assinatura que registra o ouvinte da E1 no lado nativo; ligar sem
  /// ouvinte dispararia uma leitura sem destino.
  Future<void> startScanner() => _run('Iniciar leitor', () async {
        _subscription ??= ElginScanner.onScan.listen(
          (code) {
            _lastRead = ScanEvent(code: code, at: DateTime.now());
            _readCount++;
            notifyListeners();
          },
          onError: (Object error) {
            _lastError = 'Leitor: $error';
            notifyListeners();
          },
        );

        await ElginScanner.start();
        _scannerRunning = true;
      });

  Future<void> stopScanner() => _run('Parar leitor', () async {
        await ElginScanner.stop();
        _scannerRunning = false;

        await _subscription?.cancel();
        _subscription = null;
      });

  // -------------------------------------------------------------------------
  // Display do cliente
  // -------------------------------------------------------------------------

  Future<void> showOnDisplay(String message) =>
      _run('Enviar ao display', () async {
        if (!_displayOpen) {
          await ElginDisplay.open();
          _displayOpen = true;
        }
        await ElginDisplay.showText(
          message.trim().isEmpty ? 'Bem-vindo' : message.trim(),
        );
      });

  Future<void> clearDisplay() => _run('Limpar display', () async {
        if (!_displayOpen) {
          await ElginDisplay.open();
          _displayOpen = true;
        }
        // Não existe "limpar" na API: reinicializar devolve o display ao estado
        // inicial sem derrubar a conexão.
        await ElginDisplay.reinitialize();
      });

  Future<void> closeDisplay() => _run('Fechar display', () async {
        await ElginDisplay.close();
        _displayOpen = false;
      });

  // -------------------------------------------------------------------------

  /// Executa a operação registrando o desfecho — é isso que o POC precisa ver.
  ///
  /// `ElginException` vira mensagem com o código do SDK, porque é o número que
  /// se leva para a tabela de erros; qualquer outra exceção aparece como veio,
  /// sem ser confundida com falha do aparelho.
  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;

    _busy = true;
    _lastError = null;
    _lastSuccess = null;
    notifyListeners();

    try {
      await action();
      _lastSuccess = '$label: OK';
    } on ElginException catch (error) {
      final code = error.code == null ? '' : ' (código ${error.code})';
      _lastError = '$label: ${error.message}$code';

      // Uma falha invalida o estado de conexão: insistir sobre uma conexão que
      // o SDK considera perdida é a receita para o erro se repetir.
      if (error.kind != ElginFailureKind.invalidArgument) {
        _printerOpen = false;
        _displayOpen = false;
      }
    } catch (error) {
      _lastError = '$label: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
