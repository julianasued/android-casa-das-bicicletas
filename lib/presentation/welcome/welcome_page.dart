/// Tela inicial do terminal, antes de qualquer identificação.
///
/// É o estado em que o M10 passa a maior parte do dia: ligado no balcão, sem
/// ninguém autenticado, esperando a próxima venda. Por isso ela tem uma ação só
/// e ela ocupa a largura inteira — quem chega está em pé, com o cliente na
/// frente, e não deve precisar procurar onde tocar.
///
/// A identificação do aparelho fica visível de propósito. Com dois terminais
/// iguais no balcão, saber em qual se está evita venda lançada na loja errada.
///
/// A aparência segue `fluxo-frontend/handoff/tela-inicio.html`: cabeçalho claro
/// com o terminal sublinhado em laranja, indicador de rede, a logo da loja, a
/// plaquinha do aparelho, o botão em cápsula laranja e a onda de três faixas.
/// A referência é de 1280x800 em paisagem; aqui as medidas se ajustam, porque
/// o alvo é o M10.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../platform/connectivity/connectivity_channel.dart';
import '../shared/brand.dart';

/// Tons próprios desta tela — o cabeçalho claro não aparece nas outras.
class _Tons {
  const _Tons._();

  static const Color tituloTerminal = Color(0xFF3C4257);
  static const Color fundoPilula = Color(0xFFF2F4FA);
  static const Color bordaPilula = Color(0xFFDFE4F1);
  static const Color rotulo = Color(0xFF8A92AB);
  static const Color relogio = Color(0xFF6B7490);
  static const Color etiqueta = Color(0xFFE4E9F6);
  static const Color verde = Color(0xFF20A35C);
  static const Color botaoTopo = Color(0xFFFFC043);
  static const Color botaoMeio = Color(0xFFF79A12);
  static const Color botaoBase = Color(0xFFEA8404);
  static const Color botaoSombra = Color(0xFFC06C04);
  static const Color azulDaOnda = Color(0xFF17257E);
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  Timer? _relogio;
  DateTime _agora = DateTime.now();

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(
      const Duration(seconds: 20),
      (_) => setState(() => _agora = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 600;

            return Column(
              children: [
                _Cabecalho(
                  agora: _agora,
                  conectividade: deps.connectivity,
                  compacto: compacto,
                  onConfigurar: () =>
                      Navigator.of(context).pushNamed(AppRoutes.setup),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            compacto ? 16 : 28,
                            compacto ? 12 : 26,
                            compacto ? 16 : 28,
                            // Espaço da onda e do rodapé.
                            compacto ? 130 : 260,
                          ),
                          child: Column(
                            children: [
                              // Altura fixa, e não largura: a arte tem
                              // proporção própria, e dimensionar pela largura
                              // deixa a altura a cargo dela — que é o que
                              // empurra o botão para fora da tela.
                              Image.asset(
                                LogotipoDaLoja.caminho,
                                height: compacto ? 118 : 168,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                              ),
                              SizedBox(height: compacto ? 12 : 18),
                              _PlacaDoTerminal(
                                device: deps.session.deviceId,
                                loja: deps.session.storeCode ??
                                    (deps.session.storeId == null
                                        ? null
                                        : 'L${deps.session.storeId}'),
                                compacto: compacto,
                              ),
                              SizedBox(height: compacto ? 22 : 44),
                              _BotaoIniciarVenda(
                                compacto: compacto,
                                onPressed: () => Navigator.of(context)
                                    .pushNamed(AppRoutes.terminalLogin),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: compacto ? 120 : 240,
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _OndaDoInicio(compacto: compacto),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _Rodape(agora: _agora, compacto: compacto),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Cabeçalho claro: o terminal à esquerda, rede, relógio e ajustes à direita.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.agora,
    required this.conectividade,
    required this.compacto,
    required this.onConfigurar,
  });

  final DateTime agora;
  final ConnectivityChannel conectividade;
  final bool compacto;
  final VoidCallback onConfigurar;

  @override
  Widget build(BuildContext context) {
    final hora = '${agora.hour.toString().padLeft(2, '0')}:'
        '${agora.minute.toString().padLeft(2, '0')}';

    return Container(
      height: compacto ? 62 : 74,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 14 : 28),
      child: Row(
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Só o rótulo: o identificador do aparelho está na plaquinha
                // logo abaixo, e repeti-lo aqui seria dizer a mesma coisa duas
                // vezes na mesma tela.
                Text(
                  'TERMINAL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compacto ? 17 : 28,
                    fontWeight: FontWeight.w800,
                    color: _Tons.tituloTerminal,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: compacto ? 42 : 62,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Marca.laranja,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // O estado real da rede, não um selo fixo: é o mesmo sinal que a
          // barra das outras telas usa.
          ListenableBuilder(
            listenable: conectividade,
            builder: (context, _) {
              final online = conectividade.isOnline;
              return _Pilula(
                compacto: compacto,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online ? _Tons.verde : Marca.vermelhoTexto,
                        boxShadow: [
                          BoxShadow(
                            color: (online ? _Tons.verde : Marca.vermelhoTexto)
                                .withValues(alpha: .6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      online ? 'ONLINE' : 'SEM REDE',
                      style: TextStyle(
                        fontSize: compacto ? 12 : 15,
                        fontWeight: FontWeight.w700,
                        color: _Tons.tituloTerminal,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (!compacto) ...[
            const SizedBox(width: 16),
            Text(
              hora,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _Tons.relogio,
              ),
            ),
          ],
          SizedBox(width: compacto ? 6 : 16),
          InkWell(
            onTap: onConfigurar,
            customBorder: const CircleBorder(),
            child: Container(
              width: compacto ? 42 : 52,
              height: compacto ? 42 : 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _Tons.fundoPilula,
                border: Border.fromBorderSide(
                  BorderSide(color: _Tons.bordaPilula),
                ),
              ),
              child: Icon(
                Icons.settings_outlined,
                size: compacto ? 22 : 28,
                color: Marca.tintaFraca,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pilula extends StatelessWidget {
  const _Pilula({required this.child, required this.compacto});

  final Widget child;
  final bool compacto;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 10 : 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: _Tons.fundoPilula,
          border: Border.all(color: _Tons.bordaPilula),
          borderRadius: BorderRadius.circular(999),
        ),
        child: child,
      );
}

/// Plaquinha com o identificador do aparelho e a loja.
class _PlacaDoTerminal extends StatelessWidget {
  const _PlacaDoTerminal({
    required this.device,
    required this.loja,
    required this.compacto,
  });

  final String? device;
  final String? loja;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 14 : 22,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _Tons.fundoPilula,
        border: Border.all(color: _Tons.bordaPilula),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TERMINAL',
            style: TextStyle(
              fontSize: compacto ? 10 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
              color: _Tons.rotulo,
            ),
          ),
          Container(
            width: 1,
            height: 26,
            margin: EdgeInsets.symmetric(horizontal: compacto ? 10 : 14),
            color: _Tons.bordaPilula,
          ),
          Flexible(
            child: Text(
              device ?? 'não identificado',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compacto ? 16 : 22,
                fontWeight: FontWeight.w800,
                color: Marca.tinta,
              ),
            ),
          ),
          if (loja != null) ...[
            SizedBox(width: compacto ? 8 : 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _Tons.etiqueta,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                loja!,
                style: TextStyle(
                  fontSize: compacto ? 11 : 13,
                  fontWeight: FontWeight.w700,
                  color: Marca.tintaFraca,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A ação única da tela, em cápsula laranja com sombra dura.
class _BotaoIniciarVenda extends StatelessWidget {
  const _BotaoIniciarVenda({required this.compacto, required this.onPressed});

  final bool compacto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final altura = compacto ? 96.0 : 150.0;
    final raio = altura / 2;

    return Container(
      constraints: const BoxConstraints(maxWidth: 900),
      height: altura,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(raio),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Tons.botaoTopo, _Tons.botaoMeio, _Tons.botaoBase],
          stops: [0, .46, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: _Tons.botaoSombra,
            offset: Offset(0, compacto ? 8 : 14),
          ),
          BoxShadow(
            color: const Color(0xFFBE6E0A).withValues(alpha: .35),
            offset: Offset(0, compacto ? 16 : 26),
            blurRadius: compacto ? 26 : 44,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(raio),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 34),
            child: Row(
              children: [
                Container(
                  width: compacto ? 62 : 104,
                  height: compacto ? 62 : 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .9),
                      width: 4,
                    ),
                  ),
                  child: Icon(
                    Icons.shopping_cart_outlined,
                    size: compacto ? 32 : 56,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: compacto ? 12 : 26),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'INICIAR VENDA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compacto ? 28 : 62,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            color: Color(0x59965000),
                            offset: Offset(0, 2),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compacto ? 8 : 20),
                Icon(
                  Icons.chevron_right,
                  size: compacto ? 34 : 58,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Onda de três faixas no pé, terminando no azul escuro do rodapé.
class _OndaDoInicio extends CustomPainter {
  const _OndaDoInicio({required this.compacto});

  final bool compacto;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void faixa(double inicio, double fim, Color cor) {
      final caminho = Path()
        ..moveTo(0, h * inicio)
        ..cubicTo(w * .33, h * (inicio - .32), w * .70, h * (inicio + .27), w,
            h * fim)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(caminho, Paint()..color = cor);
    }

    // Frações da referência: 150, 178 e 202 sobre 240. No retrato a faixa azul
    // sobe, porque é o fundo do rodapé e texto claro sobre branco não se lê.
    if (compacto) {
      faixa(.46, .26, Marca.laranja);
      faixa(.60, .38, Colors.white);
      faixa(.72, .48, _Tons.azulDaOnda);
    } else {
      faixa(.62, .35, Marca.laranja);
      faixa(.74, .47, Colors.white);
      faixa(.84, .55, _Tons.azulDaOnda);
    }
  }

  @override
  bool shouldRepaint(_OndaDoInicio oldDelegate) =>
      compacto != oldDelegate.compacto;
}

/// Rodapé sobre a faixa azul: o aparelho e a data.
class _Rodape extends StatelessWidget {
  const _Rodape({required this.agora, required this.compacto});

  final DateTime agora;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      color: Colors.white.withValues(alpha: .82),
      fontSize: compacto ? 10 : 13,
      fontWeight: FontWeight.w600,
      letterSpacing: .9,
    );
    final data = '${agora.day.toString().padLeft(2, '0')}/'
        '${agora.month.toString().padLeft(2, '0')}/${agora.year}';

    return Container(
      height: compacto ? 36 : 52,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 14 : 28),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              'ELGIN M10 PRO · PDV',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: estilo,
            ),
          ),
          const SizedBox(width: 8),
          Text(data, style: estilo),
        ],
      ),
    );
  }
}
