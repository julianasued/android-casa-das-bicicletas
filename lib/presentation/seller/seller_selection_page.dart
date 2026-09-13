/// Seleção do vendedor no terminal (API §2.3).
///
/// Sem senha, por decisão de negócio (§12 da integração com o M10): a seleção
/// diz quem responde pela venda (RF06), e não concede permissão administrativa
/// nenhuma. O que a tela precisa garantir é que a escolha seja consciente — daí
/// os nomes grandes e a lista sem outro elemento competindo por atenção.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/seller.dart';
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

  @override
  void initState() {
    super.initState();
    _sellers = widget.sellers;
    if (_sellers == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
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

  Future<void> _select(Seller seller) async {
    final deps = context.deps;
    final navigator = Navigator.of(context);

    setState(() => _selecting = seller.id);
    final result = await deps.selectSeller(seller.id);

    if (!mounted) return;
    setState(() => _selecting = null);

    switch (result) {
      case Ok():
        // A loja é buscada agora porque o código dela (`L1`) entra no código de
        // barras da venda e no cabeçalho do documento. Falhar aqui não impede
        // de vender: o servidor devolve o documento pronto de qualquer jeito.
        await deps.auth.currentStore();
        if (!mounted) return;
        // Direto para a venda (§5 e §19): o vendedor selecionou o nome para
        // vender, não para escolher no menu o que fazer em seguida. As
        // ferramentas seguem alcançáveis pelo menu do cabeçalho da venda.
        await navigator.pushNamedAndRemoveUntil(AppRoutes.newSale, (_) => false);
      case Err(:final failure):
        if (failure is UnauthenticatedFailure) {
          await navigator.pushNamedAndRemoveUntil(
            AppRoutes.welcome,
            (_) => false,
          );
          return;
        }
        showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendedor'),
        actions: [
          IconButton(
            tooltip: 'Fechar terminal',
            onPressed: _closeTerminal,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView(label: 'Carregando vendedores...');
    if (_failure != null) return FailureView(failure: _failure!, onRetry: _load);

    final sellers = _sellers ?? const <Seller>[];
    if (sellers.isEmpty) {
      return const EmptyView(
        icon: Icons.person_off,
        message: 'Nenhum vendedor habilitado neste terminal.\n'
            'O cadastro é feito pelo dono ou gerente.',
      );
    }

    return Column(
      children: [
        const _Instrucao(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: sellers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final seller = sellers[index];

              return _SellerButton(
                name: seller.name,
                initials: _initials(seller.name),
                busy: _selecting == seller.id,
                // Um toque de cada vez: dois vendedores selecionados em
                // sequência trocariam a sessão no meio da chamada anterior.
                onTap: _selecting == null ? () => _select(seller) : null,
              );
            },
          ),
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Título e instrução da tela (§5 do fluxo).
class _Instrucao extends StatelessWidget {
  const _Instrucao();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        children: [
          Text(
            'SELECIONE O VENDEDOR',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Toque no nome do vendedor para continuar',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cada vendedor é um botão inteiro, não uma linha de lista.
///
/// A altura de 80 é o que separa "escolher" de "errar": a lista fica ao alcance
/// do polegar de quem segura o M10 com uma mão só, e uma venda lançada no nome
/// errado é discussão de comissão no fim do mês (RF17–RF20).
class _SellerButton extends StatelessWidget {
  const _SellerButton({
    required this.name,
    required this.initials,
    required this.busy,
    required this.onTap,
  });

  final String name;
  final String initials;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(80),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.chevron_right, size: 28),
        ],
      ),
    );
  }
}
