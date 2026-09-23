/// Desfecho da venda: o que foi registrado e o que saiu na impressora.
///
/// A tela existe por causa de um caso concreto: a venda é registrada e o papel
/// **não** sai — acabou a bobina. A venda continua válida, o cliente está no
/// balcão, e o que resolve é reimprimir, não refazer. Por isso o estado da
/// impressão aparece separado do estado da venda, e a reimpressão ganha
/// destaque quando a impressão falhou.
///
/// A aparência segue `fluxo-frontend/handoff/tela-venda-registrada.html`: duas
/// colunas sobre o fundo `#eef1f8`, o cartão verde com o total em 64, a faixa
/// laranja da situação, o bloco azul do documento e, à direita, os dados da
/// venda com os itens rolando. A referência é desenhada para 1280x800 em
/// paisagem; em retrato as mesmas peças viram uma coluna só, com as ações
/// fixas no pé — o que não pode é cortar valor nem esconder a saída da tela.
///
/// Duas coisas que a referência não desenha e que a tela não pode perder: a
/// venda que ficou na fila por falta de rede (RF35) e a impressão que falhou
/// (§11). As duas entram como faixa, no mesmo vocabulário visual.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/result.dart';
import '../../domain/entities/printed_document.dart';
import '../../domain/entities/sale.dart';
import '../../domain/usecases/create_sale.dart';
import '../receipt/receipt_page.dart';
import '../shared/brand.dart';
import '../shared/confirmacao_do_vendedor.dart';
import '../shared/feedback.dart';

/// Paleta da tela, como na referência.
class _Cor {
  const _Cor._();

  static const Color fundo = Color(0xFFEEF1F8);
  static const Color cartao = Colors.white;
  static const Color borda = Color(0xFFDFE4F1);
  static const Color tinta = Color(0xFF0E1B52);
  static const Color rotulo = Color(0xFF5B6480);
  static const Color texto = Color(0xFF3C4257);

  static const Color verde = Color(0xFF1F8A4C);
  static const Color verdeEscuro = Color(0xFF15703C);
  static const Color verdeSombra = Color(0xFF0E5B2F);
  static const Color verdeRotulo = Color(0xFFD8F2E2);
  static const Color verdeCodigo = Color(0xFFBFE7CF);

  static const Color laranjaFundo = Color(0xFFFDF0DE);
  static const Color laranjaBorda = Color(0xFFD97B06);
  static const Color laranjaSombra = Color(0xFFE9CFA6);
  static const Color laranjaRotulo = Color(0xFF8A4B00);
  static const Color laranjaTexto = Color(0xFF6B3A00);
  static const Color laranjaBordaFraca = Color(0xFFF3D7A8);

  static const Color itemFundo = Color(0xFFF7F9FD);
  static const Color itemBorda = Color(0xFFE6EAF4);
  static const Color avisoTexto = Color(0xFFC9D0EE);

  static const Color vermelhoFundo = Color(0xFF7A1F1F);
  static const Color vermelhoBorda = Color(0xFFE23B3B);

  /// Cores por categoria, as mesmas da montagem da venda.
  static Color categoria(String code) => switch (code) {
        'PECAS' => const Color(0xFF0020AD),
        'PNEUS' => const Color(0xFF1D1D2E),
        'OLEOS' => const Color(0xFFD97B06),
        _ => Marca.azul,
      };
}

class SaleFinishedPage extends StatefulWidget {
  const SaleFinishedPage({required this.finished, super.key});

  final SaleFinished finished;

  @override
  State<SaleFinishedPage> createState() => _SaleFinishedPageState();
}

class _SaleFinishedPageState extends State<SaleFinishedPage> {
  bool _reprinting = false;
  late bool _printed = widget.finished.printed;

  /// Qual via está na mão do cliente.
  ///
  /// Sai do próprio documento (`sequence`), e não de um contador da tela: é o
  /// número que o servidor registrou e que está impresso no papel. A primeira
  /// impressão é a via 1; cada reimpressão avança.
  late int _via = widget.finished.result.document?.sequence ?? 1;

  Sale get _sale => widget.finished.result.sale;

