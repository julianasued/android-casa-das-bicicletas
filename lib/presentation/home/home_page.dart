/// Menu do terminal, com o vendedor já selecionado.
///
/// Uma ação domina a tela — NOVA VENDA —, e o resto é ferramenta de apoio:
/// leitor, impressora e a prova de integração com o M10. Caixa, notinha e
/// sincronização são das sprints seguintes, e o menu não promete o que ainda
/// não existe.
///
/// A aparência segue `fluxo-frontend/handoff/tela-menu.html`. O que a
/// referência desenha como decoração, aqui é estado lido do aparelho: a
/// etiqueta da impressora vem de `PrinterDiagnostics.status()`, a do leitor de
/// `BarcodeScanner.isAvailable()`, a pílula de rede do `ConnectivityChannel` e
/// o rodapé da fila de sincronização. Etiqueta que não reflete o aparelho seria
/// pior que etiqueta nenhuma: o vendedor confia nela para saber se pode vender.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../domain/entities/pending_operation.dart';
import '../../domain/ports/document_printer.dart';
import '../shared/brand.dart';
import '../shared/confirmacao_do_vendedor.dart';

/// Paleta da tela, como na referência.
class _Cor {
  const _Cor._();

  static const Color fundo = Color(0xFFEEF1F8);
  static const Color cartao = Colors.white;
  static const Color borda = Color(0xFFDFE4F1);
  static const Color sombra = Color(0xFFDBE1EF);
  static const Color tinta = Color(0xFF0E1B52);
  static const Color rotulo = Color(0xFF5B6480);
  static const Color texto = Color(0xFF3C4257);

  static const Color verdeFundo = Color(0xFFEAF7EE);
  static const Color verdeBorda = Color(0xFF9ED4B1);
  static const Color verde = Color(0xFF1F8A4C);
  static const Color verdeTexto = Color(0xFF136B33);

  static const Color laranjaFundo = Color(0xFFFDF0DE);
  static const Color laranjaBorda = Color(0xFFD97B06);
  static const Color laranjaTexto = Color(0xFF8A4B00);

  static const Color vermelhoFundo = Color(0xFFFDECEC);
  static const Color vermelhoBorda = Color(0xFFE39A9A);
  static const Color vermelhoTexto = Color(0xFFA11313);

  static const Color azulFundo = Color(0xFFEAEEFB);
  static const Color grafite = Color(0xFF1D1D2E);
  static const Color grafiteFundo = Color(0xFFECEEF4);
  static const Color laranjaSombra = Color(0xFFBD6803);
}

/// Estado que vira etiqueta: a cor diz se dá para trabalhar.
enum _Estado { bom, atencao, ruim, neutro }

/// Uma etiqueta de estado — texto curto e a cor do que ele significa.
class _Etiqueta {
  const _Etiqueta(this.texto, this.estado);

