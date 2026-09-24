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
/// - **O teclado é o do aplicativo**, não o do Android. No M10 o teclado do
///   sistema cobre metade da tela e some com o campo que está sendo digitado —
///   o mesmo motivo que fez a tela de senha desenhar o dela.
library;

import 'package:flutter/material.dart';

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
  static const Color texto = Color(0xFF3A4260);
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

  static const Color tecladoFundo = Color(0xFFE6E9F4);
  static const Color teclaSombra = Color(0xFFC3C9DE);
  static const Color teclaEspecialSombra = Color(0xFFC9A209);
  static const Color azulSombra = Color(0xFF001259);
}

/// Qual campo está sendo digitado.
enum _Campo {
  api('ENDEREÇO DA API'),
  loja('LOJA (ID)'),
  terminal('IDENTIFICADOR DO TERMINAL (X-DEVICE-ID)');

  const _Campo(this.rotulo);

  final String rotulo;

  /// A loja é só número; os outros dois usam o teclado alfanumérico.
  bool get numerico => this == _Campo.loja;
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  /// Valores em edição. Ficam aqui, e não em `TextEditingController`, porque
  /// quem digita é o teclado da tela — não há campo nativo para controlar.
  final Map<_Campo, String> _valores = {
    _Campo.api: '',
    _Campo.loja: '',
    _Campo.terminal: '',
  };

  DeviceInfo _aparelho = const DeviceInfo.unknown();
  _Campo? _emFoco;
  bool _carregando = true;
  bool _salvando = false;
  String? _erroDoServidor;

  String get _api => _valores[_Campo.api]!.trim();
  String get _loja => _valores[_Campo.loja]!.trim();
  String get _terminal => _valores[_Campo.terminal]!.trim();

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final deps = context.deps;
    final aparelho = await deps.device.read();
    if (!mounted) return;

    final sessao = deps.session;
    setState(() {
      _aparelho = aparelho;
      _valores[_Campo.api] = sessao.baseUrlOverride ?? deps.environment.apiBaseUrl;
      _valores[_Campo.loja] = sessao.storeId?.toString() ?? '';
      _valores[_Campo.terminal] = sessao.deviceId ?? aparelho.androidId;
      _carregando = false;
    });
  }

  void _digitar(String tecla) {
    final campo = _emFoco;
    if (campo == null) return;

    var valor = _valores[campo]!;
    valor = switch (tecla) {
      _Teclado.apagar => valor.isEmpty ? valor : valor.substring(0, valor.length - 1),
      _Teclado.espaco => '$valor ',
      _ => '$valor$tecla',
    };

    // A loja é um id: só dígitos, e nenhum terminal tem id de cinco casas.
    if (campo.numerico) {
      valor = valor.replaceAll(RegExp(r'\D'), '');
      if (valor.length > 4) valor = valor.substring(0, 4);
    }

    setState(() {
      _valores[campo] = valor.trimLeft();
      _erroDoServidor = null;
    });
  }

  void _limparCampo() {
    final campo = _emFoco;
    if (campo == null) return;
    setState(() {
      _valores[campo] = '';
      _erroDoServidor = null;
    });
  }

  void _usarSugestao() {
    if (_sugestao.isEmpty) return;
    setState(() {
      _valores[_Campo.terminal] = _sugestao;
      _erroDoServidor = null;
    });
  }

  Future<void> _salvar() async {
    if (!_valido || _salvando) return;

    final deps = context.deps;
    final navigator = Navigator.of(context);

    setState(() {
      _emFoco = null;
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
                        valores: _valores,
                        emFoco: _emFoco,
                        apiComErro: _apiComErro,
                        valido: _valido,
                        sugestao: _sugestao,
                        aviso: _aviso(),
                        avisoOk: _valido && _erroDoServidor == null,
                        onFocar: (campo) => setState(() => _emFoco = campo),
                        onUsarSugestao: _usarSugestao,
                        onSalvar: _valido ? _salvar : null,
                      ),
              ),
            ],
          ),
          if (_emFoco case final _Campo campo)
            _Teclado(
              campo: campo,
              valor: _valores[campo]!,
              onTecla: _digitar,
              onLimpar: _limparCampo,
              onPronto: () => setState(() => _emFoco = null),
              onFechar: () => setState(() => _emFoco = null),
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
    required this.valores,
    required this.emFoco,
    required this.apiComErro,
    required this.valido,
    required this.sugestao,
    required this.aviso,
    required this.avisoOk,
    required this.onFocar,
    required this.onUsarSugestao,
    required this.onSalvar,
  });

  final DeviceInfo aparelho;
  final Map<_Campo, String> valores;
  final _Campo? emFoco;
  final bool apiComErro;
  final bool valido;
  final String sugestao;
  final String aviso;
  final bool avisoOk;
  final ValueChanged<_Campo> onFocar;
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
                valor: valores[_Campo.api]!,
                emFoco: emFoco == _Campo.api,
                comErro: apiComErro,
                etiqueta: apiComErro ? 'USE HTTPS' : 'OBRIGATÓRIO',
                dica: 'HTTPS obrigatório (RNF01).',
                onTap: () => onFocar(_Campo.api),
              ),
              const SizedBox(height: 12),
              _CampoDeTexto(
                campo: _Campo.loja,
                valor: valores[_Campo.loja]!,
                emFoco: emFoco == _Campo.loja,
                comErro: false,
                etiqueta: 'OBRIGATÓRIO',
                dica: 'Id da loja cadastrada no sistema.',
                onTap: () => onFocar(_Campo.loja),
              ),
              const SizedBox(height: 12),
              _CampoDeTexto(
                campo: _Campo.terminal,
                valor: valores[_Campo.terminal]!,
                emFoco: emFoco == _Campo.terminal,
                comErro: false,
                etiqueta: 'OBRIGATÓRIO',
                dica: sugestao.isEmpty
                    ? 'Deve ser igual ao cadastrado no terminal.'
                    : 'Sugestão do aparelho: $sugestao',
                onTap: () => onFocar(_Campo.terminal),
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
class _CampoDeTexto extends StatelessWidget {
  const _CampoDeTexto({
    required this.campo,
    required this.valor,
    required this.emFoco,
    required this.comErro,
    required this.etiqueta,
    required this.dica,
    required this.onTap,
  });

  final _Campo campo;
  final String valor;
  final bool emFoco;
  final bool comErro;
  final String etiqueta;
  final String dica;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final corDaBorda = comErro
        ? _Cor.erroBorda
        : emFoco
            ? Marca.azul
            : _Cor.borda;

    return Semantics(
      textField: true,
      label: campo.rotulo,
      value: valor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
              Row(
                children: [
                  Expanded(child: _ValorDoCampo(valor: valor)),
                  if (emFoco) ...[
                    const SizedBox(width: 8),
                    Container(width: 3, height: 30, color: Marca.azul),
                  ],
                ],
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
      ),
    );
  }
}

