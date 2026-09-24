/// Seleção do vendedor no terminal (API §2.3).
///
/// Sem senha, por decisão de negócio (§12 da integração com o M10): a seleção
/// diz quem responde pela venda (RF06), e não concede permissão administrativa
/// nenhuma. O que a tela precisa garantir é que a escolha seja consciente — daí
/// os nomes grandes e a lista sem outro elemento competindo por atenção.
/// A aparência segue `fluxo-frontend/handoff/tela-vendedor.html`: a mesma barra
/// cinza da tela de senha, o fundo pontilhado, a marca, e os vendedores em
/// cartões laranja com sombra dura. A referência é desenhada para 1280x800 em
/// paisagem; aqui a grade muda de colunas conforme a largura, porque o alvo é
/// o M10 e o que não pode é cortar nome de vendedor.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/seller.dart';
import '../terminal/seller_login_page.dart';
import '../shared/brand.dart';
import '../shared/feedback.dart';

class SellerSelectionPage extends StatefulWidget {
  const SellerSelectionPage({this.sellers, super.key});

  /// Vendedores já carregados na abertura do terminal, quando vieram de lá.
  final List<Seller>? sellers;

  @override
  State<SellerSelectionPage> createState() => _SellerSelectionPageState();
}

class _SellerSelectionPageState extends State<SellerSelectionPage> {
  List<Seller>? _sellers;
  Failure? _failure;
  bool _loading = false;
  int? _selecting;

  /// Nome de quem está sendo aberto — a referência anuncia isso na espera.
  String? _abrindo;

  Timer? _relogio;
  DateTime _agora = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sellers = widget.sellers;
    if (_sellers == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final result = await context.deps.auth.listTerminalSellers();
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _sellers = value;
        case Err(:final failure):
          _failure = failure;
      }
    });
  }

  /// Escolher o nome é dizer quem se diz ser; o PIN vem na tela seguinte.
  ///
  /// A sessão não abre aqui. Antes abria: tocar no nome bastava, e era esse
  /// nome que ia em toda venda. Agora a lista só encaminha, e quem abre a
  /// sessão é a tela de senha, com a credencial da própria pessoa (§2.3).
  ///
  /// A rota é empurrada **direta**, e não por nome. Rota nomeada com argumento
  /// tipado depende de um `is` acertar em tempo de execução; quando ele erra,
  /// o gerador devolve `null` e o Flutter derruba a tela com "could not find a
  /// generator for route" — bem na frente do cliente. Aqui o construtor exige
  /// o `Seller`, e o compilador garante o que o `is` só torcia para dar certo.
  Future<void> _select(Seller seller) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SellerLoginPage(vendedor: seller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 600;

          return Stack(
            children: [
              Column(
                children: [
                  BarraDoTerminal(
                    terminal: context.deps.session.deviceId,
                    agora: _agora,
                    compacto: compacto,
                    acao: IconButton(
                      tooltip: 'Fechar terminal',
                      onPressed: _closeTerminal,
                      icon: const Icon(Icons.logout,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  Expanded(child: _corpo(compacto, constraints.maxWidth)),
                ],
              ),
              if (_abrindo != null) _EsperaDaSessao(nome: _abrindo!),
            ],
          );
        },
      ),
    );
  }

  Widget _corpo(bool compacto, double largura) {
    if (_loading) return const LoadingView(label: 'Carregando vendedores...');
    if (_failure != null) {
      return FailureView(failure: _failure!, onRetry: _load);
    }

    final sellers = _sellers ?? const <Seller>[];
    if (sellers.isEmpty) {
      return const EmptyView(
        icon: Icons.person_off,
        message: 'Nenhum vendedor habilitado neste terminal.\n'
            'O cadastro é feito pelo dono ou gerente.',
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: const PadraoDeBolinhas())),
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compacto ? 16 : 50,
              compacto ? 10 : 14,
              compacto ? 16 : 50,
              // Espaço para a onda e o rodapé: cartão atrás da faixa azul é
              // cartão que o vendedor não vê.
              compacto ? 130 : 215,
            ),
            children: [
              LogotipoDaLoja(compacto: compacto),
              SizedBox(height: compacto ? 12 : 16),
              _Chamada(compacto: compacto),
              SizedBox(height: compacto ? 14 : 22),
              _GradeDeVendedores(
                sellers: sellers,
                compacto: compacto,
                largura: largura,
                selecionando: _selecting,
                onSelect: _select,
              ),
            ],
          ),
        ),
        // Onda e rodapé por cima da lista: com rolagem, um cartão passaria
        // sobre a faixa azul e o texto branco do rodapé sumiria nele.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: compacto ? 116 : 190,
          child: IgnorePointer(
            child: CustomPaint(painter: _OndaTripla(compacto: compacto)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Rodape(quantidade: sellers.length, compacto: compacto),
        ),
      ],
    );
  }

  Future<void> _closeTerminal() async {
    final navigator = Navigator.of(context);
    await context.deps.auth.logout();
    if (!mounted) return;
    await navigator.pushNamedAndRemoveUntil(AppRoutes.welcome, (_) => false);
  }
}

