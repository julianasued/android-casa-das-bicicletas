/// Como o aplicativo conta ao operador que algo deu errado.
///
/// Uma falha do domínio (`Failure`) já chega com texto em português e sem
/// jargão. O que estes utilitários acrescentam é a diferença de tratamento: o
/// que é passageiro vira aviso na base da tela, o que impede de continuar
/// ocupa a tela inteira e oferece "tentar de novo".
library;

import 'package:flutter/material.dart';

import '../../core/failure.dart';

/// Aviso rápido — a operação falhou, mas a tela continua utilizável.
void showFailure(BuildContext context, Failure failure) {
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: scheme.error,
        duration: const Duration(seconds: 5),
      ),
    );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Estado de erro que ocupa a tela: nada a mostrar até resolver.
class FailureView extends StatelessWidget {
  const FailureView({required this.failure, this.onRetry, super.key});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(failure), size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_hint(failure) case final String hint) ...[
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(Failure failure) => switch (failure) {
        NetworkFailure() => Icons.wifi_off,
        UnauthenticatedFailure() => Icons.lock_outline,
        PermissionFailure() => Icons.block,
        NotFoundFailure() => Icons.search_off,
        OutOfPaperFailure() => Icons.receipt_long,
        PrinterUnavailableFailure() || PrintFailure() => Icons.print_disabled,
        ScannerFailure() => Icons.qr_code_scanner,
        ConfigurationFailure() => Icons.settings,
        _ => Icons.error_outline,
      };

  /// O que fazer a seguir, quando existe uma ação óbvia.
  String? _hint(Failure failure) => switch (failure) {
        NetworkFailure() =>
          'Confira a rede do terminal. Nada foi enviado ao servidor.',
        OutOfPaperFailure() =>
          'A venda continua registrada: reponha o papel e use a reimpressão.',
        UnauthenticatedFailure() =>
          'Abra o terminal novamente com a senha do aparelho.',
        _ => null,
      };
}

/// Espera padrão — mesmo indicador em toda tela, para o operador reconhecer.
class LoadingView extends StatelessWidget {
  const LoadingView({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Lista vazia com explicação — melhor que uma área em branco.
class EmptyView extends StatelessWidget {
  const EmptyView({required this.message, this.icon = Icons.inbox, super.key});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    // Rolável porque nem sempre a área é alta: na Nova Venda esta vista ocupa
    // a metade de cima da tela, e com mensagem de duas linhas o conteúdo
    // passava do espaço — no M10 isso vira a faixa listrada de overflow.
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
