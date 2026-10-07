/// Abertura do turno com o PIN do vendedor (API §2.3).
///
/// A senha é **da pessoa**, não do aparelho. Antes esta tela pedia a senha do
/// terminal: uma credencial que todo mundo do balcão sabia, digitada uma vez e
/// repassada de boca em boca. O que a venda carimbava era o nome em que alguém
/// encostou o dedo na lista — e, com a comissão saindo do vendedor da venda
/// (RF19), nome errado é dinheiro no bolso errado.
///
/// O teclado é numérico e é desenhado na tela: o PIN é numérico justamente
/// porque no M10 o teclado do Android cobre metade da área útil e some com o
/// campo que está sendo preenchido.
/// A aparência segue `fluxo-frontend/handoff/tela-senha.html`: o azul #0020ad,
/// o amarelo da marca, o laranja da ação, a barra cinza com o terminal e o
/// relógio, a onda separando o bloco branco do teclado e as teclas com sombra
/// dura embaixo. A referência é desenhada para 1280x800 em paisagem; aqui as
/// proporções se ajustam, porque o alvo é o M10 e o que não pode é estourar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/seller.dart';
import '../shared/brand.dart';

class SellerLoginPage extends StatefulWidget {
  const SellerLoginPage({required this.vendedor, super.key});

  /// Quem foi escolhido na tela anterior. O nome fica à vista o tempo todo:
  /// digitar o PIN achando que é outra pessoa é o erro que esta tela existe
  /// para evitar.
  final Seller vendedor;

  @override
  State<SellerLoginPage> createState() => _SellerLoginPageState();
}

class _SellerLoginPageState extends State<SellerLoginPage> {
  final _passwordController = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;
  bool _obscured = true;
  Failure? _failure;

  /// Relógio do cabeçalho, como na referência.
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
    _passwordController.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Qualquer edição limpa o erro anterior: manter na tela a recusa da senha
  /// passada enquanto o operador digita a nova faz ele achar que errou de novo.
  void _digit(String value) {
    setState(() {
      _passwordController.text += value;
      _failure = null;
    });
  }

  void _backspace() {
    final text = _passwordController.text;
    if (text.isEmpty) return;
    setState(() {
      _passwordController.text = text.substring(0, text.length - 1);
      _failure = null;
    });
  }

  void _clear() {
    setState(() {
      _passwordController.clear();
      _failure = null;
    });
  }

  Future<void> _open() async {
    if (_submitting || _passwordController.text.isEmpty) return;

    final deps = context.deps;
    final navigator = Navigator.of(context);

    setState(() {
      _submitting = true;
      _failure = null;
    });

    final result = await deps.selectSeller(
      seller: widget.vendedor,
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case Ok():
        _passwordController.clear();
        // A loja é buscada agora porque o código dela (`L1`) entra no código
        // de barras da venda e no cabeçalho do documento. Falhar aqui não
        // impede de vender: o servidor devolve o documento pronto de qualquer
        // jeito.
        await deps.auth.currentStore();
        if (!mounted) return;
        // Direto para a venda (§5 e §19): quem digitou o PIN fez isso para
        // vender, não para escolher no menu o que fazer em seguida.
        await navigator.pushNamedAndRemoveUntil(AppRoutes.newSale, (_) => false);
      case Err(:final failure):
        // O PIN errado some do campo: repetir a tentativa com o que já falhou
        // é o erro mais comum, e reexibi-lo não ajuda ninguém.
        _passwordController.clear();
        setState(() => _failure = _traduzir(failure));
    }
  }

