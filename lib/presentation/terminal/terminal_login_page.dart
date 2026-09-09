/// Abertura do terminal com a senha do aparelho (API §2.1).
///
/// A senha é **do terminal**, não do vendedor — quem digita é quem abre o
/// aparelho no começo do turno. A tela deixa isso explícito porque a confusão
/// com credencial pessoal é o caminho mais curto para alguém emprestar a senha.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/seller.dart';

class TerminalLoginPage extends StatefulWidget {
  const TerminalLoginPage({super.key});

  @override
  State<TerminalLoginPage> createState() => _TerminalLoginPageState();
}

class _TerminalLoginPageState extends State<TerminalLoginPage> {
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscured = true;
  Failure? _failure;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final deps = context.deps;
    final navigator = Navigator.of(context);
    final storeId = deps.session.storeId;

    if (storeId == null) {
      await navigator.pushNamedAndRemoveUntil(AppRoutes.setup, (_) => false);
      return;
    }

    setState(() {
      _submitting = true;
      _failure = null;
    });

    final result = await deps.openTerminal(
      storeId: storeId,
      terminalPassword: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case Ok(value: final List<Seller> sellers):
        _passwordController.clear();
        await navigator.pushNamedAndRemoveUntil(
          AppRoutes.sellerSelection,
          (_) => false,
          arguments: sellers,
        );
      case Err(:final failure):
        setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.deps.session;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Abrir terminal'),
        actions: [
          IconButton(
            tooltip: 'Configuração',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.setup),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.point_of_sale,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'Casa das Bicicletas',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'Loja ${session.storeId} · ${session.deviceId ?? ''}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: _obscured,
            enabled: !_submitting,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            onSubmitted: (_) => _open(),
            decoration: InputDecoration(
              labelText: 'Senha do terminal',
              helperText: 'A senha é do aparelho, não do vendedor.',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _open,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Abrir terminal'),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 24),
            _FailureCard(failure: _failure!),
          ],
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                failure.message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
