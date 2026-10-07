/// Configuração do terminal — feita uma vez, na instalação do aparelho.
///
/// Três informações que o backend precisa reconhecer: para onde falar, qual é a
/// loja e qual é este dispositivo. O `X-Device-Id` (§1.2) tem de ser exatamente
/// o `device_identifier` cadastrado no terminal (§3.1); o `ANDROID_ID` aparece
/// como sugestão porque é estável no aparelho, mas quem manda é o cadastro.
///
/// A aparência segue `fluxo-frontend/handoff/tela-configuracao-terminal.html`.
/// Duas decisões daquela referência que não são estéticas:
///
/// - **O identificador fica à vista**, nunca mascarado: é o valor que o suporte
///   pede ao telefone quando o terminal não abre.
/// - **Os campos são nativos**, com o teclado do Android. A tela já teve um
///   teclado próprio, desenhado para não cobrir o campo em edição; o do sistema
///   traz o que ele não tinha — acento, colar um endereço copiado, correção por
///   toque no meio do texto — e é o teclado que o operador já conhece. O que
///   resolvia o teclado próprio resolve-se no `Scaffold`, que recolhe a tela
///   acima do teclado e rola o campo em foco até ele aparecer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../platform/device/device_channel.dart';
import '../shared/brand.dart';

/// Paleta da tela, como na referência.
class _Cor {
  const _Cor._();

  static const Color fundo = Color(0xFFEEF1F8);
  static const Color cartao = Colors.white;
  static const Color borda = Color(0xFFDFE4F1);
  static const Color sombra = Color(0xFFECEFF7);
  static const Color sombraForte = Color(0xFFC9CEE0);
  static const Color tinta = Color(0xFF0E1B52);
  static const Color rotulo = Color(0xFF5B6480);
  static const Color avisoTexto = Color(0xFFC9D0EE);

  static const Color erroBorda = Color(0xFFE39A9A);
  static const Color erroFundo = Color(0xFFFDECEC);
  static const Color erroTexto = Color(0xFFA11313);

  static const Color okFundo = Color(0xFFEAF7EE);
  static const Color okBorda = Color(0xFF9ED4B1);
  static const Color okTexto = Color(0xFF136B33);

  static const Color faltaFundo = Color(0xFFFDF0DE);
  static const Color faltaBorda = Color(0xFFE9CFA6);
  static const Color faltaTexto = Color(0xFF8A4B00);

  static const Color desligado = Color(0xFFD5DAE9);
  static const Color desligadoTexto = Color(0xFF7B8299);
  static const Color desligadoSombra = Color(0xFFC0C7DA);
}

/// Qual campo está sendo digitado.
enum _Campo {
  api('ENDEREÇO DA API'),
  loja('LOJA (ID)'),
  terminal('IDENTIFICADOR DO TERMINAL (X-DEVICE-ID)');

  const _Campo(this.rotulo);

  final String rotulo;

  /// A loja é só número; os outros dois são texto.
  bool get numerico => this == _Campo.loja;

  /// Qual teclado o Android abre para este campo.
  TextInputType get tecladoDoSistema => switch (this) {
        _Campo.api => TextInputType.url,
        // `number` e não `phone`: o id da loja é um inteiro, e o teclado de
        // telefone ofereceria `+`, `*` e `#`, que não entram aqui.
        _Campo.loja => TextInputType.number,
        _Campo.terminal => TextInputType.text,
      };