  /// `UnauthenticatedFailure` nesta tela não é sessão vencida.
  ///
  /// `ApiClient` traduz todo 401 para "Sessão expirada. Autentique o terminal
  /// novamente.", o que está certo nas rotas que exigem token — mas aqui não
  /// há token nenhum ainda: 401 em `/auth/terminal/` é senha recusada. Dizer
  /// "sessão expirada" a quem acabou de digitar manda a pessoa procurar
  /// problema onde não há.
  ///
  /// A tradução é local de propósito: a mensagem do backend é descartada no
  /// mapeamento do 401, e mexer nisso é a pendência registrada no §24 do fluxo.
  Failure _traduzir(Failure failure) => switch (failure) {
        UnauthenticatedFailure() =>
          const UnauthenticatedFailure('Senha incorreta. Tente de novo.'),
        _ => failure,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Marca.azul,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Dois perfis em vez de medidas fixas: a referência é de uma tela de
          // 1280 de largura, e repetir aqueles pixels no M10 cortaria metade
          // do cabeçalho.
          final compacto = constraints.maxWidth < 600;

          return Column(
            children: [
              BarraDoTerminal(
                terminal: context.deps.session.deviceId,
                agora: _agora,
                compacto: compacto,
                acao: IconButton(
                  tooltip: 'Configuração',
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.setup),
                  icon:
                      const Icon(Icons.settings, color: Colors.white, size: 20),
                ),
              ),
              Expanded(
                flex: compacto ? 7 : 7,
                child: _BlocoBranco(
                  compacto: compacto,
                  vendedor: widget.vendedor.name,
                  // Volta para a lista de nomes. Só quando há para onde: um
                  // botão que não leva a lugar nenhum é pior que botão nenhum.
                  onVoltar: Navigator.of(context).canPop()
                      ? () => Navigator.of(context).pop()
                      : null,
                  controller: _passwordController,
                  focusNode: _focus,
                  obscured: _obscured,
                  enabled: !_submitting,
                  erro: _failure?.message,
                  onToggleObscured: () =>
                      setState(() => _obscured = !_obscured),
                  onSubmitted: (_) => _open(),
                ),
              ),
              Expanded(
                flex: compacto ? 6 : 5,
                child: _Teclado(
                  compacto: compacto,
                  submetendo: _submitting,
                  senha: _passwordController,
                  onDigit: _digit,
                  onBackspace: _backspace,
                  onClear: _clear,
                  onConfirm: _open,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bloco branco: marca, chamada, campo da senha e a linha de ajuda.
class _BlocoBranco extends StatelessWidget {
  const _BlocoBranco({
    required this.compacto,
    required this.vendedor,
    required this.onVoltar,
    required this.controller,
    required this.focusNode,
    required this.obscured,
    required this.enabled,
    required this.erro,
    required this.onToggleObscured,
    required this.onSubmitted,
  });

  final bool compacto;

  /// Nome de quem está se identificando.
  final String vendedor;

  /// Volta para a lista de nomes; `null` quando não há pilha abaixo.
  final VoidCallback? onVoltar;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscured;
  final bool enabled;
  final String? erro;
  final VoidCallback onToggleObscured;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final alturaDaOnda = compacto ? 30.0 : 56.0;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: const PadraoDeBolinhas()),
        ),
        // A área útil termina onde a onda começa: desenhada por cima, ela
        // cortava o campo de senha pela metade.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: alturaDaOnda,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ocupa altura de verdade, em vez de flutuar sobre o bloco: o
              // miolo é centralizado e o logo sobe até aqui, então um botão
              // por cima ficaria encavalado nele no M10. Ainda por cima, a
              // área rolável cobre o bloco inteiro e engoliria o toque.
              if (onVoltar != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compacto ? 12 : 24,
                    compacto ? 10 : 16,
                    0,
                    0,
                  ),
                  child: BotaoVoltar(
                    onPressed: onVoltar!,
                    compacto: compacto,
                    sobreClaro: true,
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
              // Rolável só quando precisa: com a fonte do sistema ampliada o
              // conteúdo passa da altura, e aí rolar é melhor que cortar.
              padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LogotipoDaLoja(compacto: compacto),
                    SizedBox(height: compacto ? 8 : 16),
                    _Chamada(compacto: compacto, vendedor: vendedor),
                    SizedBox(height: compacto ? 8 : 12),
                    _CampoDeSenha(
                      compacto: compacto,
                      controller: controller,
                      focusNode: focusNode,
                      obscured: obscured,
                      enabled: enabled,
                      temErro: erro != null,
                      onToggleObscured: onToggleObscured,
                      onSubmitted: onSubmitted,
                    ),
                    SizedBox(height: compacto ? 8 : 12),
                    _LinhaDeAjuda(erro: erro, compacto: compacto),
                  ],
                ),
              ),
            ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: alturaDaOnda,
          child: const IgnorePointer(
            child: CustomPaint(painter: _Onda()),
          ),
        ),
      ],
    );
  }
}

