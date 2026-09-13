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
  código de barras da venda — **desenhado como bitmap**, porque o do SDK não é
  legível neste terminal — e **reimpressão auditável** (§3.4.3).
- **Leitor de código de barras**: canal nativo, modo teclado e localização da
  venda pelo código lido (RF09, sem a confirmação do caixa — Sprint 5).
- **Diagnóstico da impressora**: estado, avanço de papel e página de teste, com
  falta de papel e impressora ausente tratadas como falhas distintas (§11).
- **Pendências do cliente** (RF15): o vendedor consulta o quanto o cliente já
  deve antes de fiar outra vez, com aviso de pendência vencida. A consulta fica
  num botão próprio na escolha do cliente — quem vende à vista não passa por uma
  tela a mais. Registrar o pagamento da pendência é do caixa (RF16), fora deste
  aplicativo.

### O que o M10 físico ensinou

O POC foi executado no aparelho e mudou o código em seis pontos. Nenhum desses
defeitos aparecia em emulador ou em teste automatizado, e todos quebrariam a
venda no balcão:

| Defeito | O que acontecia |
| ------- | --------------- |
| `checkElgin` reprovava retorno positivo | **nenhuma notinha** era dada como impressa |
| `CONEXAO_ATIVA` (-6) tratada como falha | impressora sumia depois de trocar de tela |
| CODE 128 sem o seletor `{B` | código de barras nunca saía |
| ZXing ausente do APK | códigos e QR morriam em tempo de execução |
| QR Code com nível de correção 0 | **nenhum QR** jamais saiu |
| Código de barras com 7,5 mm de altura | saía desenhado e nenhum leitor decodificava |

Duas respostas que só o aparelho podia dar, e que estão fora da documentação
pública da Elgin: a impressora conecta com `AbreConexaoImpressora(6, "M8")`, e
`StatusImpressora` só responde no assunto do papel — `5` dá para imprimir, `7`
não, sendo **tampa aberta e falta de papel indistinguíveis** entre si. O aviso
ao operador tem de cobrir os dois casos.

Sem solução, com causa registrada: o M10 **não tem sinal sonoro**
(`SinalSonoro` responde -401, função não suportada) e o **display do cliente de
2,4" não abre** — o `bindService` no serviço do terminal falha, o que aponta
para o `net.nyx.printerservice` não existir neste aparelho. O display não
bloqueia a venda. **Atenção:** a tentativa de contornar isso pelo caminho iMin
desligou o terminal, e está documentada como não repetir.

O roteiro completo, com os números medidos e o que ficou em aberto, está em
[`checklist_teste_m10.md`](docs/checklist_teste_m10.md).

## Sprint 9 — Offline, Fase 1: cache de leitura

Banco local (RF34) guardando catálogo, categorias e clientes. Quando a rede
falha, a consulta responde o que está no cache em vez de uma tela de erro —
§13.9 põe consulta de produto e de cliente entre as operações que devem
funcionar offline.

Três decisões que o código documenta:

- **o cache se enche do que a busca online já devolveu**, e não de uma rota de
  sincronização: o `GET /sync/pull/` não tem payload especificado na API, e a
  própria especificação lista a paginação dele como pendência. Aproveitar as
  buscas que o vendedor faz enche o cache sem inventar contrato — e no balcão o
  que se consulta é o que se vende;
- **só falha de rede cai para o cache.** Erro do servidor (`403`, `422`) é
  resposta legítima e sobe para quem chamou; disfarçá-la de sucesso esconderia
  problema de permissão ou de contrato;
- **sem rede e sem cache continua sendo falha**, não lista vazia. Dizer "nenhum
  produto" quando não se sabe faria o vendedor procurar no estoque um item que
  existe.

## Sprint 9 — Offline, Fase 2: a venda acontece sem rede

Sem internet, a venda vai para uma fila local (RF35) e o documento 1 é montado
no próprio terminal. O cliente leva o papel ao caixa como sempre.

**O documento provisório é honesto sobre o que não sabe.** Três campos são do
servidor por definição: o `id` da venda, a `reference` (`DOC1-L1-...`, exigida na
devolução — 13.4) e a `sequence` da via. No lugar da referência sai
`AGUARDANDO SINCRONIZACAO`, e o aviso do papel diz que o número definitivo vem
na reimpressão. Gerar uma referência local que depois divergisse deixaria o papel
do cliente apontando para um documento que não existe.

**O código de barras, sim, vale desde já** — é calculado do `uuid` do terminal
pela mesma regra do backend, e é o que o caixa lê para achar a venda (RF09).

Cuidados que os testes prendem:

- **só falha de rede vira fila.** Recusa do servidor — desconto acima do teto,
  produto inativo — é resposta legítima que o vendedor pode corrigir;
  enfileirá-la faria a venda "dar certo" no balcão para ser recusada a cada
  sincronização;
- **a fila recebe antes de o papel sair**, mesma ordem do caminho online: um
  documento impresso de uma venda que não ficou registrada em lugar nenhum é o
  pior desfecho possível;
