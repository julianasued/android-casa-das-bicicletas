# elgin_m10

Ponte Flutter para os periféricos internos do **Elgin Mini PDV M10 Pro**, sobre
o SDK nativo **E1** da Elgin (pacote `e1_v02.34.04`).

Três módulos: impressora térmica, display do cliente de 2,4" e leitor de código
de barras 1D/2D.

## Instalação

O plugin é um pacote local; a dependência já está declarada no `pubspec.yaml` do
aplicativo:

```yaml
dependencies:
  elgin_m10:
    path: packages/elgin_m10
```

### Bibliotecas nativas

O SDK é binário proprietário e **não** está versionado. Dois arquivos são
necessários, extraídos de `e1_v02.34.04.zip`:

| Arquivo | Onde | Para quê |
|---|---|---|
| `e1-V02.34.04-release.aar` | `android/app/libs/` | Empacotado no APK: classes, `.so`, recursos e AIDL |
| `minipdvm8-v01.00.00-release.aar` | `android/app/libs/` | Camada de comunicação obrigatória do Mini PDV |
| `e1-classes.jar` | `packages/elgin_m10/android/libs/` | Só para **compilar** este módulo |

O terceiro é gerado a partir do primeiro:

```bash
cd android/app/libs
unzip -p e1-V02.34.04-release.aar classes.jar \
  > ../../../packages/elgin_m10/android/libs/e1-classes.jar
```

**Por que dois lugares.** O AGP recusa dependência direta de `.aar` local em
módulo de biblioteca ("Direct local .aar file dependencies are not supported
when building an Android library"), então o plugin não pode declarar o `.aar`.
E declarar os mesmos AARs no módulo do aplicativo **e** no do plugin duplicaria
as classes no dex. A divisão resolve os dois: o aplicativo empacota o SDK
completo (`implementation`), o plugin compila contra os símbolos
(`compileOnly`).

### Configuração no aplicativo hospedeiro

Já aplicadas em `android/app/`:

- `minSdk 21` (exigido pela E1 — o projeto usa 24)
- `tools:replace="android:label,android:icon"` no `<application>`, porque a
  `minipdvm8` declara `android:label` e o merge falharia em
  `processDebugMainManifest`
- `proguard-rules.pro` mantendo `com.elgin.e1.**`, `com.elgin.minipdvm8.**` e
  `net.nyx.**` — o SDK resolve implementações por nome, e ofuscar quebra só em
  release
- `androidx.startup:startup-runtime`, `appcompat`, `commons-lang3` e `gson`

## Uso

```dart
import 'package:elgin_m10/elgin_m10.dart';

// Impressora
await ElginPrinter.open();                       // AbreConexaoImpressora(6, "M8", "", 0)
await ElginPrinter.printText('Casa das Bicicletas',
    align: PrinterAlign.center, style: PrinterStyle.of(bold: true));
await ElginPrinter.printBarcode('SALE-L1-7F3A9C2B', type: BarcodeType.code128);
await ElginPrinter.printQrCode('https://exemplo');
await ElginPrinter.feed(2);
await ElginPrinter.cut();
await ElginPrinter.close();

// Display
await ElginDisplay.open();                       // padrão: DisplayDevice.m10Pro
await ElginDisplay.showText('Total: R\$ 150,00');
await ElginDisplay.close();

// Leitor — assine ANTES de start()
final assinatura = ElginScanner.onScan.listen(print);
await ElginScanner.start(continuous: true);
```

## Erros

Todo retorno diferente de zero da E1 vira `ElginException`, com o código
numérico e a função que falhou:

```dart
try {
  await ElginPrinter.printText('teste');
} on ElginException catch (e) {
  print('${e.operation} falhou: ${e.code} — ${e.message}');
  if (e.isUnavailable) { /* SDK ausente ou sem Activity */ }
}
```

| `kind` | Quando |
|---|---|
| `noActivity` | Plugin sem Activity anexada — as APIs da E1 exigem uma |
| `sdkError` | O SDK recusou; `code` traz o retorno |
| `sdkMissing` | Classes da E1 fora do APK (emulador, build sem AARs) |
| `invalidArgument` | Argumento inválido antes de chegar ao SDK |

### Tabela de códigos

A Elgin publica os códigos de conexão e de escrita, mas **não** o significado
dos valores devolvidos por `StatusImpressora`. Esta tabela cresce com o que for
descoberto em teste:

| Código | Significado | Origem |
|---|---|---|
| `0` | Sucesso | Documentação |
| `-2` | Tipo de conexão inválido | Documentação |
| `-3` | Modelo não suportado | Documentação |
| `-4` | Porta de comunicação fechada | Documentação |
| `-6` | Conexão já ativa | Documentação |
| `-41` | Posição de impressão inválida | Documentação |
| `-42` | Estilo de texto inválido | Documentação |
| `-43` | Tamanho de texto inválido | Documentação |
| `-44` | Falha na escrita | Documentação |
| `-403` | Conexão de tipo 10 em uso | Bytecode |
| `-2023` | Conexão perdida | Bytecode |
| `-9999` | Erro desconhecido | Documentação |
| `StatusImpressora(3)` = ? | Papel — **a mapear no aparelho** | — |

## Limitações conhecidas

- **Só funciona no hardware.** O serviço `net.nyx.printerservice` não existe em
  emulador; a abertura de conexão falha e todo o resto vai junto.
- **O SDK é estático.** `Termica`, `E1_Display` e `Scanner` só têm métodos
  estáticos: o estado é do processo, não do objeto. O plugin serializa todas as
  chamadas em uma thread única para que duas operações não mexam na mesma
  conexão — mas isso não protege contra outro código do aplicativo chamando o
  SDK por fora.
- **`AbreConexaoImpressora(6, "M8", ...)` não está na documentação pública**,
  que descreve `tipo` de 1 a 5 e cujo exemplo oficial usa `(5, "")`. Os quatro
  parâmetros são configuráveis em `ElginPrinter.open()` justamente para testar a
  outra combinação sem recompilar.
- **Documentos fiscais** (`ImprimeXMLSAT`, `ImprimeXMLNFCe`, `ImprimeCupomTEF`)
  exigem AARs adicionais e não estão implementados.
