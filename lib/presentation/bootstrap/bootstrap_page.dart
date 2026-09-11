/// Primeira tela: decide onde o terminal continua de onde parou.
///
/// O M10 fica ligado no balcão o dia inteiro e é reiniciado sem aviso. Nada
/// disso pode custar uma nova digitação da senha do terminal: o que estava
/// válido no armazenamento seguro é restaurado, e só o que venceu manda o
/// operador de volta para trás.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../shared/feedback.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    final deps = context.deps;

    await deps.session.restore();
    await deps.connectivity.start();

    // Depois do `start`, para o agendador já nascer sabendo se há rede. O
    // terminal pode ter sido reiniciado depois de um dia inteiro sem conexão, e
    // aí há fila esperando desde antes de o aplicativo abrir (§13.10).
    deps.syncScheduler?.start();

    if (!mounted) return;

    final session = deps.session;
    final route = switch (session) {
      _ when !session.isConfigured => AppRoutes.setup,
      _ when !session.hasTerminalAuth => AppRoutes.terminalLogin,
      _ when !session.hasSellerSession => AppRoutes.sellerSelection,
      _ => AppRoutes.home,
    };

    await Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: LoadingView(label: 'Abrindo o terminal...'),
    );
  }
}
