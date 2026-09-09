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
| `05-fluxo-offline/` | Fila local, idempotência e resolução de conflitos |
| `checklist_teste_m10.md` | Roteiro do teste do POC no M10 físico |
| `Arquitetura do Aplicativo Android-selection.png` | Camadas do aplicativo |

## Estado atual — Sprint 4 (Aplicativo M10)

Entregue nesta sprint (§8 da especificação: *aplicativo Android; integração com
M10; leitor; impressora; impressão do primeiro documento*):

- **Estrutura do aplicativo** nas quatro camadas do diagrama de arquitetura:
  apresentação, domínio, dados e plataforma, com a regra de dependência
  apontando para dentro.
- **Abertura do terminal** (`POST /auth/terminal/`) e **seleção do vendedor**
  (`POST /auth/select-seller/`), com token guardado em armazenamento cifrado do
  aparelho.
- **Montagem da venda**: busca no catálogo da loja, carrinho, desconto com o
  teto de 5% (13.3), forma de pagamento e cliente — obrigatório na notinha
  (RF14).
- **Finalização da venda** (`POST /sales/`) com identificador gerado no
  terminal e idempotência por esse mesmo identificador (RF36).
- **Impressão do documento 1** (RF08) na impressora térmica integrada, com
  código de barras da venda, e **reimpressão auditável** (§3.4.3).
- **Leitor de código de barras**: canal nativo, modo teclado e localização da
  venda pelo código lido (RF09, sem a confirmação do caixa — Sprint 5).
- **Diagnóstico da impressora**: estado, avanço de papel e página de teste, com
  falta de papel e impressora ausente tratadas como falhas distintas (§11).

Fora do escopo desta sprint, conforme o planejamento: caixa e documento 2
(Sprint 5), notinhas e pendências (Sprint 7) e a fila local de sincronização
(Sprint 9). Os pontos de extensão dessas sprints já estão previstos — o
`SaleDraft` é o objeto que a fila local vai gravar, e `ConnectivityChannel` é o
sinal que vai disparar a sincronização.

## Stack

- Flutter/Dart (§7.1 da especificação)
- Kotlin para os canais nativos do M10 Pro
- Comunicação exclusiva via API REST sobre HTTPS
- SQLite local para operação offline-first — **Sprint 9**

### Sem dependências de terceiros

O `pubspec.yaml` não declara pacote algum além do SDK do Flutter. Rede
(`dart:io`), JSON (`dart:convert`), estado de tela (`ChangeNotifier`) e
identificadores (UUID v4 em `core/uuid.dart`) já vêm no SDK; armazenamento
seguro, conectividade e identificação do aparelho são canais nativos que este
projeto precisaria escrever de qualquer maneira, porque a impressora e o leitor
do M10 já exigem código Kotlin. Cada pacote a menos é uma atualização a menos
para empurrar a um terminal que fica meses no balcão sem ninguém mexer.

A Sprint 9 acrescentará `sqflite` para o banco local (RF34).

## Estrutura

```text
lib/
  main.dart        ponto de entrada
  app/             bootstrap, rotas, tema e injeção de dependências
  core/            dinheiro, quantidade, resultado, falhas, formatação, ambiente
  domain/          entidades, regras da venda, portas e casos de uso
  data/            cliente REST, mapeadores, repositórios e sessão do terminal
  presentation/    telas e estado de tela
  platform/        canais nativos: impressora, leitor, sessão segura, rede
test/              testes automatizados
android/           projeto Android host, canais em Kotlin e SDK da impressora
```

### Dinheiro e quantidade

Valores monetários são **centavos inteiros** (`core/money.dart`) e quantidades
são **milésimos inteiros** (`core/quantity.dart`). Nada de `double`: o
arredondamento é o mesmo do backend (meia unidade para cima, fechando em
centavos a cada etapa), e é isso que faz o total impresso no papel bater com o
total gravado no Postgres, inclusive no rateio do desconto entre as linhas.

### POC de integração com o M10

