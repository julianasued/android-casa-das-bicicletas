/// Abertura do terminal com a senha do aparelho (API §2.1).
///
/// A senha é **do terminal**, não do vendedor — quem digita é quem abre o
/// aparelho no começo do turno. A tela deixa isso explícito porque a confusão
/// com credencial pessoal é o caminho mais curto para alguém emprestar a senha.
///
/// O teclado é desenhado na tela em vez de se usar o do sistema: no M10, o
/// teclado do Android cobre metade da área útil e some com o campo que está
/// sendo preenchido. Quem precisar de senha com letra tem o botão de teclado do
/// aparelho no canto do campo — a senha do terminal é cadastrada pelo Dono e
/// nada no contrato obriga que seja numérica.
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
  final _focus = FocusNode();
  bool _submitting = false;
  bool _obscured = true;
  bool _systemKeyboard = false;
  Failure? _failure;

  @override
  void dispose() {
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
        // A senha errada some do campo: repetir a tentativa com o que já
        // falhou é o erro mais comum, e reexibi-la não ajuda ninguém.
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
          const UnauthenticatedFailure('Senha do terminal incorreta.'),
        _ => failure,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                children: [
                  Text(
                    'INSIRA A SENHA DO TERMINAL',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Digite sua senha para acessar o sistema',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  _PasswordField(
                    controller: _passwordController,
                    focusNode: _focus,
                    obscured: _obscured,
                    readOnly: !_systemKeyboard,
                    enabled: !_submitting,
                    onToggleObscured: () =>
                        setState(() => _obscured = !_obscured),
                    onToggleKeyboard: () {
                      setState(() => _systemKeyboard = !_systemKeyboard);
                      if (_systemKeyboard) {
                        _focus.requestFocus();
                      } else {
                        _focus.unfocus();
                      }
                    },
                    onSubmitted: (_) => _open(),
                  ),
                  if (_failure != null) ...[
                    const SizedBox(height: 12),
                    _FailureCard(failure: _failure!),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _NumericKeypad(
                enabled: !_submitting,
                onDigit: _digit,
                onBackspace: _backspace,
                onClear: _clear,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ListenableBuilder(
                listenable: _passwordController,
                builder: (context, _) => FilledButton(
                  onPressed:
                      _submitting || _passwordController.text.isEmpty ? null : _open,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                  ),
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('CONFIRMAR'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo da senha: mostra o que foi digitado sem abrir o teclado do sistema.
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    required this.obscured,
    required this.readOnly,
    required this.enabled,
    required this.onToggleObscured,
    required this.onToggleKeyboard,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscured;
  final bool readOnly;
  final bool enabled;
  final VoidCallback onToggleObscured;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscured,
      readOnly: readOnly,
      enabled: enabled,
      showCursor: true,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.visiblePassword,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 24, letterSpacing: 4),
      decoration: InputDecoration(
        labelText: 'Senha do terminal',
        helperText: 'A senha é do aparelho, não do vendedor.',
        prefixIcon: IconButton(
          tooltip: readOnly ? 'Usar o teclado do aparelho' : 'Usar o teclado da tela',
          onPressed: enabled ? onToggleKeyboard : null,
          icon: Icon(readOnly ? Icons.keyboard_outlined : Icons.dialpad),
        ),
        suffixIcon: IconButton(
          tooltip: obscured ? 'Mostrar senha' : 'Ocultar senha',
          onPressed: enabled ? onToggleObscured : null,
          icon: Icon(obscured ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}

/// Teclado da tela: dígitos, apagar e limpar, com alvo grande.
///
/// Montado em linhas com `Expanded` em vez de `GridView`: a grade constrói os
/// filhos sob demanda e, em tela baixa, simplesmente não criava a última linha
/// — o operador ficaria sem o `0` e sem o apagar, que é o §21 ("sem elementos
/// cortados") quebrado no lugar mais caro.
class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final linha in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Expanded(
              child: Row(
                children: [
                  for (final digito in linha)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _Key(
                          label: digito,
                          onPressed: enabled ? () => onDigit(digito) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _Key(
                      label: 'LIMPAR',
                      compact: true,
                      onPressed: enabled ? onClear : null,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _Key(
                      label: '0',
                      onPressed: enabled ? () => onDigit('0') : null,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _Key(
                      icon: Icons.backspace_outlined,
                      semanticLabel: 'Apagar',
                      onPressed: enabled ? onBackspace : null,
                    ),
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

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    this.semanticLabel,
    this.compact = false,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: icon != null
          ? Icon(icon, size: 26, semanticLabel: semanticLabel)
          : Text(
              label!,
              style: TextStyle(
                fontSize: compact ? 15 : 26,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
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
      margin: EdgeInsets.zero,
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
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