/// O valor digitado, ancorado no fim quando é comprido.
///
/// Uma URL longa cortada no começo esconde justamente o que muda entre um
/// ambiente e outro — o fim do caminho. Ancorar no fim mostra o que interessa
/// conferir.
class _ValorDoCampo extends StatelessWidget {
  const _ValorDoCampo({required this.valor});

  final String valor;

  static const int _limiteDaCauda = 44;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      color: _Cor.tinta,
    );

    if (valor.isEmpty) {
      return const Text(
        '—',
        maxLines: 1,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _Cor.rotulo),
      );
    }

    if (valor.length <= _limiteDaCauda) {
      return Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(valor, maxLines: 1, softWrap: false, style: estilo),
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
// Teclado do PDV
// ---------------------------------------------------------------------------

/// Teclado da tela, que sobe de baixo quando um campo é tocado.
///
/// O do Android não serve aqui: no M10 ele cobre metade da tela e some com o
/// campo que está sendo preenchido. Este mostra o que está sendo digitado na
/// própria barra, por cima das teclas.
class _Teclado extends StatelessWidget {
  const _Teclado({
    required this.campo,
    required this.valor,
    required this.onTecla,
    required this.onLimpar,
    required this.onPronto,
    required this.onFechar,
  });

  /// Marcadores das teclas que não são caractere.
  static const String apagar = ' apagar';
  static const String espaco = ' espaco';

  static const List<List<String>> _alfabeto = [
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', 'Ç', apagar],
    [espaco],
  ];

  static const List<List<String>> _numerico = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [espaco, '0', apagar],
  ];

  final _Campo campo;
  final String valor;
  final ValueChanged<String> onTecla;
  final VoidCallback onLimpar;
  final VoidCallback onPronto;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    final numerico = campo.numerico;
    final compacto = MediaQuery.sizeOf(context).width < 900;

    return Positioned.fill(
      child: Column(
        // `stretch` para o véu de cima ocupar a largura toda: sem isso ele
        // nasce com a menor largura possível — zero —, e o toque fora do
        // teclado não teria onde acontecer.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tocar fora fecha o teclado, como na referência.
          Expanded(
            child: GestureDetector(
              onTap: onFechar,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(color: Colors.black.withValues(alpha: .35)),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              compacto ? 12 : 20,
              14,
              compacto ? 12 : 20,
              18 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: _Cor.tecladoFundo,
              border: Border(top: BorderSide(color: Marca.azul, width: 4)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x400A143C),
                  offset: Offset(0, -12),
                  blurRadius: 30,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BarraDoTeclado(
                  campo: campo,
                  valor: valor,
                  onLimpar: onLimpar,
                  onPronto: onPronto,
                  compacto: compacto,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, restricoes) => _Teclas(
                    linhas: numerico ? _numerico : _alfabeto,
                    numerico: numerico,
                    largura: restricoes.maxWidth,
                    onTecla: onTecla,
                    onLimpar: onLimpar,
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

/// A barra do teclado: que campo está sendo digitado e o que já foi digitado.
class _BarraDoTeclado extends StatelessWidget {
  const _BarraDoTeclado({
    required this.campo,
    required this.valor,
    required this.onLimpar,
    required this.onPronto,
    required this.compacto,
  });

  final _Campo campo;
  final String valor;
  final VoidCallback onLimpar;
  final VoidCallback onPronto;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _Cor.cartao,
              border: Border.all(color: Marca.azul, width: 3),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: _Cor.sombraForte, offset: Offset(0, 5)),
              ],
            ),
            child: Row(
              children: [
                if (!compacto) ...[
                  Text(
                    campo.rotulo,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: _Cor.rotulo,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(child: _ValorDoCampo(valor: valor)),
                const SizedBox(width: 8),
                Container(width: 3, height: 30, color: Marca.azul),
              ],
            ),
          ),
        ),
        SizedBox(width: compacto ? 8 : 14),
        SizedBox(
          height: 64,
          child: OutlinedButton(
            onPressed: onLimpar,
            style: OutlinedButton.styleFrom(
              backgroundColor: _Cor.cartao,
              foregroundColor: _Cor.texto,
              padding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 18),
              side: const BorderSide(color: Color(0xFFC3C9DE), width: 2),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              compacto ? 'LIMPAR' : 'LIMPAR CAMPO',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ),
        ),
        SizedBox(width: compacto ? 8 : 14),
        SizedBox(
          height: 64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: _Cor.azulSombra, offset: Offset(0, 5)),
              ],
            ),
            child: FilledButton.icon(
              onPressed: onPronto,
              icon: const Icon(Icons.check, color: Marca.amarelo, size: 22),
              style: FilledButton.styleFrom(
                backgroundColor: Marca.azul,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: const Text(
                'PRONTO',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// As fileiras de teclas.
class _Teclas extends StatelessWidget {
  const _Teclas({
    required this.linhas,
    required this.numerico,
    required this.largura,
    required this.onTecla,
    required this.onLimpar,
  });

  final List<List<String>> linhas;
  final bool numerico;
  final double largura;
  final ValueChanged<String> onTecla;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    const vao = 9.0;

    // A largura da tecla sai da fileira mais cheia: assim todas as fileiras
    // usam a mesma medida e as colunas ficam alinhadas, em qualquer tela.
    final colunas = linhas.map((linha) => linha.length).reduce(
          (maior, atual) => atual > maior ? atual : maior,
        );
    final larguraDaTecla =
        ((largura - vao * (colunas - 1)) / colunas).clamp(40.0, numerico ? 172.0 : 96.0);
    final alturaDaTecla = numerico ? 82.0 : 74.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, linha) in linhas.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (j, tecla) in linha.indexed) ...[
                if (j > 0) const SizedBox(width: vao),
                _Tecla(
                  tecla: tecla,
                  numerico: numerico,
                  largura: _larguraDe(tecla, larguraDaTecla, colunas, vao),
                  altura: alturaDaTecla,
                  onPressed: () {
                    // No teclado numérico o lugar do ESPAÇO é o LIMPAR: espaço
                    // não entra num id de loja.
                    if (numerico && tecla == _Teclado.espaco) {
                      onLimpar();
                    } else {
                      onTecla(tecla);
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// A barra de espaço vale por várias colunas, como na referência.
  double _larguraDe(String tecla, double base, int colunas, double vao) {
    if (numerico || tecla != _Teclado.espaco) return base;
    const colunasDoEspaco = 6;
    return base * colunasDoEspaco + vao * (colunasDoEspaco - 1);
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla({
    required this.tecla,
    required this.numerico,
    required this.largura,
    required this.altura,
    required this.onPressed,
  });

  final String tecla;
  final bool numerico;
  final double largura;
  final double altura;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final apagar = tecla == _Teclado.apagar;
    final espaco = tecla == _Teclado.espaco;
    final especial = apagar || espaco;

    final rotulo = apagar
        ? '⌫'
        : espaco
            ? (numerico ? 'LIMPAR' : 'ESPAÇO')
            : tecla;

    return SizedBox(
      width: largura,
      height: altura,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: especial ? _Cor.teclaEspecialSombra : _Cor.teclaSombra,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: especial ? Marca.amarelo : _Cor.cartao,
            foregroundColor: _Cor.tinta,
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                rotulo,
                style: TextStyle(
                  fontSize: especial && !apagar
                      ? 20
                      : numerico
                          ? 34
                          : 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
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
