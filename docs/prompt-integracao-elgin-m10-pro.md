# Prompt: integração do SDK Elgin E1 v02.34.04 em app Flutter para Mini PDV M10 Pro

> Cole o conteúdo abaixo (a partir de "## Contexto") no seu assistente de código,
> com o projeto Flutter aberto e o zip já extraído em `android/app/libs/`.

---

## Contexto

Estou desenvolvendo um aplicativo Flutter que roda no **Elgin Mini PDV M10 Pro** (Android 11, ARM). Preciso integrar três periféricos internos do equipamento através do SDK nativo da Elgin, chamado **E1**, distribuído como AARs.

O SDK é **Android-only** e **Java**. Não existe plugin oficial Flutter. Preciso escrever a ponte eu mesmo.

### Bibliotecas já colocadas em `android/app/libs/`

Extraí o pacote oficial `e1_v02.34.04.zip` da Elgin. Use apenas estes dois arquivos:

| Arquivo | Função |
|---|---|
| `e1-V02.34.04-release.aar` | Biblioteca principal: impressora, display, scanner, balança |
| `minipdvm8-v01.00.00-release.aar` | Camada de comunicação obrigatória para Mini PDV M8/M10 |

**Não** inclua os demais arquivos do zip, a menos que eu peça depois:

- `satelgin-8.1.1-release.aar` — só para SAT fiscal
- `InterfaceAutomacao-v2.0.0.12.aar` — só para TEF / ElginPay
- `cloudpossdk-s-1.0.2.aar` — linha PosGo/SmartPOS, não serve para o M10
- `scanner-v1.1-release.aar` — AIDL CloudPOS (`com.cloudpos.scanserver`), **não serve para o M10 Pro**; o scanner do M10 vem pela própria E1

---

## O que preciso construir

Um **plugin Flutter local** (federated não é necessário — pode ser um pacote no diretório do projeto, ex.: `packages/elgin_m10/`) expondo três módulos:

1. **Impressora térmica** — MethodChannel
2. **Display do cliente de 2,4"** — MethodChannel
3. **Leitor de código de barras 1D/2D integrado** — MethodChannel para controle + **EventChannel** para o stream de leituras

---

## Restrição arquitetural crítica

As três APIs da E1 exigem uma **`Activity`**, não um `Context` de aplicação.

Isso significa que o `FlutterPlugin` **precisa** implementar `ActivityAware`:

```kotlin
class ElginM10Plugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var activity: Activity? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivity() { activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) { activity = b.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
}
```

Chamar qualquer API da E1 com `activity == null` deve devolver um erro claro para o Dart, nunca um NPE. **Esse é o erro mais comum nessa integração** — trate desde o começo.

Além disso: todas as classes da E1 são de **métodos estáticos**. Não há instância. Isso implica estado global no processo — cuide para não abrir a mesma conexão duas vezes.

---

## Configuração Android

### `android/app/build.gradle`

```gradle
android {
    defaultConfig {
        minSdkVersion 21   // exigido pela E1
    }
}

dependencies {
    implementation fileTree(include: ['*.aar'], dir: 'libs')
    implementation("androidx.startup:startup-runtime:1.1.0")
    implementation 'androidx.appcompat:appcompat:1.3.0'
    implementation 'org.apache.commons:commons-lang3:3.9'
    implementation 'com.google.code.gson:gson:2.8.6'
}
```

Se o projeto usar `build.gradle.kts`, converta a sintaxe.

### `AndroidManifest.xml`

A `minipdvm8` declara `android:icon` e `android:label`, o que colide com o manifest do app. É obrigatório:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
    <application
        tools:replace="android:label,android:icon"
        ... >
```

Sem isso o build falha em `processDebugMainManifest` com erro de merge.

### ProGuard / R8

Se houver minificação em release, mantenha as classes da E1:

```proguard
-keep class com.elgin.e1.** { *; }
-keep class net.nyx.** { *; }
-dontwarn com.elgin.e1.**
```

---

## API nativa — assinaturas reais

Extraí estas assinaturas diretamente dos bytecodes da `e1-V02.34.04-release.aar`. São exatas. **Não invente métodos que não estejam nesta lista** — se precisar de algo ausente, me avise em vez de improvisar.

### 1. Impressora térmica — `com.elgin.e1.Impressora.Termica`

```java
static int setContext(Context ctx);
static int setActivity(Activity act);

// Abertura da impressora INTERNA do M10:
//   AbreConexaoImpressora(6, "M8", "", 0)
//   O literal "M8" está correto mesmo no M10 — é o identificador da família.
static int AbreConexaoImpressora(int tipo, String modelo, String conexao, int parametro);
static int FechaConexaoImpressora();