/// Ícone de pessoa, título e subtítulo — o cabeçalho da referência.
class _Chamada extends StatelessWidget {
  const _Chamada({required this.compacto});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final medalhao = Container(
      width: compacto ? 44 : 64,
      height: compacto ? 44 : 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD8A8), Color(0xFFF7B169)],
        ),
        border: Border.all(color: Marca.laranja, width: 3),
      ),
      child: Icon(Icons.person, size: compacto ? 26 : 34, color: Colors.white),
    );

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SELECIONE O VENDEDOR',
          style: TextStyle(
            fontSize: compacto ? 19 : 40,
            fontWeight: FontWeight.w800,
            height: 1.05,
            color: Marca.tinta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Toque no nome do vendedor para continuar',
          style: TextStyle(
            fontSize: compacto ? 12 : 19,
            fontWeight: FontWeight.w500,
            color: Marca.tintaFraca,
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        medalhao,
        SizedBox(width: compacto ? 12 : 18),
        Flexible(child: textos),
      ],
    );
  }
}

/// Os vendedores em grade: três colunas na tela larga, uma no M10.
class _GradeDeVendedores extends StatelessWidget {
  const _GradeDeVendedores({
    required this.sellers,
    required this.compacto,
    required this.largura,
    required this.selecionando,
    required this.onSelect,
  });

  final List<Seller> sellers;
  final bool compacto;
  final double largura;
  final int? selecionando;
  final ValueChanged<Seller> onSelect;

  int get _colunas {
    if (largura >= 1000) return 3;
    if (largura >= 640) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final colunas = _colunas;
    final espacoH = compacto ? 12.0 : 26.0;
    final espacoV = compacto ? 12.0 : 20.0;

    return Wrap(
      spacing: espacoH,
      runSpacing: espacoV,
      alignment: WrapAlignment.center,
      children: [
        for (final seller in sellers)
          SizedBox(
            width: colunas == 1
                ? double.infinity
                : (largura - (compacto ? 32 : 100) - espacoH * (colunas - 1)) /
                    colunas,
            child: _CartaoDeVendedor(
              nome: seller.name,
              compacto: compacto,
              abrindo: selecionando == seller.id,
              // Um toque de cada vez: dois vendedores em sequência trocariam a
              // sessão no meio da chamada anterior.
              onTap: selecionando == null ? () => onSelect(seller) : null,
            ),
          ),
      ],
    );
  }
}

/// O cartão laranja da referência: pessoa, divisória e o nome em destaque.
class _CartaoDeVendedor extends StatelessWidget {
  const _CartaoDeVendedor({
    required this.nome,
    required this.compacto,
    required this.abrindo,
    required this.onTap,
  });

