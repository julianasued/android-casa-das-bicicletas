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

/// Voltar à etapa anterior, no padrão das telas do terminal.
///
/// Mora aqui porque mais de uma tela precisa dele e porque o fluxo (§19) pede
/// que a volta seja **visível**: o aplicativo roda em modo quiosque, com a
/// barra do Android escondida, e o gesto do sistema é justamente o
/// comportamento oculto que não pode ser a única saída.
class BotaoVoltar extends StatelessWidget {
  const BotaoVoltar({
    required this.onPressed,
    required this.compacto,
    this.sobreClaro = false,
    super.key,
  });

  final VoidCallback onPressed;
  final bool compacto;

  /// Sobre fundo claro o branco translúcido some; aí o botão veste a borda e a
  /// tinta da marca, com a seta no laranja que essa tela já usa.
  final bool sobreClaro;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          Icons.chevron_left,
          color: sobreClaro ? Marca.laranja : Marca.amarelo,
          size: 22,
        ),
        style: OutlinedButton.styleFrom(
          // O tema manda `Size.fromHeight(56)`, que é largura **infinita**:
          // basta este botão cair num lugar sem largura definida — um
          // `Positioned` sem `right`, por exemplo — para a tela não montar.
          // Aqui a largura sai do rótulo, como um botão de barra deve fazer.
          minimumSize: const Size(0, 44),
          backgroundColor:
              sobreClaro ? Colors.white : Colors.white.withValues(alpha: .14),
          foregroundColor: sobreClaro ? Marca.azul : Colors.white,
          padding: EdgeInsets.symmetric(horizontal: compacto ? 10 : 16),
          side: BorderSide(
            color: sobreClaro
                ? Marca.bordaCampo
                : Colors.white.withValues(alpha: .3),
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        label: const Text(
          'VOLTAR',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
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

  /// A arte da loja, com símbolo, nome e assinatura numa peça só.
  ///
  /// Antes isto era desenhado com widgets — círculo, dois textos e a
  /// assinatura —, o que era aproximação enquanto não havia a marca. Com a arte
  /// real, recriá-la em código só introduziria diferença de tipografia.
  static const String caminho = 'assets/logo/logo-casa-das-bicicletas.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      caminho,
      // Altura manda, largura acompanha: é o que mantém a proporção da arte
      // sem depender de eu acertar a largura à mão.
      height: compacto ? 64 : 130,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