- **sem o mínimo para o cupom, a falha de rede segue seu caminho.** Melhor o
  vendedor saber que não deu do que receber um papel que não identifica a loja;
- **a venda local nasce `AGUARDANDO_CAIXA`**, não em limbo:
  `PENDENTE_SINCRONIZACAO` é estado da operação na fila, não da venda.

A identidade do terminal (nome, CNPJ e endereço da loja, nome do terminal) é
**aprendida**, não configurada: vem dentro do documento que o servidor já mandou
— o único lugar que traz o nome do terminal — e de `GET /stores/{id}/`.

## Sprint 9 — Offline, Fase 3: a fila sobe quando a rede volta

`POST /sync/push/` em lote, disparado pela volta da conexão (§13.10). O gatilho é
o `ConnectivityChannel`, que existia desde a Sprint 4 esperando por isto.

**O gatilho é a subida, não a mudança.** A conexão de um terminal no balcão
oscila, e avisar a cada notificação faria o aplicativo tentar sincronizar quando
a rede acabou de cair. Há também uma tentativa periódica, porque falha de
servidor não muda o estado da conexão: sem ela, uma venda recusada por um `500`
esperaria a próxima oscilação de rede, o que pode não acontecer no mesmo dia.

Cada desfecho decide o destino de uma venda que já aconteceu, e é aí que os
testes apertam:

- **um desfecho não arrasta os outros.** O §3.9 é explícito — operação recusada
  não interrompe o lote. Uma venda entra enquanto a seguinte conflita;
- **operação sobre a qual o servidor não falou fica como falha**, nunca como
  sincronizada: supor que foi aceita perderia a venda, e voltar na próxima rodada
  é seguro porque a idempotência (RF36) impede duplicata;
- **falha do lote inteiro não marca ninguém.** Rede caindo no meio do envio não é
  problema das operações, e marcá-las infl aria a contagem de tentativas;
- **uma sincronização por vez.** O gatilho é evento de rede, que dispara duas
  vezes quando o sinal oscila; dois envios do mesmo lote embaralhariam a
  contagem de tentativas;
- **status desconhecido vira erro**, não sucesso — mesma razão de sempre.

Falta da Sprint 9: a tela dos conflitos (13.11), para o operador ver o que está
pendente e o gerente decidir, e a auditoria offline (RF37).

Fora do escopo deste repositório: caixa e documento 2 (Sprint 5) e comissão
(Sprint 6), que são do projeto web. Os pontos de extensão dessas sprints já estão previstos — o
`SaleDraft` é o objeto que a fila local vai gravar, e `ConnectivityChannel` é o
sinal que vai disparar a sincronização.

## Stack

- Flutter/Dart (§7.1 da especificação)
- Kotlin para os canais nativos do M10 Pro
- Comunicação exclusiva via API REST sobre HTTPS
- SQLite local para operação offline-first — **Sprint 9**

### Uma dependência de terceiros, e o motivo

A regra do projeto é não declarar pacote algum além do SDK do Flutter. Rede
(`dart:io`), JSON (`dart:convert`), estado de tela (`ChangeNotifier`) e
identificadores (UUID v4 em `core/uuid.dart`) já vêm no SDK; armazenamento
seguro, conectividade e identificação do aparelho são canais nativos que este
projeto precisaria escrever de qualquer maneira, porque a impressora e o leitor
do M10 já exigem código Kotlin. Cada pacote a menos é uma atualização a menos
para empurrar a um terminal que fica meses no balcão sem ninguém mexer.

**A exceção é `barcode`, e ela existe porque o SDK da Elgin não desenha código
de barras legível neste terminal.** No M10 quem dimensiona as barras é o serviço
NYX, e o `ImpressaoCodigoBarras` devolve sucesso enquanto produz um código que
nenhum leitor decodifica — conferido no aparelho, onde o código de venda saía
ilegível pelo SDK e legível desenhado por nós, na mesma tirada de papel. O
pacote entra apenas para **codificar** o CODE 128; a rasterização é feita com o
`dart:ui` do próprio Flutter, e não com o pacote `image`, que traria peso que
não se justifica para desenhar retângulos. Ver `platform/printer/barcode_bitmap.dart`
e o §Impressão de [`checklist_teste_m10.md`](docs/checklist_teste_m10.md).

Se um dia a política precisar valer sem exceção, o caminho é escrever o encoder
CODE 128 à mão — são as tabelas de 107 símbolos mais o checksum — e conferir a
saída contra os cupons que já foram validados no M10.

O `sqflite` entrou com a Fase 1 da Sprint 9, como o planejamento previa (RF34),
junto com `path` para montar o caminho do arquivo e `sqflite_common_ffi` apenas
em `dev_dependencies` — é ele que permite rodar os testes do banco contra SQLite
de verdade, em memória, em vez de um dublê que responderia o que o teste
mandasse.

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