  final String texto;
  final _Estado estado;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PrinterStatus? _impressora;
  bool? _temLeitor;
  QueueSummary? _fila;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lerAparelho());
  }

  /// Consulta o que a tela promete mostrar.
  ///
  /// Roda de novo ao voltar das ferramentas: quem foi à tela da impressora
  /// trocar a bobina espera encontrar a etiqueta atualizada aqui.
  Future<void> _lerAparelho() async {
    final deps = context.deps;

    final status = await deps.printerDiagnostics.status();
    final leitor = await deps.scanner.isAvailable();
    final fila = await deps.syncQueue?.summary();

    if (!mounted) return;
    setState(() {
      _impressora = status is Ok<PrinterStatus> ? status.value : null;
      _temLeitor = leitor;
      _fila = fila;
    });
  }

  Future<void> _abrir(String rota) async {
    await Navigator.of(context).pushNamed(rota);
    if (!mounted) return;
    await _lerAparelho();
  }

  /// Confirma quem é o responsável e abre a venda.
  ///
  /// A pergunta vem antes da tela, e não dentro dela, porque a venda nasce
  /// vinculada a quem está na sessão: corrigir depois de lançada é alteração
  /// de venda, não um toque. Desistir (tocar fora) não abre nada nem troca
  /// ninguém — o menu continua como estava.
  Future<void> _novaVenda() async {
    final vendedor = context.deps.session.seller?.name;
    if (vendedor == null) {
      // Sem vendedor em sessão não há o que confirmar; o roteamento inicial
      // já teria mandado esta tela para a seleção.
      await _abrir(AppRoutes.newSale);
      return;
    }

    final resposta = await confirmarVendedor(context, vendedor: vendedor);
    if (!mounted || resposta == null) return;

    switch (resposta) {
      case ConfirmacaoDoVendedor.confirmado:
        await _abrir(AppRoutes.newSale);
      case ConfirmacaoDoVendedor.trocar:
        await _trocarVendedor();
    }
  }

  /// Troca de vendedor sem fechar o terminal.
  ///
  /// Derruba só a sessão do vendedor: a autenticação do aparelho continua
  /// valendo, e é isso que evita pedir a senha do terminal a cada troca de
  /// turno no balcão.
  Future<void> _trocarVendedor() async {
    final deps = context.deps;
    final navigator = Navigator.of(context);

    await deps.session.clearSession();
    await navigator.pushNamedAndRemoveUntil(
      AppRoutes.sellerSelection,
      (_) => false,
    );
  }

  Future<void> _fecharTerminal() async {
    final deps = context.deps;
    final navigator = Navigator.of(context);

    await deps.auth.logout();
    await navigator.pushNamedAndRemoveUntil(AppRoutes.welcome, (_) => false);
  }

  // -------------------------------------------------------------------------
  // Estados lidos do aparelho
  // -------------------------------------------------------------------------

  _Etiqueta get _etiquetaDaImpressora {
    final status = _impressora;
    if (status == null) return const _Etiqueta('VERIFICANDO', _Estado.neutro);
    if (!status.available) return const _Etiqueta('OFFLINE', _Estado.ruim);
    if (status.outOfPaper) return const _Etiqueta('SEM PAPEL', _Estado.ruim);
    if (status.coverOpen) {
      return const _Etiqueta('TAMPA ABERTA', _Estado.atencao);
    }
    return const _Etiqueta('PRONTA', _Estado.bom);
  }

  _Etiqueta get _etiquetaDoLeitor => switch (_temLeitor) {
        null => const _Etiqueta('VERIFICANDO', _Estado.neutro),
        true => const _Etiqueta('LEITOR OK', _Estado.bom),
        false => const _Etiqueta('SEM LEITOR', _Estado.atencao),
      };

  /// A linha da esquerda do rodapé: impressora e fila, em texto corrido.
  String get _resumoDoSistema {
    final partes = <String>[];

    final status = _impressora;
    if (status == null) {
      partes.add('Consultando a impressora');
    } else if (!status.available) {
      partes.add('Impressora indisponível');
      if (status.detail.isNotEmpty) partes.add(status.detail);
    } else if (status.outOfPaper) {
      partes.add('Impressora sem papel');
    } else {
      partes.add('Impressora pronta · papel ok');
    }

    final fila = _fila;
    if (fila == null) {
      partes.add('sem fila local');
    } else if (fila.isEmpty) {
      partes.add('nada esperando envio');
    } else {
      partes.add(
        fila.outstanding == 1
            ? '1 operação esperando envio'
            : '${fila.outstanding} operações esperando envio',
      );
      if (fila.oldestPendingAt case final DateTime desde) {
        partes.add('desde ${formatTime(desde)}');
      }
    }

    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;

    return Scaffold(
      backgroundColor: _Cor.fundo,
      body: ListenableBuilder(
        listenable: Listenable.merge([deps.session, deps.connectivity]),
        builder: (context, _) {
          final vendedor = deps.session.seller?.name ?? 'VENDEDOR';
          final loja = deps.session.storeCode ??
              (deps.session.storeId == null ? '—' : 'L${deps.session.storeId}');
          final online = deps.connectivity.isOnline;

          return Column(
            children: [
              _Cabecalho(
                loja: loja,
                vendedor: vendedor,
                onSair: _fecharTerminal,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, restricoes) {
                    final compacto =
                        restricoes.maxWidth < 900 || restricoes.maxHeight < 560;

                    return _Corpo(
                      compacto: compacto,
                      vendedor: vendedor,
                      loja: loja,
                      online: online,
                      etiquetaDoLeitor: _etiquetaDoLeitor,
                      etiquetaDaImpressora: _etiquetaDaImpressora,
                      resumoDoSistema: _resumoDoSistema,
                      versao: deps.environment.appVersion,
                      host: _hostDaApi(deps.apiClient.baseUrl),
                      onTrocar: _trocarVendedor,
                      onNovaVenda: _novaVenda,
                      onLeitor: () => _abrir(AppRoutes.scanner),
                      onImpressora: () => _abrir(AppRoutes.printerDiagnostics),
                      onTeste: () => _abrir(AppRoutes.m10Poc),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _hostDaApi(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host.isEmpty ? baseUrl : host;
  }
}

// ---------------------------------------------------------------------------
// Cabeçalho
// ---------------------------------------------------------------------------

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.loja,
    required this.vendedor,
    required this.onSair,
  });

  final String loja;
  final String vendedor;
  final VoidCallback onSair;

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
            Flexible(
              child: Text(
                'CASA DAS BICICLETAS',
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
            SizedBox(width: compacto ? 8 : 16),
            if (!compacto)
              _ChipDoTerminal(loja: loja)
            else
              const SizedBox.shrink(),
            const Spacer(),
            _ChipDoVendedor(vendedor: vendedor, compacto: compacto),
            const SizedBox(width: 16),
            InkWell(
              onTap: onSair,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compacto ? 8 : 14,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, color: Colors.white, size: 20),
                    if (!compacto) ...[
                      const SizedBox(width: 9),
                      const Text(
                        'SAIR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipDoTerminal extends StatelessWidget {
  const _ChipDoTerminal({required this.loja});

  final String loja;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Marca.amarelo.withValues(alpha: .14),
        border: Border.all(color: Marca.amarelo.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'TERMINAL $loja',
        maxLines: 1,
        style: const TextStyle(
          color: Marca.amarelo,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ChipDoVendedor extends StatelessWidget {
  const _ChipDoVendedor({required this.vendedor, required this.compacto});

  final String vendedor;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 6,
        right: compacto ? 10 : 16,
        top: 5,
        bottom: 5,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compacto ? 28 : 30,
            height: compacto ? 28 : 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Marca.amarelo,
            ),
            child: Icon(
              Icons.person,
              size: compacto ? 17 : 18,
              color: Marca.azul,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compacto ? 84 : 190),
            child: Text(
              vendedor.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compacto ? 13 : 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corpo
// ---------------------------------------------------------------------------

class _Corpo extends StatelessWidget {
  const _Corpo({
    required this.compacto,
    required this.vendedor,
    required this.loja,
    required this.online,
    required this.etiquetaDoLeitor,
    required this.etiquetaDaImpressora,
    required this.resumoDoSistema,
    required this.versao,
    required this.host,
    required this.onTrocar,
    required this.onNovaVenda,
    required this.onLeitor,
    required this.onImpressora,
    required this.onTeste,
  });

  final bool compacto;
  final String vendedor;
  final String loja;
  final bool online;
  final _Etiqueta etiquetaDoLeitor;
  final _Etiqueta etiquetaDaImpressora;
  final String resumoDoSistema;
  final String versao;
  final String host;
  final VoidCallback onTrocar;
  final VoidCallback onNovaVenda;
  final VoidCallback onLeitor;
  final VoidCallback onImpressora;
  final VoidCallback onTeste;

  @override
  Widget build(BuildContext context) {
    final ferramentas = [
      _Ferramenta(
        elastico: !compacto,
        icone: Icons.qr_code_scanner,
        cor: Marca.azul,
        fundoDoIcone: _Cor.azulFundo,
        titulo: 'LEITOR DE CÓDIGO',
        descricao: 'Localiza a venda pelo código do documento',
        acao: 'ABRIR LEITOR',
        etiqueta: etiquetaDoLeitor,
        onTap: onLeitor,
      ),
      _Ferramenta(
        elastico: !compacto,
        icone: Icons.print_outlined,
        cor: _Cor.laranjaBorda,
        fundoDoIcone: _Cor.laranjaFundo,
        titulo: 'IMPRESSORA',
        descricao: 'Estado, avanço de papel e impressão de teste',
        acao: 'VER ESTADO',
        etiqueta: etiquetaDaImpressora,
        onTap: onImpressora,
      ),
      _Ferramenta(
        elastico: !compacto,
        icone: Icons.memory,
        cor: _Cor.grafite,
        fundoDoIcone: _Cor.grafiteFundo,
        titulo: 'TESTE ELGIN M10',
        descricao: 'Prova de integração com impressora, leitor e display',
        acao: 'RODAR TESTE',
        etiqueta: const _Etiqueta('DIAGNÓSTICO', _Estado.neutro),
        onTap: onTeste,
      ),
    ];

    final faixa = _FaixaDoVendedor(
      vendedor: vendedor,
      loja: loja,
      online: online,
      onTrocar: onTrocar,
      compacto: compacto,
    );

    final principal = _BlocoDaVenda(onTap: onNovaVenda, compacto: compacto);

    final rodape = _RodapeDoSistema(
      resumo: resumoDoSistema,
      versao: versao,
      host: host,
      compacto: compacto,
    );

    // Em retrato as três ferramentas viram uma coluna rolável: lado a lado, num
    // aparelho de 360 de largura, cada cartão fica com 110 e o título não cabe.
    if (compacto) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            faixa,
            const SizedBox(height: 12),
            principal,
            const SizedBox(height: 12),
            for (final ferramenta in ferramentas) ...[
              ferramenta,
              const SizedBox(height: 12),
            ],
            rodape,
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          faixa,
          const SizedBox(height: 14),
          // As proporções da referência: a venda domina, as ferramentas ficam
          // abaixo, e nenhuma delas tem o peso dela.
          Expanded(flex: 12, child: principal),
          const SizedBox(height: 14),
          Expanded(
            flex: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, ferramenta) in ferramentas.indexed) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: ferramenta),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          rodape,
        ],
      ),
    );
  }
}

/// Quem está no terminal, em que loja, e como trocar.
class _FaixaDoVendedor extends StatelessWidget {
  const _FaixaDoVendedor({
    required this.vendedor,
    required this.loja,
    required this.online,
    required this.onTrocar,
    required this.compacto,
  });

  final String vendedor;
  final String loja;
  final bool online;
  final VoidCallback onTrocar;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final pilula = _PilulaDeRede(loja: loja, online: online);

    final trocar = SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTrocar,
        icon: const Icon(Icons.swap_horiz, size: 22),
        style: OutlinedButton.styleFrom(
          backgroundColor: _Cor.cartao,
          foregroundColor: _Cor.texto,
          // Largura mínima própria: a do tema é `Size.fromHeight(56)`, que tem
          // largura infinita, e numa linha sem limite isso estoura o layout.
          minimumSize: const Size(132, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: const BorderSide(color: _Cor.borda, width: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        label: const Text(
          'TROCAR',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: _Cor.cartao,
        border: Border.all(color: _Cor.borda),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: online ? _Cor.verdeFundo : _Cor.laranjaFundo,
                  border: Border.all(
                    color: online ? _Cor.verdeBorda : _Cor.laranjaBorda,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  size: 26,
                  color: online ? _Cor.verde : _Cor.laranjaBorda,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'VENDEDOR NO TERMINAL',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                        color: _Cor.rotulo,
                      ),
                    ),
                    Text(
                      vendedor.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compacto ? 22 : 27,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: _Cor.tinta,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compacto) ...[
                const SizedBox(width: 16),
                pilula,
                const SizedBox(width: 16),
                trocar,
              ],
            ],
          ),
          // Em retrato a pílula e o TROCAR descem: ao lado do nome, o nome
          // sobraria com meia dúzia de pontos de largura.
          if (compacto) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: pilula),
                const SizedBox(width: 12),
                trocar,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Loja e rede, com o ponto que pulsa quando há conexão.
class _PilulaDeRede extends StatelessWidget {
  const _PilulaDeRede({required this.loja, required this.online});

  final String loja;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final cor = online ? _Cor.verdeTexto : _Cor.laranjaTexto;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: online ? _Cor.verdeFundo : _Cor.laranjaFundo,
        border: Border.all(
          color: online ? _Cor.verdeBorda : _Cor.laranjaBorda,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Ponto(cor: online ? _Cor.verde : _Cor.laranjaBorda),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              'LOJA $loja · ${online ? 'CONECTADO' : 'SEM REDE'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O ponto da pílula de rede.
///
/// Estático de propósito. A referência pulsa o ponto, e a animação em laço
/// custa caro em dois lugares: prende o teste de widget — `pumpAndSettle` nunca
/// assenta com animação infinita (§18 do fluxo) — e mantém o aparelho
/// redesenhando a tela o dia inteiro no balcão. Quem diz se há rede é a cor,
/// que muda com o estado real.
class _Ponto extends StatelessWidget {
  const _Ponto({required this.cor});

  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(shape: BoxShape.circle, color: cor),
    );
  }
}

/// A ação principal da tela — e a única com este peso.
class _BlocoDaVenda extends StatelessWidget {
  const _BlocoDaVenda({required this.onTap, required this.compacto});

  final VoidCallback onTap;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compacto ? 140 : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: _Cor.laranjaSombra, offset: Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Marca.laranja,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compacto ? 18 : 32),
              child: Row(
                children: [
                  Container(
                    width: compacto ? 68 : 92,
                    height: compacto ? 68 : 92,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .2),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .6),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      size: compacto ? 36 : 48,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: compacto ? 16 : 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'NOVA VENDA',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: compacto ? 32 : 44,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              letterSpacing: .6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Monta a venda e imprime o encaminhamento ao caixa',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compacto ? 16 : 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: .92),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right,
                    size: compacto ? 40 : 54,
                    color: Colors.white.withValues(alpha: .9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Um cartão de ferramenta, com a etiqueta do estado real.
class _Ferramenta extends StatelessWidget {
  const _Ferramenta({
    required this.elastico,
    required this.icone,
    required this.cor,
    required this.fundoDoIcone,
    required this.titulo,
    required this.descricao,
    required this.acao,
    required this.etiqueta,
    required this.onTap,
  });

  /// Na grade de três colunas o cartão preenche a célula; empilhado numa
  /// coluna rolável, ele tem a altura do próprio conteúdo — altura fixa ali
  /// corta o rodapé da ação.
  final bool elastico;

  final IconData icone;
  final Color cor;
  final Color fundoDoIcone;
  final String titulo;
  final String descricao;
  final String acao;
  final _Etiqueta etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: _Cor.sombra, offset: Offset(0, 6))],
      ),
      child: Material(
        color: _Cor.cartao,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              border: Border.all(color: _Cor.borda),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: elastico ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: fundoDoIcone,
                        border: Border.all(color: cor, width: 2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icone, size: 34, color: cor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _EtiquetaDeEstado(etiqueta: etiqueta),
                      ),
                    ),
                  ],
                ),
                if (elastico) const Spacer() else const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    titulo,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.08,
                      color: _Cor.tinta,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _Cor.rotulo,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        acao,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                          color: Marca.azul,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 26, color: Marca.azul),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EtiquetaDeEstado extends StatelessWidget {
  const _EtiquetaDeEstado({required this.etiqueta});

  final _Etiqueta etiqueta;

  @override
  Widget build(BuildContext context) {
    final (fundo, borda, texto) = switch (etiqueta.estado) {
      _Estado.bom => (_Cor.verdeFundo, _Cor.verdeBorda, _Cor.verdeTexto),
      _Estado.atencao => (
          _Cor.laranjaFundo,
          _Cor.laranjaBorda,
          _Cor.laranjaTexto
        ),
      _Estado.ruim => (
          _Cor.vermelhoFundo,
          _Cor.vermelhoBorda,
          _Cor.vermelhoTexto
        ),
      _Estado.neutro => (_Cor.fundo, _Cor.borda, _Cor.rotulo),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: fundo,
        border: Border.all(color: borda),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        etiqueta.texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: texto,
        ),
      ),
    );
  }
}

/// A linha de sistema: o que está funcionando e para onde o terminal fala.
class _RodapeDoSistema extends StatelessWidget {
  const _RodapeDoSistema({
    required this.resumo,
    required this.versao,
    required this.host,
    required this.compacto,
  });

  final String resumo;
  final String versao;
  final String host;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: _Cor.rotulo,
    );

    final esquerda = Text(
      resumo,
      maxLines: compacto ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: estilo,
    );
    final direita = Text(
      'app $versao · $host',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: compacto ? TextAlign.left : TextAlign.right,
      style: estilo,
    );

    if (compacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [esquerda, const SizedBox(height: 2), direita],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(child: esquerda),
          const SizedBox(width: 16),
          Flexible(child: direita),
        ],
      ),
    );
  }
}
