/// Ponto de entrada do aplicativo do terminal.
///
/// Monta o grafo de dependências uma vez — canais nativos, cliente HTTP,
/// repositórios — e entrega para a árvore de widgets. A restauração da sessão
/// acontece na primeira tela (`BootstrapPage`), e não aqui, para que o
/// aplicativo abra imediatamente em vez de ficar em tela preta esperando o
/// armazenamento seguro responder.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Quiosque: o M10 é um terminal de balcão, não um celular. Sem as barras do
  // Android à vista, o operador não sai do aplicativo sem querer e a tela
  // inteira fica para a venda.
  //
  // `immersiveSticky` esconde as duas barras e as devolve por alguns segundos
  // quando alguém desliza da borda — é o quanto o Flutter alcança sozinho.
  // Travar de vez o aparelho num aplicativo só é configuração do Android
  // (lock task / device owner), fora do alcance daqui.
  //
  // As telas continuam somando `MediaQuery.padding` no que desenham junto às
  // bordas: aqui isso vira zero, e nos aparelhos onde as barras aparecem a
  // conta continua certa.
  unawaited(
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
  );

  runApp(
    CasaDasBicicletasApp(dependencies: AppDependencies.production()),
  );
}