/// Onda laranja e branca que separa o bloco branco do teclado.
class _Onda extends CustomPainter {
  const _Onda();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Duas curvas, a branca por cima: o que sobra entre elas é a faixa
    // laranja. O afastamento é o que dá espessura à faixa — curvas próximas
    // demais viram um fio, que foi como saiu na primeira tentativa.
    final laranja = Path()
      ..moveTo(0, h * .30)
      ..cubicTo(w * .28, h * -.20, w * .73, h * .75, w, h * .06)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(laranja, Paint()..color = Marca.laranja);

    final branca = Path()
      ..moveTo(0, h * .66)
      ..cubicTo(w * .28, h * .16, w * .73, h * 1.11, w, h * .42)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(branca, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_Onda oldDelegate) => false;
}

/// Cadeado, título e subtítulo.
class _Chamada extends StatelessWidget {
  const _Chamada({required this.compacto, required this.vendedor});

  final bool compacto;

  /// O nome de quem foi escolhido. Sem ele a tela pediria "sua senha" sem
  /// dizer de quem.
  final String vendedor;

  @override
  Widget build(BuildContext context) {
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'INSIRA A SENHA DO VENDEDOR',
          style: TextStyle(
            fontSize: compacto ? 17 : 38,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: Marca.tinta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          vendedor.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compacto ? 15 : 26,
            fontWeight: FontWeight.w800,
            height: 1.15,
            color: Marca.azul,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Digite sua senha',
          style: TextStyle(
            fontSize: compacto ? 12 : 19,
            fontWeight: FontWeight.w500,
            color: Marca.tintaFraca,
          ),
        ),
      ],
    );

    final cadeado = Container(
      width: compacto ? 36 : 56,
      height: compacto ? 36 : 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Marca.azulClaro,
        border: Border.all(color: const Color(0xFFC3CDF3), width: 2),
      ),
      child:
          Icon(Icons.lock_outline, size: compacto ? 22 : 28, color: Marca.azul),
    );

    // Lado a lado nos dois tamanhos: empilhar o cadeado custava uma altura que
    // o retrato não tem, e o que não pode faltar na tela é o campo da senha.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [cadeado, const SizedBox(width: 18), Flexible(child: textos)],
    );
  }
}

/// Campo da senha: mascarado, com o olho para revelar.
class _CampoDeSenha extends StatelessWidget {
  const _CampoDeSenha({
    required this.compacto,
    required this.controller,
    required this.focusNode,
    required this.obscured,
    required this.enabled,
    required this.temErro,
    required this.onToggleObscured,
    required this.onSubmitted,
  });

  final bool compacto;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscured;
  final bool enabled;
  final bool temErro;
  final VoidCallback onToggleObscured;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // A borda conta o estado sem texto nenhum: cinza vazio, laranja
        // preenchido, vermelho recusado — como na referência.
        final borda = temErro
            ? Marca.vermelho
            : (controller.text.isEmpty ? Marca.bordaCampo : Marca.laranja);

