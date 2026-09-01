import 'package:flutter/material.dart';

void main() {
  runApp(const CasaDasBicicletasApp());
}

/// Raiz do aplicativo. As telas reais entram em `lib/presentation`
/// conforme as sprints definidas na documentação.
class CasaDasBicicletasApp extends StatelessWidget {
  const CasaDasBicicletasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Casa das Bicicletas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
        useMaterial3: true,
      ),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Casa das Bicicletas')),
      body: const Center(
        child: Text('Projeto criado. Nenhuma tela implementada ainda.'),
      ),
    );
  }
}
