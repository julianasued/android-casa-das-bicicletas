# Casa das Bicicletas — Aplicativo M10 Pro

Aplicativo Flutter/Android do Sistema de Gestão de Vendas e Caixa, destinado aos
terminais **Elgin M10 Pro** das duas lojas.

A especificação completa está em [`docs/`](docs/):

| Documento | Conteúdo |
|---|---|
| `especificacao_sistema_vendas_v2.md` | Levantamento, requisitos, arquitetura e planejamento |
| `especificacao-api/especificacao_api_v1.md` | Contrato da API REST (Django) |
| `modelagem-banco/modelo_de_dados_v1.md` | Modelo de dados |
| `integração-com-Elgin-M10-Pro.md` | Impressora térmica e leitor de código de barras |
| `Arquitetura do Aplicativo Android-selection.png` | Camadas do aplicativo |

## Estado atual

Scaffold mínimo: o projeto compila e abre uma tela de espaço reservado. As pastas
de arquitetura existem, mas ainda estão vazias.

## Stack

- Flutter/Dart (§7.1 da especificação)
- SQLite local para operação offline-first
- Kotlin apenas para os canais nativos do M10 Pro (impressora e leitor)
- Comunicação exclusiva via API REST sobre HTTPS

## Estrutura

```text
lib/
  main.dart        ponto de entrada
  app/             bootstrap, rotas e tema
  core/            erros, resultado, formatação, injeção de dependências, ambiente
  domain/          entidades, casos de uso e regras locais
  data/            repositórios, fontes local (SQLite) e remota (REST), fila de sync
  presentation/    telas e estado de tela
  platform/        canais nativos: impressora, leitor, conectividade, sessão segura
test/              testes automatizados
android/           projeto Android host (Gradle + MainActivity)
```

A regra de dependência é a do diagrama de arquitetura: as dependências apontam
sempre para dentro — trocar SQLite, cliente HTTP ou SDK do terminal não afeta
domínio nem interface.

## Pré-requisitos

- Flutter SDK 3.24 ou superior (Dart 3.5+)
- Android SDK com plataforma de compilação recente
- JDK 17

Nenhum deles está instalado na máquina onde o projeto foi criado.

## Primeira execução

```bash
flutter pub get
flutter run
```

O arquivo `android/local.properties` e o Gradle Wrapper (`gradlew`,
`gradle-wrapper.jar`) não estão versionados — o Flutter os gera na primeira
execução de `flutter run` ou `flutter build apk`.

## Verificações

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

## Padrão de commits

`feat:`, `fix:`, `refactor:`, `test:`, `docs:` (§10.3 da especificação).