        return Container(
          constraints: const BoxConstraints(maxWidth: 880),
          height: compacto ? 56 : 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borda, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A1E6E).withValues(alpha: .12),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: compacto ? 16 : 26),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    obscureText: obscured,
                    obscuringCharacter: '✱',
                      enabled: enabled,
                    showCursor: true,
                    cursorColor: Marca.tinta,
                    cursorWidth: 3,
                    style: TextStyle(
                      fontSize: compacto ? 26 : 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: compacto ? 10 : 18,
                      color: Marca.tinta,
                    ),
                    // Só leitura: quem escreve é o teclado da tela. Sem isto
                    // um toque no campo abriria o teclado do Android, que no
                    // M10 cobre metade da área útil — e some justamente com o
                    // campo que está sendo preenchido.
                    readOnly: true,
                    keyboardType: TextInputType.number,
                    onSubmitted: onSubmitted,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Seu PIN',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Marca.bordaCampo,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: obscured ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: enabled ? onToggleObscured : null,
                icon: Icon(
                  obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Marca.azul,
                  size: compacto ? 26 : 34,
                ),
              ),
              SizedBox(width: compacto ? 4 : 12),
            ],
          ),
        );
      },
    );
  }
}

/// Linha abaixo do campo: dica em cinza, erro em vermelho.
class _LinhaDeAjuda extends StatelessWidget {
  const _LinhaDeAjuda({required this.erro, required this.compacto});

  final String? erro;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final temErro = erro != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: temErro ? Marca.vermelhoTexto : Marca.azulClaro,
          ),
          child: Text(
            temErro ? '!' : 'i',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: temErro ? Colors.white : Marca.azul,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            erro ?? 'Toque no ícone do olho para mostrar a senha',
            style: TextStyle(
              fontSize: compacto ? 13 : 18,
              fontWeight: FontWeight.w600,
              color: temErro ? Marca.vermelhoTexto : Marca.tintaFraca,
            ),
          ),
        ),
      ],
    );
  }
}

/// Teclado sobre o azul escuro: dígitos com letras, apagar, limpar, confirmar.
///
/// Grade fixa de quatro colunas por quatro linhas, sem rolagem: tecla que
/// precisa ser procurada é tecla que atrasa o balcão. As alturas saem do
/// espaço disponível, e não de medidas fixas — é o que mantém o alvo grande no
/// M10 sem estourar quando a fonte do sistema está ampliada.
class _Teclado extends StatelessWidget {
  const _Teclado({
    required this.compacto,
    required this.submetendo,
    required this.senha,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onConfirm,
  });

