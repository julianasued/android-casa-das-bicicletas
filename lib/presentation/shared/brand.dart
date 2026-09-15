/// Identidade visual das telas do terminal.
///
/// Vive aqui, e não dentro de uma tela, porque as referências de
/// `fluxo-frontend/handoff/` repetem os mesmos elementos em todas elas: a
/// mesma barra cinza no topo, a mesma paleta, o mesmo fundo pontilhado.
/// Duplicar isso por tela seria garantir que uma hora divergem.
library;

import 'package:flutter/material.dart';

/// Cores da identidade, como na referência.
class Marca {
  const Marca._();

  static const Color azul = Color(0xFF0020AD);
  static const Color azulEscuro = Color(0xFF061661);
  static const Color azulTeclado = Color(0xFF0A1F86);
  static const Color azulTecla = Color(0xFF1B2C7D);
  static const Color azulTeclaAlt = Color(0xFF2A3D9E);
  static const Color amarelo = Color(0xFFFDD425);
  static const Color laranja = Color(0xFFF5921E);
  static const Color laranjaSombra = Color(0xFFA8620D);
  static const Color laranjaEscuro = Color(0xFFC9781A);
  static const Color tinta = Color(0xFF0E1B52);
  static const Color tintaFraca = Color(0xFF5B6480);
  static const Color bordaCampo = Color(0xFFC9D2EE);
  static const Color vermelho = Color(0xFFE23B3B);
  static const Color vermelhoTexto = Color(0xFFD32020);
  static const Color azulClaro = Color(0xFFE8ECFB);
}

/// Barra cinza do topo: qual aparelho é este, que horas são.
class BarraDoTerminal extends StatelessWidget {
  const BarraDoTerminal({
    required this.terminal,
    required this.agora,
    required this.compacto,
    this.acao,
    super.key,
  });

  final String? terminal;
  final DateTime agora;
  final bool compacto;

  /// Botão do canto direito, quando a tela tem um. A referência não desenha
  /// nenhum, mas tirar a saída do terminal seria perder função, não estilo.
  final Widget? acao;

  String get _hora => '${agora.hour.toString().padLeft(2, '0')}:'
      '${agora.minute.toString().padLeft(2, '0')}';

  String get _data => '${agora.day.toString().padLeft(2, '0')}/'
      '${agora.month.toString().padLeft(2, '0')}/${agora.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compacto ? 48 : 56,
      padding: EdgeInsets.only(left: compacto ? 12 : 24, right: 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8F8F8F), Color(0xFF636363), Color(0xFF4C4C4C)],
          stops: [0, .55, 1],
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.only(bottom: 2),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Marca.laranja, width: 4),
                ),
              ),
              child: Text(
                // O aparelho de verdade, não um número fixo: com dois
                // terminais no balcão é isto que diz em qual se está.
                terminal ?? 'TERMINAL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compacto ? 15 : 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Encolhe junto: com a fonte do sistema ampliada, relógio e data
          // empurram a barra para fora da largura do M10.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compacto ? 10 : 18,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .22)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hora,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 13 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: Colors.white.withValues(alpha: .4),
                    ),
                    Text(
                      _data,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 13 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (acao != null) acao!,
        ],
      ),
    );
  }
}

/// Fundo pontilhado do bloco branco.
class PadraoDeBolinhas extends CustomPainter {
  const PadraoDeBolinhas();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    final ponto = Paint()..color = Marca.azul.withValues(alpha: .09);
    const passo = 16.0;
    // Só nas laterais, como na referência: o miolo fica limpo para o texto.
    final faixa = size.width * .18;

    for (var y = 0.0; y < size.height; y += passo) {
      for (var x = 0.0; x < size.width; x += passo) {
        if (x > faixa && x < size.width - faixa) continue;
        canvas.drawCircle(Offset(x, y), 1.4, ponto);
      }
    }
  }

  @override
  bool shouldRepaint(PadraoDeBolinhas oldDelegate) => false;
}

/// Logo: bicicleta no círculo azul de borda amarela, com o nome da loja.
class LogotipoDaLoja extends StatelessWidget {
  const LogotipoDaLoja({required this.compacto, super.key});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final diametro = compacto ? 34.0 : 74.0;

    return Column(
      children: [
        Container(
          width: diametro,
          height: diametro,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Marca.azul,
            border: Border.all(color: Marca.amarelo, width: 4),
          ),
          child: Icon(
            Icons.pedal_bike,
            size: diametro * .56,
            color: Marca.amarelo,
          ),
        ),
        SizedBox(height: compacto ? 4 : 8),
        Text(
          'CASA DAS',
          style: TextStyle(
            fontSize: compacto ? 13 : 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Marca.amarelo,
            shadows: const [
              Shadow(color: Marca.azul, offset: Offset(-.8, 0)),
              Shadow(color: Marca.azul, offset: Offset(.8, 0)),
              Shadow(color: Marca.azul, offset: Offset(0, .8)),
              Shadow(color: Marca.azul, offset: Offset(0, -.8)),
            ],
          ),
        ),
        Text(
          'BICICLETAS',
          style: TextStyle(
            fontSize: compacto ? 16 : 24,
            fontWeight: FontWeight.w800,
            color: Marca.azul,
          ),
        ),
        if (!compacto)
          const Text(
            'PEÇAS PARA MOTOS E BICICLETAS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: Marca.azul,
            ),
          ),
      ],
    );
  }
}
