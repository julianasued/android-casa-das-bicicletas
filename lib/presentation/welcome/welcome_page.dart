/// Tela inicial do terminal, antes de qualquer identificação.
///
/// É o estado em que o M10 passa a maior parte do dia: ligado no balcão, sem
/// ninguém autenticado, esperando a próxima venda. Por isso ela tem uma ação só
/// e ocupa a largura inteira — quem chega está em pé, com o cliente na frente,
/// e não deve precisar procurar onde tocar.
///
/// A identificação do aparelho fica visível de propósito. Com dois terminais
/// iguais no balcão, saber em qual se está evita venda lançada na loja errada.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.deps.session;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Configuração do terminal',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.setup),
                ),
              ),
              Expanded(
                child: Center(
                  // Rolagem porque o M10 é de 5": com a fonte do sistema
                  // ampliada nas configurações de acessibilidade, o conjunto
                  // logo + identificação não cabe mais na vertical.
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pedal_bike,
                          size: 96,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'CASA DAS BICICLETAS',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _TerminalIdentity(
                          storeCode: session.storeCode,
                          storeId: session.storeId,
                          deviceId: session.deviceId,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.terminalLogin),
                icon: const Icon(Icons.point_of_sale, size: 28),
                label: const Text('INICIAR VENDA'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                  textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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

/// Qual aparelho é este, em uma linha.
class _TerminalIdentity extends StatelessWidget {
  const _TerminalIdentity({
    required this.storeCode,
    required this.storeId,
    required this.deviceId,
  });

  final String? storeCode;
  final int? storeId;
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `storeCode` só existe depois da primeira resposta do servidor; antes
    // disso o id numérico é o que há, e é melhor que deixar em branco.
    final loja = storeCode ?? (storeId == null ? null : 'Loja $storeId');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TERMINAL',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            deviceId ?? 'não identificado',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (loja != null) ...[
            const SizedBox(height: 2),
            Text(loja, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