  /// O que o campo aceita.
  ///
  /// A regra é a de antes, no mecanismo do campo nativo: a loja é um id de até
  /// quatro dígitos — nenhum terminal tem id de cinco casas.
  List<TextInputFormatter> get formatos => switch (this) {
        _Campo.loja => [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
        // Endereço e identificador não levam espaço: o que aparece ali é
        // colado de uma mensagem, e espaço no fim passa despercebido.
        _ => [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      };

  /// O último campo fecha o teclado; os outros levam ao seguinte.
  TextInputAction get acaoDoTeclado =>
      this == _Campo.terminal ? TextInputAction.done : TextInputAction.next;
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  /// Um campo nativo por informação, com o controlador e o foco de cada um.
  final Map<_Campo, TextEditingController> _controles = {
    for (final campo in _Campo.values) campo: TextEditingController(),
  };
  final Map<_Campo, FocusNode> _focos = {
    for (final campo in _Campo.values) campo: FocusNode(),
  };

  DeviceInfo _aparelho = const DeviceInfo.unknown();
  _Campo? _emFoco;
  bool _carregando = true;
  bool _salvando = false;
  String? _erroDoServidor;

  String get _api => _controles[_Campo.api]!.text.trim();
  String get _loja => _controles[_Campo.loja]!.text.trim();
  String get _terminal => _controles[_Campo.terminal]!.text.trim();

  /// Sugestão do aparelho para o `X-Device-Id`.
  String get _sugestao => _aparelho.androidId;

  bool get _httpsOk =>
      !context.deps.environment.violatesTransportSecurity(_api) &&
      Uri.tryParse(_api)?.hasAuthority == true;

  bool get _apiComErro => _api.isNotEmpty && !_httpsOk;

  bool get _valido =>
      _httpsOk && (int.tryParse(_loja) ?? 0) > 0 && _terminal.isNotEmpty;

  @override
  void initState() {
    super.initState();
    for (final campo in _Campo.values) {
      // O que se digita muda o que o botão de salvar e a faixa de aviso dizem,
      // e isso é recalculado a cada tecla — não só quando o campo é deixado.
      _controles[campo]!.addListener(_aoDigitar);
      _focos[campo]!.addListener(() => _aoMudarOFoco(campo));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void dispose() {
    for (final campo in _Campo.values) {
      _controles[campo]!.dispose();
      _focos[campo]!.dispose();
    }
    super.dispose();
  }

  void _aoDigitar() {
    if (!mounted) return;
    // A recusa do servidor é da configuração que foi enviada; mexer no campo
    // já a torna velha, e mantê-la na tela faz parecer que o novo valor também
    // falhou.
    setState(() => _erroDoServidor = null);
  }

  /// Qual campo está em edição — é o que acende a borda azul do cartão.
  void _aoMudarOFoco(_Campo campo) {
    if (!mounted) return;
    final focado = _focos[campo]!.hasFocus;
    if (focado) {
      setState(() => _emFoco = campo);
    } else if (_emFoco == campo) {
      setState(() => _emFoco = null);
    }
  }

  Future<void> _carregar() async {
    final deps = context.deps;
    final aparelho = await deps.device.read();
    if (!mounted) return;

    final sessao = deps.session;
    _controles[_Campo.api]!.text =
        sessao.baseUrlOverride ?? deps.environment.apiBaseUrl;
    _controles[_Campo.loja]!.text = sessao.storeId?.toString() ?? '';
    _controles[_Campo.terminal]!.text = sessao.deviceId ?? aparelho.androidId;

    setState(() {
      _aparelho = aparelho;
      _carregando = false;
    });
  }

  void _usarSugestao() {
    if (_sugestao.isEmpty) return;
    // `text =` já avisa o controlador, e o ouvinte redesenha a tela.
    _controles[_Campo.terminal]!.text = _sugestao;
  }

  Future<void> _salvar() async {
    if (!_valido || _salvando) return;

    final deps = context.deps;
    final navigator = Navigator.of(context);

    // Fecha o teclado antes da espera: a tela de "testando a conexão" com
    // meia tela de teclado por cima não deixa ler o que está acontecendo.
    FocusScope.of(context).unfocus();

    setState(() {
      _salvando = true;
      _erroDoServidor = null;
    });

    // Testa antes de gravar: endereço errado gravado deixa o terminal sem abrir,
    // e quem descobre é o balcão no dia seguinte.
    final alcancou = await deps.apiClient.probe(_api);

    if (!mounted) return;

    if (alcancou case Err(:final Failure failure)) {
      setState(() {
        _salvando = false;
        _erroDoServidor = failure.message;
      });
      return;
    }

    await deps.session.saveConfiguration(
      deviceId: _terminal,
      storeId: int.parse(_loja),
      baseUrl: _api,
    );

    if (!mounted) return;
    setState(() => _salvando = false);

    await _anunciarEAbrir(navigator);
  }

  /// Confirma o que foi gravado antes de seguir.
  ///
  /// O identificador aparece uma última vez de propósito: é o valor que o
  /// suporte vai pedir, e esta é a tela onde ele ainda está à vista.
  Future<void> _anunciarEAbrir(NavigatorState navigator) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConfiguradoDialog(terminal: _terminal),
    );
    if (!mounted) return;
    // Volta ao repouso: daqui quem chega escolhe o nome e digita o PIN. Não
    // há mais uma senha de aparelho entre a configuração e a venda.
    await navigator.pushNamedAndRemoveUntil(
      AppRoutes.welcome,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final podeVoltar = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: _Cor.fundo,
      body: Stack(
        children: [
          Column(
            children: [
              _Cabecalho(
                versao: deps.environment.appVersion,
                primeiroAcesso: !deps.session.isConfigured,
                onVoltar: podeVoltar ? () => Navigator.of(context).pop() : null,
              ),
              Expanded(
                child: _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _Corpo(
                        aparelho: _aparelho,
                        controles: _controles,
                        focos: _focos,
                        emFoco: _emFoco,
                        apiComErro: _apiComErro,
                        valido: _valido,
                        sugestao: _sugestao,
                        aviso: _aviso(),
                        avisoOk: _valido && _erroDoServidor == null,
                        onUsarSugestao: _usarSugestao,
                        onSalvar: _valido ? _salvar : null,
                      ),
              ),
            ],
          ),
          if (_salvando)
            _EsperaDaConexao(
              host: _hostDaApi(),
              loja: _loja.isEmpty ? '—' : _loja,
            ),
        ],
      ),
    );
  }

  /// O que falta, ou o que vai acontecer quando salvar.
  String _aviso() {
    if (_erroDoServidor case final String erro) return erro;
    if (_valido) {
      return 'Configuração pronta · o terminal será vinculado à loja $_loja '
          'como $_terminal';
    }
    if (!_httpsOk) {
      return 'O endereço da API precisa começar com https:// para o terminal '
          'conectar.';
    }
    return 'Preencha loja e identificador do terminal para continuar.';
  }

  String _hostDaApi() {
    final host = Uri.tryParse(_api)?.host ?? '';
    return host.isEmpty ? '—' : host;
  }
}

// ---------------------------------------------------------------------------
// Cabeçalho
// ---------------------------------------------------------------------------

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.versao,
    required this.primeiroAcesso,
    required this.onVoltar,
  });

  final String versao;
  final bool primeiroAcesso;

  /// `null` quando esta é a primeira tela do aparelho: não há para onde voltar,
  /// e um botão que não faz nada é pior que botão nenhum.
  final VoidCallback? onVoltar;

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 900;

    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF132A9E), Marca.azul],
        ),
      ),
      child: Container(
        height: compacto ? 56 : 66,
        padding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 20),
        child: Row(
          children: [
            if (onVoltar != null) ...[
              BotaoVoltar(onPressed: onVoltar!, compacto: compacto),
              SizedBox(width: compacto ? 10 : 16),
            ],
            Flexible(
              child: Text(
                'CONFIGURAÇÃO DO TERMINAL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compacto ? 16 : 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            const Spacer(),
            if (primeiroAcesso && !compacto) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Marca.amarelo.withValues(alpha: .14),
                  border: Border.all(color: Marca.amarelo.withValues(alpha: .4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'PRIMEIRO ACESSO',
                  style: TextStyle(
                    color: Marca.amarelo,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Text(
              'app $versao',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .8),
                fontSize: compacto ? 13 : 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corpo
// ---------------------------------------------------------------------------

class _Corpo extends StatelessWidget {
  const _Corpo({
    required this.aparelho,
    required this.controles,
    required this.focos,
    required this.emFoco,
    required this.apiComErro,
    required this.valido,
    required this.sugestao,
    required this.aviso,
    required this.avisoOk,
    required this.onUsarSugestao,
    required this.onSalvar,
  });

  final DeviceInfo aparelho;
  final Map<_Campo, TextEditingController> controles;
  final Map<_Campo, FocusNode> focos;
  final _Campo? emFoco;
  final bool apiComErro;
  final bool valido;
  final String sugestao;
  final String aviso;
  final bool avisoOk;
  final VoidCallback onUsarSugestao;
  final VoidCallback? onSalvar;

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 900;

    return Center(
      child: ConstrainedBox(
        // Coluna centralizada de até 1000, como na referência: numa tela larga,
        // campo esticado de ponta a ponta é campo que ninguém lê inteiro.
        constraints: const BoxConstraints(maxWidth: 1000),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compacto ? 12 : 26,
            compacto ? 12 : 18,
            compacto ? 12 : 26,
            (compacto ? 14 : 20) + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CartaoDoAparelho(aparelho: aparelho),
              SizedBox(height: compacto ? 10 : 14),
              _CampoDeTexto(
                campo: _Campo.api,
                controlador: controles[_Campo.api]!,
                foco: focos[_Campo.api]!,
                emFoco: emFoco == _Campo.api,
                comErro: apiComErro,
                etiqueta: apiComErro ? 'USE HTTPS' : 'OBRIGATÓRIO',
                dica: 'HTTPS obrigatório (RNF01).',
                proximo: focos[_Campo.loja]!,
              ),
              const SizedBox(height: 12),
              _CampoDeTexto(
                campo: _Campo.loja,
                controlador: controles[_Campo.loja]!,
                foco: focos[_Campo.loja]!,
                emFoco: emFoco == _Campo.loja,
                comErro: false,
                etiqueta: 'OBRIGATÓRIO',
                dica: 'Id da loja cadastrada no sistema.',
                proximo: focos[_Campo.terminal]!,
              ),
              const SizedBox(height: 12),
              _CampoDeTexto(
                campo: _Campo.terminal,
                controlador: controles[_Campo.terminal]!,
                foco: focos[_Campo.terminal]!,
                emFoco: emFoco == _Campo.terminal,
                comErro: false,
                etiqueta: 'OBRIGATÓRIO',
                dica: sugestao.isEmpty
                    ? 'Deve ser igual ao cadastrado no terminal.'
                    : 'Sugestão do aparelho: $sugestao',
              ),
              SizedBox(height: compacto ? 10 : 14),
              _Acoes(
                sugestao: sugestao,
                onUsarSugestao: sugestao.isEmpty ? null : onUsarSugestao,
                onSalvar: onSalvar,
                compacto: compacto,
              ),
              SizedBox(height: compacto ? 10 : 14),
              _FaixaDeAviso(texto: aviso, ok: avisoOk),
            ],
          ),
        ),
      ),
    );
  }
}

/// O que o aplicativo leu do próprio aparelho.
class _CartaoDoAparelho extends StatelessWidget {
  const _CartaoDoAparelho({required this.aparelho});

  final DeviceInfo aparelho;

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 900;
    final nome = aparelho.displayName.isEmpty
        ? 'Aparelho não identificado'
        : aparelho.displayName;
    final versao = aparelho.androidVersion.isEmpty
        ? 'Android —'
        : 'Android ${aparelho.androidVersion}';

    final pilula = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Marca.amarelo.withValues(alpha: .14),
        border: Border.all(color: Marca.amarelo.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        versao,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Marca.amarelo,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: _Cor.tinta,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Marca.amarelo.withValues(alpha: .18),
              border: Border.all(color: Marca.amarelo, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.tablet_android_outlined,
              size: 28,
              color: Marca.amarelo,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'APARELHO DETECTADO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: _Cor.avisoTexto,
                  ),
                ),
                Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
                // Em retrato a versão do Android desce para a linha de baixo:
                // ao lado do nome, ela espreme o modelo até ele virar uma letra
                // por linha.
                if (compacto) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: pilula),
                ],
              ],
            ),
          ),
          if (!compacto) ...[
            const SizedBox(width: 12),
            pilula,
          ],
        ],
      ),
    );
  }
}