A tela **Teste Elgin M10** (rota `/m10`, atalho no menu do terminal) é uma prova
de hardware isolada do fluxo de venda: um botão por função, sem cliente, sem
produto e sem servidor. Existe para responder no aparelho o que a documentação
da Elgin deixa em aberto — o roteiro está em
[`docs/checklist_teste_m10.md`](docs/checklist_teste_m10.md).

O que a documentação oficial confirma e o que não confirma:

| Assunto | Situação |
|---|---|
| Impressora térmica | API confirmada: `com.elgin.e1.Impressora.Termica`, conexão embarcada tipo `5`, `ImpressaoTexto`, `ImpressaoCodigoBarras`, `ImpressaoQRCode`, `ImprimeImagem`, `AvancaPapel`, `Corte`, `StatusImpressora` |
| Retorno de `StatusImpressora` | **Não publicado.** O POC mostra o valor cru para o mapeamento ser feito no aparelho |
| Inicialização | **Ambígua**: o exemplo oficial usa `setContext`, a lista de funções cita `setActivity`. Os dois são tentados |
| Scanner | **Sem API para o M10.** A Elgin documenta scanner apenas para o SmartPOS (`com.elgin.e1.Scanner.Scanner`). As ações de broadcast usadas aqui são candidatas, trocáveis em tempo de execução |
| Display do cliente | **Sem API publicada.** Existe a porta `CustomerDisplay` e um levantamento de telas secundárias via `DisplayManager`; escrever no display ainda não é possível |

### Integração com o M10 Pro

Os canais nativos ficam em
`android/app/src/main/kotlin/br/com/casadasbicicletas/vendas/platform/`:

| Canal | Responsabilidade |
|---|---|
| `PrinterChannel` | Impressora térmica integrada, fora da thread principal |
| `ScannerChannel` | Leitor integrado, por broadcast do serviço de scanner |
| `CustomerDisplayChannel` | Display do cliente — levantamento apenas, API pendente |
| `SecureStoreChannel` | Token do terminal em `EncryptedSharedPreferences` |
| `ConnectivityChannel` | Rede com saída validada, não apenas "tem Wi-Fi" |
| `DeviceChannel` | Modelo e `ANDROID_ID`, sugestão de `X-Device-Id` |

Os **SDKs da Elgin** (`.aar`) não são versionados — são binários proprietários
distribuídos com o terminal. Veja [`android/app/libs/README.md`](android/app/libs/README.md)
para os nomes exatos dos arquivos e como instalá-los. Sem ele o projeto compila e roda normalmente; a impressora
responde `PRINTER_UNAVAILABLE`, que é o caso previsto no §11 da especificação de
integração.

O leitor opera em dois modos em campo — broadcast e emulação de teclado — e o
aplicativo aceita os dois: o primeiro pelo canal nativo, o segundo por
`platform/scanner/keyboard_wedge.dart`.

## Pré-requisitos

- Flutter SDK 3.24 ou superior (Dart 3.5+)
- Android SDK com plataforma de compilação recente
- JDK 17

## Primeira execução

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.dominio.com.br/api/v1/
```

Apontando para o Django local, o HTTPS pode ser dispensado explicitamente na
compilação (a RNF01 continua valendo em produção):

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1/ \
  --dart-define=ALLOW_INSECURE_HTTP=true
```

O arquivo `android/local.properties` e o Gradle Wrapper (`gradlew`,
`gradle-wrapper.jar`) não estão versionados — o Flutter os gera na primeira
execução de `flutter run` ou `flutter build apk`.

### Configuração do terminal

Na primeira abertura o aplicativo pede três informações, gravadas cifradas no
aparelho: endereço da API, id da loja e o identificador do terminal
(`X-Device-Id`). O identificador precisa ser **exatamente** o
`device_identifier` cadastrado em `POST /terminals/` no backend; o `ANDROID_ID`
aparece só como sugestão.

## Verificações

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

## Padrão de commits

`feat:`, `fix:`, `refactor:`, `test:`, `docs:` (§10.3 da especificação).
