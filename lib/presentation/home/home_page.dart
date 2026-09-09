/// Tela inicial do terminal com o vendedor já selecionado.
///
/// O que a Sprint 4 entrega está aqui: montar e finalizar a venda com impressão
/// do documento 1 (RF06–RF08), validar o leitor integrado (RF09) e diagnosticar
/// a impressora (§4 e §11 da integração). Caixa, notinha e sincronização são
/// das sprints seguintes, e o menu não promete o que ainda não existe.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../shared/terminal_bar.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Casa das Bicicletas'),
        actions: [
          IconButton(
            tooltip: 'Fechar terminal',
            icon: const Icon(Icons.logout),
            onPressed: () => _closeTerminal(context),
          ),
        ],
      ),
      body: Column(
        children: [
          TerminalBar(
            session: deps.session,
            connectivity: deps.connectivity,
            onChangeSeller: () => _changeSeller(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ActionCard(
                  icon: Icons.add_shopping_cart,
                  title: 'Nova venda',
                  subtitle: 'Monta a venda e imprime o encaminhamento ao caixa',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.newSale),
                ),
                _ActionCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Leitor de código',
                  subtitle: 'Localiza a venda pelo código do documento',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.scanner),
                ),
                _ActionCard(
                  icon: Icons.print,
                  title: 'Impressora',
                  subtitle: 'Estado, avanço de papel e impressão de teste',
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.printerDiagnostics),
                ),
                _ActionCard(
                  icon: Icons.memory,
                  title: 'Teste Elgin M10',
                  subtitle: 'Prova de integração com impressora, leitor e display',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.m10Poc),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeSeller(BuildContext context) async {
    final deps = context.deps;
    final navigator = Navigator.of(context);

    await deps.session.clearSession();
    await navigator.pushNamedAndRemoveUntil(AppRoutes.sellerSelection, (_) => false);
  }

  Future<void> _closeTerminal(BuildContext context) async {
    final deps = context.deps;
    final navigator = Navigator.of(context);

    await deps.auth.logout();
    await navigator.pushNamedAndRemoveUntil(AppRoutes.terminalLogin, (_) => false);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        leading: Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