/// Um campo: rótulo, etiqueta de estado, o valor digitado e a dica.
///
/// Não é `TextField`: quem digita é o teclado da tela, e um campo nativo
/// chamaria o teclado do Android por cima dele.
/// Um dos três campos, no cartão da referência.
///
/// O cartão é a área de toque inteira: no M10 se toca com o dedo, e acertar
/// só a linha do valor é pedir mira que ninguém tem no balcão.
class _CampoDeTexto extends StatelessWidget {
  const _CampoDeTexto({
    required this.campo,
    required this.controlador,
    required this.foco,
    required this.emFoco,
    required this.comErro,
    required this.etiqueta,
    required this.dica,
    this.proximo,
  });

  final _Campo campo;
  final TextEditingController controlador;
  final FocusNode foco;
  final bool emFoco;
  final bool comErro;
  final String etiqueta;
  final String dica;

  /// Para onde o botão de avançar do teclado leva. Nulo no último campo, que
  /// fecha o teclado em vez de ir a lugar nenhum.
  final FocusNode? proximo;

  @override
  Widget build(BuildContext context) {
    final corDaBorda = comErro
        ? _Cor.erroBorda
        : emFoco
            ? Marca.azul
            : _Cor.borda;

    return GestureDetector(
      // Tocar em qualquer parte do cartão abre o teclado no campo certo.
      onTap: foco.requestFocus,
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        decoration: BoxDecoration(
          color: _Cor.cartao,
          border: Border.all(color: corDaBorda, width: 3),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: emFoco ? _Cor.sombraForte : _Cor.sombra,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    campo.rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: _Cor.tinta,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _Etiqueta(texto: etiqueta, comErro: comErro),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              // O teste encosta o dedo em cada campo por este nome.
              key: Key('campo-${campo.name}'),
              controller: controlador,
              focusNode: foco,
              keyboardType: campo.tecladoDoSistema,
              inputFormatters: campo.formatos,
              textInputAction: campo.acaoDoTeclado,
              onSubmitted: (_) {
                if (proximo case final FocusNode seguinte) {
                  seguinte.requestFocus();
                } else {
                  foco.unfocus();
                }
              },
              // Endereço e identificador são valores exatos, conferidos letra
              // por letra com o cadastro: correção automática e maiúscula no
              // começo da frase só têm como estragá-los.
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              // Nada aqui é segredo — o identificador é justamente o valor que
              // o suporte pede ao telefone.
              obscureText: false,
              cursorColor: Marca.azul,
              cursorWidth: 3,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _Cor.tinta,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '—',
                hintStyle: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _Cor.rotulo,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dica,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: comErro ? _Cor.erroTexto : _Cor.rotulo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.comErro});

  final String texto;
  final bool comErro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: comErro ? _Cor.erroFundo : _Cor.fundo,
        border: Border.all(color: comErro ? _Cor.erroBorda : _Cor.borda),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: comErro ? _Cor.erroTexto : _Cor.rotulo,
        ),
      ),
    );
  }
}