  Future<void> _reprint() async {
    setState(() => _reprinting = true);

    final result =
        await context.deps.reprintDocument(_sale.id, DocumentType.doc1);

    if (!mounted) return;
    setState(() => _reprinting = false);

    switch (result) {
      case Ok(:final value):
        setState(() {
          _printed = true;
          _via = value.sequence;
        });
        showMessage(context, 'Documento reimpresso — via ${value.sequence}.');
      case Err(:final failure):
        showFailure(context, failure);
    }
  }

  /// Repouso do terminal: a venda acabou e ninguém está esperando.
  void _inicio() => Navigator.of(context)
      .pushNamedAndRemoveUntil(AppRoutes.welcome, (_) => false);

  /// Outra venda, do zero: a montagem nasce com o rascunho vazio.
  ///
  /// Confirma o responsável antes de abrir. É aqui que o turno costuma virar —
  /// a venda acabou, o balcão trocou de gente —, e a sessão do vendedor não
  /// muda sozinha: sem a pergunta, a venda seguinte sai no nome de quem fez a
  /// anterior.
  Future<void> _novaVenda() async {
    final vendedor = context.deps.session.seller?.name;
    final navigator = Navigator.of(context);

    if (vendedor == null) {
      await navigator.pushNamedAndRemoveUntil(AppRoutes.newSale, (_) => false);
      return;
    }

    final resposta = await confirmarVendedor(context, vendedor: vendedor);
    if (!mounted || resposta == null) return;

    switch (resposta) {
      case ConfirmacaoDoVendedor.confirmado:
        await navigator.pushNamedAndRemoveUntil(
          AppRoutes.newSale,
          (_) => false,
        );
      case ConfirmacaoDoVendedor.trocar:
        // Derruba só a sessão do vendedor: o terminal continua aberto e a
        // senha do aparelho não volta a ser pedida.
        await context.deps.session.clearSession();
        if (!mounted) return;
        await navigator.pushNamedAndRemoveUntil(
          AppRoutes.sellerSelection,
          (_) => false,
        );
    }
  }

  Future<void> _sair() async {
    final deps = context.deps;
    final navigator = Navigator.of(context);
    await deps.auth.logout();
    if (!mounted) return;
    await navigator.pushNamedAndRemoveUntil(AppRoutes.welcome, (_) => false);
  }

  /// Ferramentas do terminal — as mesmas do cabeçalho da venda.
  Future<void> _abrirMenu() async {
    final navigator = Navigator.of(context);
    final destino = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Leitor de código'),
              onTap: () => Navigator.of(context).pop(AppRoutes.scanner),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Impressora'),
              onTap: () =>
                  Navigator.of(context).pop(AppRoutes.printerDiagnostics),
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Teste Elgin M10'),
              onTap: () => Navigator.of(context).pop(AppRoutes.m10Poc),
            ),
          ],
        ),
      ),
    );

    if (destino != null) await navigator.pushNamed(destino);
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;

    return PopScope(
      // Voltar para a montagem depois da venda registrada só levaria a um
      // carrinho já enviado. A saída é INÍCIO ou NOVA VENDA.
      canPop: false,
      child: Scaffold(
        backgroundColor: _Cor.fundo,
        body: Stack(
          children: [
            Column(
              children: [
                _Cabecalho(
                  numeroDaVenda: _numeroDaVenda(_sale.id),
                  vendedor: deps.session.seller?.name ?? _sale.sellerName,
                  onMenu: _abrirMenu,
                  onSair: _sair,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, restricoes) {
                      // Duas colunas só quando há espaço nas duas direções: a
                      // referência é de 1280x800, e espremê-la numa tela baixa
                      // põe o cartão do total e os itens disputando altura que
                      // não existe.
                      final compacto = restricoes.maxWidth < 900 ||
                          restricoes.maxHeight < 560;

                      return compacto
                          ? _CorpoEstreito(
                              finished: widget.finished,
                              via: _via,
                              impresso: _printed,
                              reimprimindo: _reprinting,
                              onReimprimir: _reprint,
                              onInicio: _inicio,
                              onNovaVenda: _novaVenda,
                            )
                          : _CorpoLargo(
                              finished: widget.finished,
                              via: _via,
                              impresso: _printed,
                              reimprimindo: _reprinting,
                              onReimprimir: _reprint,
                              onInicio: _inicio,
                              onNovaVenda: _novaVenda,
                            );
                    },
                  ),
                ),
              ],
            ),
            if (_reprinting)
              _EsperaDaReimpressao(
                codigo: _sale.barcode,
                total: _sale.totalAmount,
              ),
          ],
        ),
      ),
    );
  }
}

