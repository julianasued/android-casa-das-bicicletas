/// Ponto de entrada do aplicativo do terminal.
///
/// Monta o grafo de dependências uma vez — canais nativos, cliente HTTP,
/// repositórios — e entrega para a árvore de widgets. A restauração da sessão
/// acontece na primeira tela (`BootstrapPage`), e não aqui, para que o
/// aplicativo abra imediatamente em vez de ficar em tela preta esperando o
/// armazenamento seguro responder.
library;

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    CasaDasBicicletasApp(dependencies: AppDependencies.production()),
  );
}