class _Acoes extends StatelessWidget {
  const _Acoes({
    required this.sugestao,
    required this.onUsarSugestao,
    required this.onSalvar,
    required this.compacto,
  });

  final String sugestao;
  final VoidCallback? onUsarSugestao;
  final VoidCallback? onSalvar;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final altura = compacto ? 64.0 : 80.0;
    final habilitado = onSalvar != null;

    final sugerir = SizedBox(
      height: altura,
      child: OutlinedButton(
        onPressed: onUsarSugestao,
        style: OutlinedButton.styleFrom(
          backgroundColor: _Cor.cartao,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: const BorderSide(color: _Cor.borda, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'USAR SUGESTÃO',
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: Marca.azul,
              ),
            ),
            if (sugestao.isNotEmpty)
              Text(
                sugestao,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: _Cor.rotulo,
                ),
              ),
          ],
        ),
      ),
    );

    final salvar = SizedBox(
      height: altura,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: habilitado ? const Color(0xFFBD6803) : _Cor.desligadoSombra,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: onSalvar,
          icon: const Icon(Icons.save_outlined, size: 28),
          style: FilledButton.styleFrom(
            backgroundColor: Marca.laranja,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _Cor.desligado,
            disabledForegroundColor: _Cor.desligadoTexto,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'SALVAR E ABRIR TERMINAL',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        Expanded(flex: 2, child: sugerir),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: salvar),
      ],
    );
  }
}