static int InicializaImpressora();
static int ImpressaoTexto(String dados, int posicao, int estilo, int tamanho);
static int ImpressaoCodigoBarras(int tipo, String dados, int altura, int largura, int hri);
static int ImpressaoQRCode(String dados, int tamanho, int nivelCorrecao);
static int ImpressaoPDF417(int colunas, int linhas, int moduloLargura,
                           int moduloAltura, int nivelCorrecao, int opcoes, String dados);
static int ImprimeImagem(String caminho);
static int ImprimeImagem(Bitmap bmp);
static int ImprimeBitmap(Bitmap bmp);
static int ImprimeImagemMemoria(String base64, int modo);
static int AvancaPapel(int linhas);
static int Corte(int avanco);
static int CorteTotal(int avanco);
static int DefinePosicao(int posicao);
static int DefineDensidade(int densidade);
static int DefineLarguraBobina(int largura);
static int SinalSonoro(int qtd, int tempoInicio, int tempoFim);
static int StatusImpressora(int param);
static int AbreGavetaElgin();
static int AbreGaveta(int pino, int ti, int tf);
static int DirectIO(byte[] dados, int tamanho);          // ESC/POS cru
static String GetVersaoDLL();
static String GetSerialEquipamento();

// Modo página
static int ModoPagina();
static int ModoPadrao();
static int DirecaoImpressao(int dir);
static int DefineAreaImpressao(int x, int y, int largura, int altura);
static int PosicaoImpressaoHorizontal(int pos);
static int PosicaoImpressaoVertical(int pos);
static int ImprimeModoPagina();
static int LimpaBufferModoPagina();
static int ImprimeMPeRetornaPadrao();

// Documentos fiscais (requer AARs extras — não implementar agora)
static int ImprimeXMLSAT(String xml, int param);
static int ImprimeXMLNFCe(String xml, int param, String csc, int cscId);
static int ImprimeCupomTEF(String dados);
static int ImprimeEHTML(String html);
```

Convenção de retorno: `0` = sucesso, negativo = erro.

### 2. Display do cliente 2,4" — `com.elgin.e1.Display.E1_Display`

O M10 Pro é suportado nativamente. O enum `E1_Display.DisplayDevices` contém `AUTO`, `PIX4`, `TPRO`, **`M10_PRO`**.

Use `M10_PRO` explicitamente (o `AUTO` funciona lendo propriedades de build `M11G`/`M11Pro`, mas prefiro determinismo).

```java
static void init(Activity act, E1_Display.DisplayDevices device);
static void setDisplay(E1_Display.DisplayDevices device);

static int AbreConexaoDisplay();
static int DesconectarDisplay();
static int InicializaDisplay();
static int ReinicializaDisplay();
static int ObtemVersaoFirmware();

static int ApresentaTexto(String texto, int a, int b, int c);
static int ApresentaTextoColorido(String texto, int a, int b, int c, int d, String cor);
static int ApresentaQrCode(String dados, int a, int b, int c);
static int ApresentaImagemDisplay(Bitmap bmp);
static int ApresentaImagemDisplay(String caminho);
static int ApresentaImagemDisplay(String caminho, int a, int b, int c);
static int CarregaImagemDisplay(Bitmap bmp);
static int CarregaImagemDisplay(String caminho);
static int CarregaImagemDisplay(String a, String b, int c, int d);
static int SetModoInvertido(int modo);

// Layout de PDV pronto — caminho mais curto para uma tela de cliente utilizável
static void InicializaLayoutPagamento(String a, String b, String c);
static void ApresentaListaCompras(String a, String b);
static int  AdicionaFormaPagamento(int tipo, String descricao);
```

Sequência de uso: `init(...)` → `AbreConexaoDisplay()` → `InicializaDisplay()` → comandos de apresentação → `DesconectarDisplay()` no dispose.

Internamente isso resolve para `ImplementacaoM11`, que faz bind no serviço AIDL `net.nyx.printerservice.IPrinterService` (o mesmo da impressora). Se `AbreConexaoDisplay()` falhar, a mensagem típica é "Servico M11 indisponivel".

### 3. Scanner 1D/2D — `com.elgin.e1.Scanner.Scanner`

```java
interface OnScanListener {
    void onScanResult(String codigo);
}

