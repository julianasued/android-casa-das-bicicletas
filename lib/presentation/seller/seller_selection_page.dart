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
        await navigator.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
      case Err(:final failure):
        if (failure is UnauthenticatedFailure) {
          await navigator.pushNamedAndRemoveUntil(
            AppRoutes.terminalLogin,
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
        title: const Text('Quem vai vender?'),
        actions: [
          IconButton(
            tooltip: 'Fechar terminal',
            onPressed: _closeTerminal,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _body(),
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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sellers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final seller = sellers[index];
        final busy = _selecting == seller.id;

        return ListTile(
          leading: CircleAvatar(child: Text(_initials(seller.name))),
          title: Text(seller.name),
          trailing: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _selecting == null ? () => _select(seller) : null,
        );
      },
    );
  }

  Future<void> _closeTerminal() async {
    final navigator = Navigator.of(context);
    await context.deps.auth.logout();
    if (!mounted) return;
    await navigator.pushNamedAndRemoveUntil(AppRoutes.terminalLogin, (_) => false);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