/// O que falta, ou o que vai acontecer ao salvar.
class _FaixaDeAviso extends StatelessWidget {
  const _FaixaDeAviso({required this.texto, required this.ok});

  final String texto;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: ok ? _Cor.okFundo : _Cor.faltaFundo,
        border: Border.all(
          color: ok ? _Cor.okBorda : _Cor.faltaBorda,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 24,
            color: ok ? _Cor.okTexto : _Cor.faltaTexto,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ok ? _Cor.okTexto : _Cor.faltaTexto,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Esperas
// ---------------------------------------------------------------------------

/// Enquanto o endereço digitado é testado.
class _EsperaDaConexao extends StatelessWidget {
  const _EsperaDaConexao({required this.host, required this.loja});

  final String host;
  final String loja;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Marca.azul.withValues(alpha: .94),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 6,
                  color: Marca.amarelo,
                  backgroundColor: Color(0x47FFFFFF),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Testando conexão com o servidor…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$host · loja $loja',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: .85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmação do que ficou gravado, antes de abrir a tela de senha.
class _ConfiguradoDialog extends StatelessWidget {
  const _ConfiguradoDialog({required this.terminal});

  final String terminal;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Marca.azul,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Marca.amarelo, width: 6),
                ),
                child: const Icon(Icons.check, size: 52, color: Marca.amarelo),
              ),
              const SizedBox(height: 14),
              Text(
                'Terminal $terminal configurado',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abrindo a tela de senha do terminal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: .85),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Marca.amarelo,
                    foregroundColor: Marca.azul,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'CONTINUAR',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