static void init(Activity act, Scanner.OnScanListener listener);
static void iniciaScanner(boolean manterAtivo);  // true = contínuo, false = disparo único
static void iniciaScanner();                      // equivale a disparo único
static void desativaScanner();
static Intent getScanner(Context ctx);            // rota alternativa via Activity
```

Mecanismo interno: registra um `BroadcastReceiver` na action `com.android.NYX_QSC_DATA` e dispara a leitura via `triggerQscScan` no serviço NYX. O resultado chega no `onScanResult`.

A sobrecarga `iniciaScanner(boolean)` **só existe a partir da 02.34.04**. É o motivo de estarmos nessa versão.

---

## Interface Dart desejada

Projete a API Dart, mas nesta linha:

```dart
// Impressora
await ElginPrinter.open();                    // AbreConexaoImpressora(6, "M8", "", 0)
await ElginPrinter.printText(String text, {int align = 0, int style = 0, int size = 0});
await ElginPrinter.printQrCode(String data, {int size = 4, int correction = 0});
await ElginPrinter.printBarcode(String data, {required BarcodeType type, ...});
await ElginPrinter.printImageFromBytes(Uint8List bytes);
await ElginPrinter.feed(int lines);
await ElginPrinter.cut({int feed = 0, bool full = false});
await ElginPrinter.status();
await ElginPrinter.raw(Uint8List escPos);     // DirectIO
await ElginPrinter.close();

// Display
await ElginDisplay.open();
await ElginDisplay.showText(String text, {...});
await ElginDisplay.showQrCode(String data, {...});
await ElginDisplay.showImage(Uint8List bytes);
await ElginDisplay.close();

// Scanner
Stream<String> get ElginScanner.onScan;        // EventChannel
await ElginScanner.start({bool continuous = true});
await ElginScanner.stop();
```

### Regras de mapeamento

- Todo retorno `int != 0` da E1 deve virar uma **exceção Dart tipada**, `ElginException`, carregando o código numérico e uma mensagem legível. Não devolva o inteiro cru para a camada de UI.
- Bitmaps: receba `Uint8List` do Dart, decodifique com `BitmapFactory.decodeByteArray` no Kotlin e passe para `ImprimeImagem(Bitmap)` / `ApresentaImagemDisplay(Bitmap)`. Não escreva arquivo temporário em disco.
- Todas as chamadas nativas bloqueantes (impressão, imagem) devem rodar fora da main thread e devolver o resultado via `Handler(Looper.getMainLooper())` — o `MethodChannel.Result` só pode ser chamado na main thread.

### Scanner via EventChannel

```kotlin
EventChannel(binaryMessenger, "elgin_m10/scanner_events")
    .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(args: Any?, sink: EventChannel.EventSink) {
            val act = activity ?: run { sink.error("NO_ACTIVITY", "...", null); return }
            Scanner.init(act) { codigo ->
                Handler(Looper.getMainLooper()).post { sink.success(codigo) }
            }
        }
        override fun onCancel(args: Any?) { Scanner.desativaScanner() }
    })
```

Atenção ao ciclo de vida: se a Activity for recriada (rotação, retorno do background), o listener precisa ser reregistrado. Chame `desativaScanner()` em `onDetachedFromActivity`.

---

## Entregáveis

1. Estrutura do plugin em `packages/elgin_m10/` (Dart + `android/src/main/kotlin/`)
2. `ElginM10Plugin.kt` implementando `FlutterPlugin` + `ActivityAware` + os três handlers
3. API Dart tipada com `ElginException`
4. Ajustes no `android/app/build.gradle` e `AndroidManifest.xml` do app hospedeiro
5. Uma tela de exemplo em `example/` ou `lib/debug/` que permita: abrir a impressora, imprimir um texto de teste e um QR Code, cortar; abrir o display e mostrar texto; ligar o scanner e listar os códigos lidos
6. `README.md` do plugin com a tabela de códigos de erro que descobrirmos em teste

---

## Como quero que você trabalhe

- Comece confirmando o que encontrou em `android/app/libs/` e a estrutura atual do projeto, **antes** de escrever código.
- Faça na ordem: (1) build passando com os AARs linkados e nada mais, (2) impressora, (3) display, (4) scanner. Não avance de etapa antes da anterior compilar.
- Kotlin no lado nativo.
- Se alguma assinatura da E1 que você precisar não estiver na lista acima, **pare e me pergunte**. Não chame método por adivinhação — o SDK é ofuscado em parte e um método inexistente só falha em runtime no equipamento.
- Não adicione dependências de terceiros para código de barras, impressão ou scanner. Tudo vem da E1.

## Ambiente de teste

Só é possível testar em hardware físico. O emulador não tem o serviço `net.nyx.printerservice` e todas as chamadas vão falhar na abertura de conexão. Escreva o código assumindo que eu rodo com `flutter run` no M10 Pro conectado via cabo de debug com depuração USB ativada.