/// `#0010` — o número que o cliente lê no papel e diz no caixa.
String _numeroDaVenda(int id) => '#${id.toString().padLeft(4, '0')}';

// ---------------------------------------------------------------------------
// Cabeçalho
// ---------------------------------------------------------------------------

/// Cabeçalho azul: menu, título, número da venda, vendedor e a saída.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.numeroDaVenda,
    required this.vendedor,
    required this.onMenu,
    required this.onSair,
  });

  final String numeroDaVenda;
  final String vendedor;
  final VoidCallback onMenu;
  final VoidCallback onSair;

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 900;

    return Container(
      // O azul sobe até a borda do aparelho e o conteúdo desce o tanto que a
      // barra de status ocupa — em quiosque isso é zero, e a conta continua
      // certa nos aparelhos onde a barra aparece.
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
            _BotaoDoCabecalho(
              onTap: onMenu,
              lado: compacto ? 40 : 44,
              child: const Icon(Icons.menu, color: Colors.white, size: 22),
            ),
            SizedBox(width: compacto ? 10 : 16),
            Flexible(
              child: Text(
                'VENDA REGISTRADA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compacto ? 17 : 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            SizedBox(width: compacto ? 8 : 16),
            // O número da venda no amarelo da marca: é o que o caixa pede.
            // Em retrato ele sai daqui — está em corpo grande no cartão verde,
            // logo abaixo, e na barra só espremeria o título e o vendedor.
            if (!compacto)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Marca.amarelo.withValues(alpha: .14),
                  border:
                      Border.all(color: Marca.amarelo.withValues(alpha: .4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  numeroDaVenda,
                  style: const TextStyle(
                    color: Marca.amarelo,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            const Spacer(),
            // Vendedor e SAIR são um grupo só, colado no canto direito.
            Container(
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
                    constraints: BoxConstraints(
                      maxWidth: compacto ? 76 : 190,
                    ),
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
            ),
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

class _BotaoDoCabecalho extends StatelessWidget {
  const _BotaoDoCabecalho({
    required this.onTap,
    required this.lado,
    required this.child,
  });

  final VoidCallback onTap;
  final double lado;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: lado,
        height: lado,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corpos
// ---------------------------------------------------------------------------

/// Duas colunas, como na referência de 1280x800.
class _CorpoLargo extends StatelessWidget {
  const _CorpoLargo({
    required this.finished,
    required this.via,
    required this.impresso,
    required this.reimprimindo,
    required this.onReimprimir,
    required this.onInicio,
    required this.onNovaVenda,
  });

  final SaleFinished finished;
  final int via;
  final bool impresso;
  final bool reimprimindo;
  final VoidCallback onReimprimir;
  final VoidCallback onInicio;
  final VoidCallback onNovaVenda;

  @override
  Widget build(BuildContext context) {
    final sale = finished.result.sale;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 452,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // O que conta a venda rola quando não cabe — com a fonte do
                // sistema ampliada, os três blocos passam da altura da coluna.
                // A reimpressão fica presa no pé, como o `margin-top:auto` da
                // referência: é a ação que salva o balcão quando falta papel, e
                // não pode depender de rolar até ela.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CartaoDeSucesso(sale: sale),
                        const SizedBox(height: 12),
                        _FaixaDaSituacao(sale: sale),
                        if (finished.awaitsSync) ...[
                          const SizedBox(height: 12),
                          const _FaixaDaFila(),
                        ],
                        const SizedBox(height: 12),
                        _AvisoDoDocumento(
                          impresso: impresso,
                          motivo: finished.printFailure?.message,
                          notinha: sale.paymentMethod.requiresCustomer,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _BotaoDeReimpressao(
                  via: via,
                  impresso: impresso,
                  ocupado: reimprimindo,
                  onPressed: onReimprimir,
                ),
                if (finished.result.document case final documento?) ...[
                  const SizedBox(height: 10),
                  _BotaoDeComprovante(document: documento, finished: finished),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CartoesDeDados(sale: sale),
                const SizedBox(height: 12),
                _CartaoDoCliente(
                  nome: sale.customerName,
                  telefone: finished.customerPhone,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _PainelDeItens(
                    sale: sale,
                    percentualDoDesconto: finished.discountPercentHundredths,
                  ),
                ),
                const SizedBox(height: 12),
                _Acoes(
                  compacto: false,
                  onInicio: onInicio,
                  onNovaVenda: onNovaVenda,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Coluna única, para o retrato do M10.
///
/// As mesmas peças, na ordem em que interessam: o que foi registrado, a
/// situação, o documento, os dados e os itens. As duas ações ficam fixas no pé
/// — são a única saída da tela, e não podem depender de rolar até o fim.
class _CorpoEstreito extends StatelessWidget {
  const _CorpoEstreito({
    required this.finished,
    required this.via,
    required this.impresso,
    required this.reimprimindo,
    required this.onReimprimir,
    required this.onInicio,
    required this.onNovaVenda,
  });

  final SaleFinished finished;
  final int via;
  final bool impresso;
  final bool reimprimindo;
  final VoidCallback onReimprimir;
  final VoidCallback onInicio;
  final VoidCallback onNovaVenda;

  @override
  Widget build(BuildContext context) {
    final sale = finished.result.sale;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CartaoDeSucesso(sale: sale, compacto: true),
                const SizedBox(height: 10),
                _FaixaDaSituacao(sale: sale),
                if (finished.awaitsSync) ...[
                  const SizedBox(height: 10),
                  const _FaixaDaFila(),
                ],
                const SizedBox(height: 10),
                _AvisoDoDocumento(
                  impresso: impresso,
                  motivo: finished.printFailure?.message,
                  notinha: sale.paymentMethod.requiresCustomer,
                ),
                const SizedBox(height: 10),
                _BotaoDeReimpressao(
                  via: via,
                  impresso: impresso,
                  ocupado: reimprimindo,
                  onPressed: onReimprimir,
                ),
                if (finished.result.document case final documento?) ...[
                  const SizedBox(height: 10),
                  _BotaoDeComprovante(document: documento, finished: finished),
                ],
                const SizedBox(height: 10),
                _CartoesDeDados(sale: sale, compacto: true),
                const SizedBox(height: 10),
                _CartaoDoCliente(
                  nome: sale.customerName,
                  telefone: finished.customerPhone,
                  compacto: true,
                ),
                const SizedBox(height: 10),
                _PainelDeItens(
                  sale: sale,
                  percentualDoDesconto: finished.discountPercentHundredths,
                  rolavel: false,
                ),
              ],
            ),
          ),
        ),
        Material(
          elevation: 8,
          color: _Cor.cartao,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              10 + MediaQuery.paddingOf(context).bottom,
            ),
            child: _Acoes(
              compacto: true,
              onInicio: onInicio,
              onNovaVenda: onNovaVenda,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coluna da esquerda
// ---------------------------------------------------------------------------

/// O cartão verde: o que foi registrado, com o total em corpo grande.
class _CartaoDeSucesso extends StatelessWidget {
  const _CartaoDeSucesso({required this.sale, this.compacto = false});

  final Sale sale;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(22, compacto ? 14 : 18, 22, compacto ? 16 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Cor.verde, _Cor.verdeEscuro],
        ),
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: _Cor.verdeSombra, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: compacto ? 56 : 72,
            height: compacto ? 56 : 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Marca.amarelo,
            ),
            child: Icon(
              Icons.check_rounded,
              size: compacto ? 34 : 42,
              color: _Cor.verdeEscuro,
            ),
          ),
          SizedBox(height: compacto ? 8 : 10),
          Text(
            'VENDA FINALIZADA',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compacto ? 14 : 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              color: _Cor.verdeRotulo,
            ),
          ),
          Text(
            'Venda ${_numeroDaVenda(sale.id)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compacto ? 28 : 34,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: Colors.white,
            ),
          ),
          // O código interno, que é o que o caixa bipa.
          Text(
            sale.barcode,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compacto ? 14 : 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _Cor.verdeCodigo,
            ),
          ),
          SizedBox(height: compacto ? 6 : 10),
          // O número que o cliente confere de longe.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              sale.totalAmount.toDisplayString(),
              style: TextStyle(
                fontSize: compacto ? 44 : 64,
                fontWeight: FontWeight.w800,
                height: 1,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faixa da situação da venda.
///
/// Mostra o estado que o servidor registrou, e não um texto fixo: numa venda em
/// notinha o estado é outro, e escrever "aguardando caixa" ali seria mentira.
/// Em nenhum caminho a tela chama a venda de paga — quem paga é o caixa.
class _FaixaDaSituacao extends StatelessWidget {
  const _FaixaDaSituacao({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return _Faixa(
      icone: Icons.schedule,
      rotulo: 'SITUAÇÃO',
      valor: sale.status.label,
      fundo: _Cor.laranjaFundo,
      borda: _Cor.laranjaBorda,
      sombra: _Cor.laranjaSombra,
      corDoRotulo: _Cor.laranjaRotulo,
      corDoValor: _Cor.laranjaTexto,
    );
  }
}

/// A venda está no aparelho e ainda vai subir (§17 do fluxo, RF35).
///
/// Sem este aviso a tela diria a mesma coisa nos dois casos — o mesmo ✓ verde
/// de "registrada" —, e o vendedor sairia achando que o servidor já sabe da
/// venda. Ele não sabe ainda, e é isso que precisa estar escrito.
class _FaixaDaFila extends StatelessWidget {
  const _FaixaDaFila();

  @override
  Widget build(BuildContext context) {
    return const _Faixa(
      icone: Icons.cloud_upload_outlined,
      rotulo: 'SINCRONIZAÇÃO',
      valor: 'Registrada no terminal, ainda não enviada',
      apoio: 'Sem rede agora. A venda sobe sozinha quando a conexão voltar, e '
          'o documento já vale no caixa.',
      fundo: Color(0xFFE8ECFB),
      borda: Marca.azul,
      sombra: Color(0xFFCBD3F0),
      corDoRotulo: Marca.azul,
      corDoValor: _Cor.tinta,
    );
  }
}

/// Faixa de estado: ícone em quadrado colorido, rótulo miúdo e o valor grande.
class _Faixa extends StatelessWidget {
  const _Faixa({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.fundo,
    required this.borda,
    required this.sombra,
    required this.corDoRotulo,
    required this.corDoValor,
    this.apoio,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final String? apoio;
  final Color fundo;
  final Color borda;
  final Color sombra;
  final Color corDoRotulo;
  final Color corDoValor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: fundo,
        border: Border.all(color: borda, width: 3),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: sombra, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: borda,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icone, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: corDoRotulo,
                  ),
                ),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: corDoValor,
                  ),
                ),
                if (apoio case final String texto) ...[
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: corDoValor.withValues(alpha: .85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// O bloco azul do documento — e o alerta quando o papel não saiu.
///
/// O trecho em amarelo é o que não pode sumir: documento 1 **não** é
/// comprovante de pagamento (RF08). Quem confunde os dois manda o cliente
/// embora achando que já pagou.
class _AvisoDoDocumento extends StatelessWidget {
  const _AvisoDoDocumento({
    required this.impresso,
    required this.notinha,
    this.motivo,
  });

  final bool impresso;
  final bool notinha;
  final String? motivo;

  @override
  Widget build(BuildContext context) {
    final titulo = impresso
        ? 'Documento de encaminhamento impresso'
        : 'O documento não foi impresso';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: impresso ? _Cor.tinta : _Cor.vermelhoFundo,
        border:
            impresso ? null : Border.all(color: _Cor.vermelhoBorda, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Marca.amarelo.withValues(alpha: .18),
              border: Border.all(color: Marca.amarelo, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              impresso ? Icons.print_outlined : Icons.print_disabled_outlined,
              size: 28,
              color: Marca.amarelo,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                if (impresso)
                  _TextoDoDocumento(notinha: notinha)
                else
                  Text(
                    motivo ??
                        'A venda está registrada. Resolva a impressora e '
                            'reimprima — o cliente precisa do papel para pagar '
                            'no caixa.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _Cor.avisoTexto,
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

/// O texto do documento, com o trecho que não pode ser lido por alto.
class _TextoDoDocumento extends StatelessWidget {
  const _TextoDoDocumento({required this.notinha});

  final bool notinha;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _Cor.avisoTexto,
    );
    const destaque = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: Marca.amarelo,
    );

    // A notinha tem lembrete próprio (§16): ali o cliente leva o papel e acerta
    // a pendência depois, então "paga com este papel" seria a instrução errada.
    if (notinha) {
      return const Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Não esqueça de entregar a notinha para o cliente. É com '
                  'ela que ele acerta a pendência depois — ',
            ),
            TextSpan(text: 'não é comprovante de pagamento', style: destaque),
            TextSpan(text: '.'),
          ],
        ),
        style: base,
      );
    }

    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Entregue ao cliente para levar ao caixa. Ele paga com este '
                'papel — ',
          ),
          TextSpan(text: 'não é comprovante de pagamento', style: destaque),
          TextSpan(text: '.'),
        ],
      ),
      style: base,
    );
  }
}

/// Reimprimir o documento 1 (§3.4.3).
///
/// Secundário quando o papel saiu; em destaque quando não saiu — ali é a ação
/// que resolve o balcão. O número da via vem do documento registrado, e não de
/// um contador da tela.
class _BotaoDeReimpressao extends StatelessWidget {
  const _BotaoDeReimpressao({
    required this.via,
    required this.impresso,
    required this.ocupado,
    required this.onPressed,
  });

  final int via;
  final bool impresso;
  final bool ocupado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final rotulo =
        via > 1 ? 'REIMPRIMIR DOCUMENTO ($via)' : 'REIMPRIMIR DOCUMENTO';

    return SizedBox(
      height: 72,
      child: OutlinedButton(
        onPressed: ocupado ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: impresso ? _Cor.cartao : Marca.laranja,
          foregroundColor: impresso ? _Cor.texto : Colors.white,
          disabledForegroundColor:
              (impresso ? _Cor.texto : Colors.white).withValues(alpha: .6),
          side: BorderSide(
            color: impresso ? _Cor.borda : Marca.laranja,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ocupado)
                const SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                const Icon(Icons.print_outlined, size: 26),
              const SizedBox(width: 12),
              Text(
                rotulo,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre o comprovante no visual de papel térmico (mesmos dados do documento
/// que já foi — ou vai ser — impresso).
///
/// Só aparece quando há documento: sem ele não existe o que mostrar, e a tela
/// de comprovante não inventa dado nenhum.
class _BotaoDeComprovante extends StatelessWidget {
  const _BotaoDeComprovante({required this.document, required this.finished});

  final PrintedDocument document;
  final SaleFinished finished;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReceiptPage(
              document: document,
              discountPercentHundredths: finished.discountPercentHundredths,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: _Cor.cartao,
          foregroundColor: _Cor.texto,
          side: const BorderSide(color: _Cor.borda, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.receipt_long_outlined, size: 22),
        label: const Text(
          'VER COMPROVANTE',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: .6),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coluna da direita
// ---------------------------------------------------------------------------

/// Vendedor, pagamento e horário, lado a lado.
class _CartoesDeDados extends StatelessWidget {
  const _CartoesDeDados({required this.sale, this.compacto = false});

  final Sale sale;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final cartoes = [
      ('VENDEDOR', sale.sellerName.toUpperCase()),
      ('PAGAMENTO', sale.paymentMethod.label.toUpperCase()),
      ('HORÁRIO', formatDateTime(sale.occurredAt)),
    ];

    // `IntrinsicHeight` para os três terem a mesma altura sem depender da do
    // pai: a coluna que os contém é alta o quanto o conteúdo pedir, e esticar
    // contra uma altura infinita não é conta que feche.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, dado) in cartoes.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _CartaoDeDado(
                rotulo: dado.$1,
                valor: dado.$2,
                compacto: compacto,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CartaoDeDado extends StatelessWidget {
  const _CartaoDeDado({
    required this.rotulo,
    required this.valor,
    required this.compacto,
  });

  final String rotulo;
  final String valor;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: compacto ? 12 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: _Cor.cartao,
        border: Border.all(color: _Cor.borda),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: _Cor.rotulo,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: TextStyle(
                fontSize: compacto ? 24 : 26,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: _Cor.tinta,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O cliente da venda — ou a ausência dele, dita com todas as letras.
class _CartaoDoCliente extends StatelessWidget {
  const _CartaoDoCliente({
    required this.nome,
    required this.telefone,
    this.compacto = false,
  });

  final String? nome;
  final String? telefone;
  final bool compacto;

  /// Até duas iniciais — é o que cabe no círculo sem virar borrão.
  static String iniciais(String nome) {
    final partes =
        nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.first.toUpperCase();
    return (partes.first.characters.first + partes.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final semCliente = nome == null || nome!.trim().isEmpty;

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: 18, vertical: compacto ? 10 : 12),
      decoration: BoxDecoration(
        color: _Cor.cartao,
        border: Border.all(color: _Cor.borda),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (semCliente)
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _Cor.itemFundo,
                border: Border.all(color: _Cor.borda, width: 2),
              ),
              child: const Icon(
                Icons.person_off_outlined,
                size: 22,
                color: _Cor.rotulo,
              ),
            )
          else
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Marca.azul,
                border: Border.all(color: Marca.amarelo, width: 3),
              ),
              child: Text(
                iniciais(nome!),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Marca.amarelo,
                ),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CLIENTE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: _Cor.rotulo,
                  ),
                ),
                Text(
                  semCliente ? 'Venda sem cliente' : nome!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compacto ? 20 : 23,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: semCliente ? _Cor.rotulo : _Cor.tinta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              telefone?.trim().isNotEmpty ?? false ? telefone!.trim() : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _Cor.rotulo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Os itens da venda, com o desconto e o total a pagar no caixa.
class _PainelDeItens extends StatelessWidget {
  const _PainelDeItens({
    required this.sale,
    required this.percentualDoDesconto,
    this.rolavel = true,
  });

  final Sale sale;
  final int percentualDoDesconto;

  /// Na tela larga a lista tem altura própria e rola dentro do cartão; no
  /// retrato quem rola é o corpo inteiro, e uma rolagem dentro da outra só faz
  /// o dedo mover a lista errada.
  final bool rolavel;

  @override
  Widget build(BuildContext context) {
    final itens = sale.items;
    final linhas = <Widget>[
      for (final item in itens) _LinhaDoItem(item: item),
      if (sale.hasDiscount)
        _LinhaDoDesconto(
          valor: sale.discountAmount,
          percentual: percentualDoDesconto,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _Cor.cartao,
        border: Border.all(color: _Cor.borda),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: rolavel ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _CabecalhoDoPainel(
            quantidade: itens.length,
            subtotal: sale.grossAmount,
          ),
          if (rolavel)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                itemCount: linhas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, indice) => linhas[indice],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                children: [
                  for (final (i, linha) in linhas.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    linha,
                  ],
                ],
              ),
            ),
          _RodapeDoPainel(
            subtotal: sale.grossAmount,
            desconto: sale.discountAmount,
            total: sale.totalAmount,
            pagamento: sale.paymentMethod.label,
          ),
        ],
      ),
    );
  }
}

class _CabecalhoDoPainel extends StatelessWidget {
  const _CabecalhoDoPainel({required this.quantidade, required this.subtotal});

  final int quantidade;
  final Money subtotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Cor.fundo)),
      ),
      child: Row(
        children: [
          const Text(
            'ITENS DA VENDA',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: _Cor.rotulo,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              '${quantidade == 1 ? '1 item' : '$quantidade itens'} · '
              'subtotal ${subtotal.toDisplayString()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _Cor.rotulo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaDoItem extends StatelessWidget {
  const _LinhaDoItem({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    return _LinhaDoPainel(
      fundo: _Cor.itemFundo,
      borda: _Cor.itemBorda,
      corDaEtiqueta: _Cor.categoria(item.categoryCode),
      etiqueta: item.productName.toUpperCase(),
      detalhe: '${item.quantity.toDisplayString()} × '
          '${item.unitPrice.toDisplayString()}',
      corDoDetalhe: _Cor.rotulo,
      valor: item.lineTotal.toDisplayString(),
      corDoValor: _Cor.tinta,
    );
  }
}

/// A linha do desconto, com o critério que o gerou.
class _LinhaDoDesconto extends StatelessWidget {
  const _LinhaDoDesconto({required this.valor, required this.percentual});

  final Money valor;
  final int percentual;

  @override
  Widget build(BuildContext context) {
    return _LinhaDoPainel(
      fundo: _Cor.laranjaFundo,
      borda: _Cor.laranjaBordaFraca,
      corDaEtiqueta: _Cor.laranjaBorda,
      etiqueta: 'DESCONTO',
      detalhe: percentual > 0
          ? '${formatPercentDisplay(percentual)} sobre o subtotal'
          : 'valor fixo',
      corDoDetalhe: _Cor.laranjaRotulo,
      valor: '− ${valor.toDisplayString()}',
      corDoValor: _Cor.laranjaRotulo,
    );
  }
}

class _LinhaDoPainel extends StatelessWidget {
  const _LinhaDoPainel({
    required this.fundo,
    required this.borda,
    required this.corDaEtiqueta,
    required this.etiqueta,
    required this.detalhe,
    required this.corDoDetalhe,
    required this.valor,
    required this.corDoValor,
  });

  final Color fundo;
  final Color borda;
  final Color corDaEtiqueta;
  final String etiqueta;
  final String detalhe;
  final Color corDoDetalhe;
  final String valor;
  final Color corDoValor;

  @override
  Widget build(BuildContext context) {
    final estreito = MediaQuery.sizeOf(context).width < 900;

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: estreito ? 10 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: fundo,
        border: Border.all(color: borda, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            constraints: BoxConstraints(minWidth: estreito ? 76 : 104),
            padding: EdgeInsets.symmetric(
              horizontal: estreito ? 10 : 14,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: corDaEtiqueta,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              etiqueta,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(width: estreito ? 10 : 14),
          Expanded(
            child: Text(
              detalhe,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: corDoDetalhe,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // O valor encolhe antes de sair da linha: número de dinheiro cortado
          // é pior que número menor.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valor,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: corDoValor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O que o cliente vai pagar no caixa — e de onde esse número saiu.
class _RodapeDoPainel extends StatelessWidget {
  const _RodapeDoPainel({
    required this.subtotal,
    required this.desconto,
    required this.total,
    required this.pagamento,
  });

  final Money subtotal;
  final Money desconto;
  final Money total;
  final String pagamento;

  @override
  Widget build(BuildContext context) {
    final apoio = StringBuffer('subtotal ${subtotal.toDisplayString()}');
    if (desconto.isPositive) apoio.write(' − ${desconto.toDisplayString()}');
    apoio.write(' · $pagamento');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: const BoxDecoration(
        color: _Cor.itemFundo,
        border: Border(top: BorderSide(color: _Cor.fundo)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'TOTAL A PAGAR NO CAIXA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: _Cor.rotulo,
                  ),
                ),
                Text(
                  apoio.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _Cor.rotulo,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // `Flexible` antes do `FittedBox`: solto num `Row`, ele recebe
          // largura infinita e não tem contra o que encolher — o total saía
          // pela direita do cartão em vez de diminuir.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                total.toDisplayString(),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: _Cor.tinta,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// As duas saídas da tela.
class _Acoes extends StatelessWidget {
  const _Acoes({
    required this.compacto,
    required this.onInicio,
    required this.onNovaVenda,
  });

  final bool compacto;
  final VoidCallback onInicio;
  final VoidCallback onNovaVenda;

  @override
  Widget build(BuildContext context) {
    final altura = compacto ? 64.0 : 82.0;

    final inicio = SizedBox(
      height: altura,
      child: OutlinedButton.icon(
        onPressed: onInicio,
        icon: const Icon(Icons.home_outlined, size: 26),
        style: OutlinedButton.styleFrom(
          backgroundColor: _Cor.cartao,
          foregroundColor: _Cor.texto,
          side: const BorderSide(color: _Cor.borda, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'INÍCIO',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ),
      ),
    );

    final nova = SizedBox(
      height: altura,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0xFFBD6803), offset: Offset(0, 7)),
          ],
        ),
        child: FilledButton.icon(
          onPressed: onNovaVenda,
          icon: const Icon(Icons.shopping_cart_outlined, size: 30),
          style: FilledButton.styleFrom(
            backgroundColor: Marca.laranja,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'NOVA VENDA',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
              ),
            ),
          ),
        ),
      ),
    );

    // Proporção da referência: a ação que continua o balcão é a maior.
    return Row(
      children: [
        Expanded(flex: 2, child: inicio),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: nova),
      ],
    );
  }
}

/// Espera da reimpressão, por cima da tela inteira.
class _EsperaDaReimpressao extends StatelessWidget {
  const _EsperaDaReimpressao({required this.codigo, required this.total});

  final String codigo;
  final Money total;

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
                'Reimprimindo documento…',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$codigo · ${total.toDisplayString()}',
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