  final bool compacto;
  final bool submetendo;
  final TextEditingController senha;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final espaco = compacto ? 8.0 : 14.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compacto ? 12 : 26,
        compacto ? 12 : 20,
        compacto ? 12 : 26,
        compacto ? 12 : 22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Marca.azulTeclado, Marca.azulEscuro],
        ),
      ),
      child: Row(
        children: [
          // Coluna dos dígitos: três por linha, e o zero sozinho na célula
          // do meio da última.
          Expanded(
            flex: 3,
            child: Column(
              // Sem isto as linhas saem do tamanho do texto em vez da
              // largura da coluna: `Column` centraliza, não estica.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var linha = 0; linha < 3; linha++) ...[
                  Expanded(
                    child: Row(
                      // Toda tecla ocupa a linha inteira. Sem isto cada uma se
                      // dimensiona pelo próprio conteúdo, e o `1` — o único
                      // dígito sem a linha de letras — sai mais baixo que os
                      // vizinhos; quanto maior a fonte do sistema, maior a
                      // diferença.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var coluna = 0; coluna < 3; coluna++) ...[
                          if (coluna > 0) SizedBox(width: espaco),
                          Expanded(
                            child: _Tecla(
                              rotulo: '${linha * 3 + coluna + 1}',
                              compacto: compacto,
                              onPressed: submetendo
                                  ? null
                                  : () => onDigit('${linha * 3 + coluna + 1}'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: espaco),
                ],
                // O zero passa pela mesma grade das outras linhas, e não
                // solto na coluna, porque solto ele esticava pelas três
                // células: virava o maior alvo do teclado sem ser a tecla mais
                // usada. Na célula do meio ele fica do tamanho dos outros
                // dígitos e alinhado com o `2`, o `5` e o `8`.
                Expanded(
                  child: Row(
                    // Mesmo motivo das linhas de cima: o `0` também não tem
                    // letras, então precisa da altura da linha para ficar do
                    // tamanho dos outros dígitos.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var coluna = 0; coluna < 3; coluna++) ...[
                        if (coluna > 0) SizedBox(width: espaco),
                        Expanded(
                          child: coluna == 1
                              ? _Tecla(
                                  rotulo: '0',
                                  compacto: compacto,
                                  onPressed:
                                      submetendo ? null : () => onDigit('0'),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: espaco),
          // Coluna da direita: apagar, limpar e o confirmar valendo por duas
          // faixas — é o peso que a ação principal tem na referência.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _TeclaAlternativa(
                    compacto: compacto,
                    onPressed: submetendo ? null : onBackspace,
                    child: Icon(
                      Icons.backspace_outlined,
                      color: Colors.white,
                      size: compacto ? 24 : 40,
                    ),
                  ),
                ),
                SizedBox(height: espaco),
                Expanded(
                  child: _TeclaAlternativa(
                    compacto: compacto,
                    onPressed: submetendo ? null : onClear,
                    child: Text(
                      'LIMPAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 14 : 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: espaco),
                Expanded(
                  flex: 2,
                  child: _Confirmar(
                    compacto: compacto,
                    submetendo: submetendo,
                    senha: senha,
                    onPressed: onConfirm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tecla de dígito: número grande e as letras embaixo, sombra dura no pé.
class _Tecla extends StatelessWidget {
  const _Tecla({
    required this.rotulo,
    required this.compacto,
    required this.onPressed,
  });

  final String rotulo;
  final bool compacto;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _BaseDeTecla(
      cor: Marca.azulTecla,
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        // Só o dígito: é um PIN, e as letras de telefone que ficavam aqui
        // sugeriam uma senha alfanumérica que este teclado não digita.
        child: Text(
          rotulo,
          style: TextStyle(
            color: Colors.white,
            fontSize: compacto ? 26 : 34,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Apagar e limpar: azul um tom acima do dos dígitos.
class _TeclaAlternativa extends StatelessWidget {
  const _TeclaAlternativa({
    required this.compacto,
    required this.onPressed,
    required this.child,
  });

  final bool compacto;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => _BaseDeTecla(
        cor: Marca.azulTeclaAlt,
        onPressed: onPressed,
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      );
}

/// A ação: laranja, com o estado de validando.
class _Confirmar extends StatelessWidget {
  const _Confirmar({
    required this.compacto,
    required this.submetendo,
    required this.senha,
    required this.onPressed,
  });

  final bool compacto;
  final bool submetendo;
  final TextEditingController senha;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: senha,
      builder: (context, _) {
        final habilitado = !submetendo && senha.text.isNotEmpty;

        return FilledButton(
          onPressed: habilitado ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: submetendo ? Marca.laranjaEscuro : Marca.laranja,
            disabledBackgroundColor: Marca.azulTeclaAlt,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: .55),
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ).copyWith(
            shadowColor: WidgetStateProperty.all(Marca.laranjaSombra),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: submetendo
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: compacto ? 18 : 26,
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'VALIDANDO',
                        style: TextStyle(
                          fontSize: compacto ? 15 : 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'CONFIRMAR',
                    style: TextStyle(
                      fontSize: compacto ? 15 : 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// A moldura comum: canto arredondado, borda clara e a sombra dura no pé.
class _BaseDeTecla extends StatelessWidget {
  const _BaseDeTecla({
    required this.cor,
    required this.onPressed,
    required this.child,
  });

  final Color cor;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: cor,
        disabledBackgroundColor: cor.withValues(alpha: .5),
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        side: BorderSide(color: Colors.white.withValues(alpha: .14)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: child,
    );
  }
}