  final String nome;
  final bool compacto;
  final bool abrindo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final altura = compacto ? 88.0 : 112.0;

    return Container(
      height: altura,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compacto ? 20 : 26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD18A), Color(0xFFF8AE55), Color(0xFFF0972F)],
          stops: [0, .52, 1],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          // Sombra dura embaixo: é ela que dá o volume de tecla da referência.
          BoxShadow(color: Color(0xFFD4770C), offset: Offset(0, 8)),
          BoxShadow(
            color: Color(0x47BE6E0A),
            offset: Offset(0, 14),
            blurRadius: 22,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compacto ? 20 : 26),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compacto ? 14 : 20),
            child: Row(
              children: [
                Container(
                  width: compacto ? 42 : 52,
                  height: compacto ? 42 : 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .45),
                  ),
                  child: Icon(
                    Icons.person,
                    size: compacto ? 26 : 32,
                    color: const Color(0xFFE07D00),
                  ),
                ),
                SizedBox(width: compacto ? 12 : 16),
                Container(
                  width: 2,
                  height: compacto ? 34 : 44,
                  color: Colors.white.withValues(alpha: .55),
                ),
                SizedBox(width: compacto ? 12 : 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        nome.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compacto ? 18 : 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                          height: 1.05,
                          color: const Color(0xFF3D2600),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        abrindo ? 'ABRINDO...' : 'DISPONÍVEL',
                        style: TextStyle(
                          fontSize: compacto ? 10 : 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: const Color(0xFF6B4A12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (abrindo)
                  SizedBox.square(
                    dimension: compacto ? 18 : 24,
                    child: const CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF7A2E00),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Onda de três faixas no pé da tela: laranja, branca e azul.
class _OndaTripla extends CustomPainter {
  const _OndaTripla({required this.compacto});

  final bool compacto;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void faixa(double inicio, double fim, Color cor) {
      final caminho = Path()
        ..moveTo(0, h * inicio)
        ..cubicTo(w * .30, h * (inicio - .37), w * .70, h * (inicio + .38), w,
            h * fim)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(caminho, Paint()..color = cor);
    }

    // As frações largas são as da referência (96, 126 e 158 sobre 190). No
    // retrato a faixa azul precisa começar mais alto: ela é o fundo do rodapé,
    // e texto branco sobre o branco da onda não se lê.
    if (compacto) {
      faixa(.34, .18, Marca.laranja);
      faixa(.54, .38, Colors.white);
      faixa(.70, .52, Marca.azul);
    } else {
      faixa(.50, .31, Marca.laranja);
      faixa(.66, .46, Colors.white);
      faixa(.83, .59, Marca.azul);
    }
  }

  @override
  bool shouldRepaint(_OndaTripla oldDelegate) =>
      compacto != oldDelegate.compacto;
}

/// Rodapé sobre a faixa azul: quantos vendedores e qual aparelho.
class _Rodape extends StatelessWidget {
  const _Rodape({required this.quantidade, required this.compacto});

  final int quantidade;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      color: Colors.white,
      fontSize: compacto ? 10 : 13,
      fontWeight: FontWeight.w600,
      letterSpacing: .8,
    );

    return Container(
      height: compacto ? 34 : 48,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 14 : 26),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              quantidade == 1
                  ? '1 VENDEDOR DISPONÍVEL NESTE TERMINAL'
                  : '$quantidade VENDEDORES DISPONÍVEIS NESTE TERMINAL',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: estilo,
            ),
          ),
          const SizedBox(width: 8),
          Text('ELGIN M10 PRO', style: estilo),
        ],
      ),
    );
  }
}

/// Espera enquanto a sessão do vendedor é aberta no servidor.
class _EsperaDaSessao extends StatelessWidget {
  const _EsperaDaSessao({required this.nome});

  final String nome;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Marca.azul.withValues(alpha: .94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 6,
                  color: Marca.amarelo,
                  backgroundColor: Colors.white.withValues(alpha: .28),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Abrindo sessão de $nome...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
