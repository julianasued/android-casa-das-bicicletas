# Checklist de teste no Elgin M10 Pro

Roteiro do POC de integração. Abrir o aplicativo → **Teste Elgin M10** no menu
do terminal (ou rota `/m10`).

Nada disto funciona em emulador: o serviço `net.nyx.printerservice` só existe no
aparelho. Rode com `flutter run` no M10 Pro ligado por cabo, com depuração USB
ativada.

## Preparação

- [ ] `android/app/libs/` contém `e1-V02.34.04-release.aar` e
      `minipdvm8-v01.00.00-release.aar`
- [ ] `packages/elgin_m10/android/libs/e1-classes.jar` existe
      (`unzip -p e1-V02.34.04-release.aar classes.jar > ...`)
- [ ] `flutter pub get` sem erro
- [ ] `flutter analyze` sem erro
- [ ] `flutter test` verde
- [ ] `flutter build apk` gera o APK — atenção a `processDebugMainManifest`, que
      é onde o merge da `minipdvm8` falharia sem o `tools:replace`
- [ ] APK instalado no M10
- [ ] Aplicativo abre e a tela do POC carrega

## Impressora

### Conexão — a primeira pergunta a responder

- [x] Com `tipo 6` e modelo `M8` (padrão), **Abrir** funciona?
- [ ] Se não, tentar `tipo 5` e modelo vazio na própria tela
- [x] **Anotar** qual combinação funcionou e o código de erro da que falhou
- [ ] Versão do SDK e número de série aparecem no painel após abrir

**RESPONDIDO (09/09/2026, M10 Pro, SDK 02.34.04):** `tipo 6` + modelo `M8`
conecta — o painel mostrou "impressora conectada". Não foi preciso recorrer ao
`tipo 5`/vazio.

Isto resolve a pendência aberta no commit do plugin: a combinação funciona
mesmo **não constando da documentação pública** da Elgin, que descreve tipo
de 1 a 5 e cujo exemplo oficial usa `(5, "")`. O padrão do código
(`PrinterHandler.DEFAULT_CONNECTION_TYPE = 6`, `DEFAULT_MODEL = "M8"`) está
certo e não precisa mudar.

### Status — a segunda pergunta

- [x] **Anotar** `StatusImpressora` bruto com a bobina **cheia**
- [x] **Anotar** com a bobina **vazia**
- [x] **Anotar** com a **tampa aberta**
- [ ] **Anotar** com a impressora ocupada, se der para reproduzir

**RESPONDIDO (09/09/2026, M10 Pro, SDK 02.34.04).** Retorno bruto de
`StatusImpressora(param)` nos quatro estados testados:

| Assunto (`param`)  | Papel + tampa fechada | Sem papel | Tampa aberta (com bobina) | Sem papel + tampa aberta |
| ------------------ | --------------------- | --------- | ------------------------- | ------------------------ |
| `drawer` (1)       | −126                  | −126      | −126                      | −126                     |
| `cover` (2)        | 4                     | 4         | 4                         | 4                        |
| `paper` (3)        | **5**                 | **7**     | **7**                     | **7**                    |
| `ejector` (4)      | −126                  | −126      | −126                      | −126                     |
| `general` (5)      | −126                  | −126      | −126                      | −126                     |

O que isto significa para o aplicativo:

- **Só `paper` serve.** `5` = pronto para imprimir; `7` = não dá para imprimir.
- **Tampa aberta e falta de papel são indistinguíveis:** os dois dão `paper 7`.
  O aviso ao operador tem de cobrir os dois casos — algo como "verifique o
  papel e a tampa", nunca afirmar qual dos dois é.
- **`cover` é inerte.** Ficou em `4` nos quatro estados, inclusive de tampa
  aberta. Não usar para detectar a tampa.
- **−126 é "não aplicável".** Constante em `drawer`, `ejector` e `general`, que
  o M10 Pro não expõe (não tem gaveta nem ejetor). Tratar qualquer negativo
  como ausência de informação, não como estado de erro.

Só `paper` deve alimentar a verificação que antecede a impressão da notinha.
Diferença entre `5` e `7` é de um bit (`101` → `111`), mas a hipótese de
máscara de bits **não se confirmou**: se valesse, a tampa aberta teria levado
`cover` de `4` para `6`, e ela não se moveu. Fica o mapeamento literal.

### Impressão

- [x] Texto sai legível
- [x] Alinhamento: esquerda, centro e direita nas posições certas
- [x] Negrito, sublinhado, altura dupla e largura dupla saem diferentes entre si
- [x] CODE 128 sai e é legível por um leitor  *(só desenhado como imagem)*
- [ ] EAN-13 sai e é legível  *(sai pelo SDK; leitura irregular)*
- [x] EAN-8 sai e é legível  *(pelo SDK, sem precisar de imagem)*
- [x] QR Code sai e é legível por um celular
- [x] Imagem de teste (moldura com "X") sai inteira, sem cortar nem inverter
- [ ] Avançar papel move a bobina
- [x] Cortar papel: **confirmar se o M10 tem guilhotina** ou se apenas avança
- [x] Sinal sonoro toca  *(não toca: o M10 não suporta)*
- [ ] Sem papel: o erro aparece no painel com o código do SDK
- [ ] Fechar e reabrir volta a imprimir sem reiniciar o aplicativo
- [ ] Imprimir com o aplicativo voltando do background ainda funciona

#### Quatro defeitos entre o primeiro toque e o primeiro cupom (09/09/2026)

Cada um escondia o seguinte, e nenhum apareceria sem o aparelho na mão:

1. **Retorno positivo não é erro.** `ImpressaoTexto` devolveu `20` — os 19
   caracteres de "CASA DAS BICICLETAS" mais a quebra de linha — e o
   `checkElgin` reprovava qualquer valor diferente de zero. Só valor
   **negativo** é erro, conforme a tabela `CodigoErro` do AAR e a documentação
   da Elgin.
2. **`CONEXAO_ATIVA` (-6) não é falha.** As classes da E1 são estáticas e a
   conexão pertence ao processo, então sobrevive à tela que a abriu. Depois de
   trocar de tela, reabrir devolvia -6 e a impressora ficava inacessível.
3. **CODE 128 exige seletor de conjunto.** A tabela do parâmetro `tipo` manda
   primeiro caractere `{` e segundo `A`/`B`/`C`. Sem isso o SDK devolve -65 até
   para `12345678`.
4. **A ZXing não estava no APK.** O E1 desenha códigos e QR Code com ela, mas o
   AAR é local e entra por `fileTree`, que não carrega dependência transitiva.

Ver 6afc4cd, d9c434c e 8d6ccd3.

#### Códigos de barras: legibilidade em aberto (10/09/2026)

Os três saem no papel, mas **só o EAN-8 decodifica de forma confiável**. O
CODE 128 do código de venda (`SALE-L1-7F3A9C2B`) não foi lido nem por câmera
de celular nem isolado num cupom só.

Limite medido, imprimindo CODE 128 de comprimentos decrescentes e lendo cada
um: `ABC123` (6 caracteres, 101 módulos) lê; `7F3A9C2B` (8 caracteres, 123
módulos) já não. Para referência, o EAN-8 tem 67 módulos e o EAN-13, 95.

**Isso é anormalmente baixo.** CODE 128 de 16 caracteres em papel de 58 mm é
rotina no varejo. Um aparelho que só decodifica até 6 caracteres tem problema
de impressão, não de formato do código — e o quadro fecha com o resto do que
se observou: barras borradas, o mesmo código lendo numa impressão e falhando
na seguinte.

**A densidade não é ajustável por software neste aparelho.** `DefineDensidade`
existe no AAR (não na documentação pública), aceita 1..4 e monta o `ESC 7` do
ESC/POS. Mas o bytecode mostra que ela descarta o retorno de
`Conexao.Escrever` e devolve 0 incondicionalmente: no M10 a impressão passa
pelo serviço NYX, que ignora o comando cru. Os quatro níveis saíram idênticos
no papel. Não vale expor no plugin.

Antes de mexer no formato do código de venda — o que exigiria mudar o
`identifiers.py` do backend junto, já que terminal e servidor calculam o mesmo
código —, **eliminar as causas físicas**: bateria a 100% (bateria baixa imprime
fraco), cabeça de impressão limpa com álcool isopropílico, e bobina de outro
lote. Só se o limite não subir depois disso é que a conversa passa a ser sobre
encurtar o formato ou trocar de simbologia.

Se chegar a esse ponto, o EAN-13 (95 módulos) é o mais legível, mas tem um
custo: o caixa usa o mesmo leitor para produtos, e um EAN-13 de venda pode ser
confundido com o código de uma bicicleta. Encurtar mantendo CODE 128 preserva
a distinção e a leitura humana do código.

#### Como cada símbolo ficou (10/09/2026)

| Símbolo | Caminho | Situação |
| ------- | ------- | -------- |
| CODE 128 | **imagem** (`barcode_bitmap.dart`) | lê — é o do código de venda |
| EAN-8 | SDK | lê |
| EAN-13 | SDK | sai; leu numa tirada e falhou em outra |
| QR Code | SDK | lê |
| Imagem | SDK | sai inteira, sem cortar nem espelhar |

O CODE 128 é o único que precisou sair do SDK. Desenhado por nós, o código de
venda `SALE-L1-7F3A9C2B` lê; pelo SDK, impresso na mesma tirada de papel,
continuou ilegível. Ver 5f66074 e fbda7d8.

O EAN-13 fica como dúvida aberta: leu numa impressão e não em outra, e não foi
investigado a fundo porque a venda não depende dele. Se um dia depender, o
caminho é o mesmo do CODE 128.

**O M10 não tem sinal sonoro.** `SinalSonoro` responde -401
(`ERRO_FUNCAO_NAO_SUPORTADA`). Não é defeito e não adianta insistir: quem
quiser avisar o operador por som terá de usar o áudio do Android, não a
impressora.

#### Duas medidas que ficam

**Papel em branco não significa comando recusado.** A impressora é bufferizada
e só descarrega no avanço de papel. Confirme com "Avançar papel" antes de
concluir que nada foi impresso — foi o que revelou o defeito 1.

**O vão da lâmina é de 3 linhas.** Medido com uma régua de 12 linhas impressas
seguidas de corte sem avanço: sobraram 9. Cortar com menos de 3 linhas de
avanço come o fim do cupom — foi o que decepou o EAN-8, com a POC avançando 2.

Consequência para a notinha: `document_layout` termina com `PrintFeed(2)` +
`PrintCut()` (avanço 3), somando 5 — folga de 2 sobre o necessário, e o último
elemento antes do corte é texto. **O rodapé do cliente está seguro.** Quem
mexer no fim do documento precisa manter essa soma acima de 3.


## Display do cliente

**NÃO FUNCIONA no aparelho testado (10/09/2026), e a causa mais provável é o
terminal não ter o serviço.** O display físico existe, mas `AbreConexaoDisplay`
nunca abre.

O que o log da própria E1 mostra, lido de dentro do aplicativo (um app lê o seu
próprio logcat sem permissão especial — foi o que destravou o diagnóstico):

```
Valor de Activity display ...MainActivity@a9954b7   <- a Activity chega
Modelo: M11
Entrando na Função: AbreConexao
E/CONM11: Falha ao solicitar o vínculo com o serviço da impressora.
Retorno AbreConexao: -173
```

Descartado pelo caminho, cada um com teste próprio:

| Suspeita | Como caiu |
| -------- | --------- |
| Dispositivo errado no enum | os cinco falham; `AUTO` resolve para `M10_PRO` |
| Conflito com a impressora | resultado idêntico com ela aberta e fechada |
| Permissão de armazenamento | concedida à mão, mesmo erro |
| Activity nula | o log mostra a Activity presente |
| Visibilidade de pacote (Android 11+) | `<queries>` declarado; bind continua falhando |

**Cuidado com o -173:** o `ConM11.abrir` devolve esse mesmo código para "Activity
nula" **e** para falha de bind. Ler só o primeiro `ireturn` do bytecode leva
para o lado errado — foi o que aconteceu aqui, e custou três APKs de
diagnóstico. Só o log separa os dois.

O que sobra verificar, para quem retomar: se o pacote `net.nyx.printerservice`
está instalado no terminal (`pm list packages | grep nyx`) e se algum serviço
responde à action `net.nyx.printerservice.IPrinterService`. Se não estiver, não
há o que corrigir do lado do aplicativo — é firmware ou modelo sem o recurso.

Nada disto bloqueia a venda: o display é comodidade para o cliente ver o valor,
e o operador não perde nenhuma função sem ele.

### ⚠️ Tentativa pelo caminho iMin desligou o terminal (11/09/2026)

**Não repetir sem falar com a Elgin antes.** Um APK que seguia o caminho
descrito abaixo fez o M10 **desligar** durante o teste. A impressora continuou
funcionando depois, mas um terminal que reinicia no meio do atendimento é pior
que um display que não acende.

O que a investigação estabeleceu, e que fica aqui porque é factual e pouparia o
trabalho de quem tentar de novo:

**`M10_PRO` nunca usou `ImplementacaoM11`.** O `setDisplay` do `E1_Display`
mapeia (`tableswitch` sobre o `$SwitchMap`) assim:

| Enum | Índice | Implementação |
| ---- | ------ | ------------- |
| PIX4 | 1 | `ImplementacaoPIX4` |
| TPRO | 2 | `ImplementacaoIMIN` |
| **M10_PRO** | **3** | **`ImplementacaoIMIN`** |
| M11 | 4 | `ImplementacaoM11` |

**As três famílias têm contratos complementares**, e cada uma deixa como stub o
que não faz — o stub loga "Dispositivo não suporta esta função" e devolve
`FALHA` (-1) sem tentar nada:

| Método | iMin | M11 | PIX4 |
| ------ | ---- | --- | ---- |
| `AbreConexaoDisplay` | — | sim | sim |
| `InicializaDisplay` | sim | sim | sim |
| `ApresentaTexto` | — | sim | — |
| `ApresentaTextoColorido` | sim | — | sim |
| `DesconectarDisplay` | — | sim | sim |

Daí o `-1` do M10_PRO: não é falha de hardware, é `IAbreConexaoDisplay` sendo
stub no iMin. E o texto simples também é stub ali — só o colorido existe.

A correção aparente seria pular `AbreConexaoDisplay` e usar
`ApresentaTextoColorido`. **Foi isso que desligou o aparelho**, e é onde a
investigação para: sem documentação da Elgin sobre a sequência correta do
display iMin, mexer às cegas em algo que derruba o terminal não se justifica
por um recurso que não bloqueia a venda.

**Próximo passo é com a Elgin, não com o código:** perguntar qual é a sequência
oficial do display de 2,4" do M10 Pro no SDK E1 02.34.04, dado que
`AbreConexaoDisplay` não é suportado nessa família.


- [ ] **Enviar** abre o display e escreve — funciona com `M10_PRO`?
- [ ] Se falhar, **anotar** a mensagem: "Serviço M11 indisponível" aponta para o
      bind AIDL, outro erro aponta para outra coisa
- [ ] Texto aparece na tela do cliente
- [ ] Texto atualiza quando reenviado
- [ ] **Limpar** (reinicializar) devolve o display ao estado inicial
- [ ] Fechar display e reabrir funciona
- [ ] Testar `DisplayDevice.auto` se `M10_PRO` falhar — e anotar a diferença

## Scanner

- [x] **Iniciar** liga o leitor sem erro

**Só isto foi verificado (10/09/2026).** `Scanner.init` e `iniciaScanner`
passam sem erro, o que já descarta Activity ausente e ouvinte não registrado —
os dois modos de falha que o plugin trata. Nada abaixo foi testado: não se
localizou o gatilho físico do aparelho, e sem disparo não há leitura para
conferir. Fica para quem tiver o manual do M10 em mãos ou souber qual botão
aciona o leitor.

- [ ] Apertar o gatilho: o código aparece no painel
- [ ] EAN-13 lido
- [ ] EAN-8 lido
- [ ] Code128 lido
- [ ] QR Code lido
- [ ] Leituras repetidas em sequência, sem travar (contador sobe)
- [ ] Ler o código impresso pelo próprio terminal
- [ ] **Parar** desliga: apertar o gatilho não produz mais leitura
- [ ] Iniciar de novo depois de parar funciona
- [ ] Girar o aparelho / voltar do background e ler de novo — o ouvinte
      sobreviveu?

## Aplicativo

- [ ] Instalar APK
- [ ] Abrir a tela do POC
- [ ] Executar todos os testes acima
- [ ] Reiniciar o aplicativo e repetir impressora e leitor
- [ ] Reiniciar o aparelho e repetir
- [ ] Build de **release** (`flutter build apk --release`) e repetir a impressão
      — é onde o ProGuard mal configurado apareceria

## O que trazer de volta deste teste

1. Qual combinação de `AbreConexaoImpressora` funciona: `(6, "M8")` ou `(5, "")`.
2. A tabela de `StatusImpressora` — papel cheio, papel vazio, tampa aberta.
3. Se `Corte` corta ou apenas avança.
4. Se o display responde com `M10_PRO`, e a mensagem exata quando não responde.
5. Se o leitor sobrevive ao ciclo de vida da Activity.
6. Qualquer código de erro do SDK que apareça — vai para a tabela do
   `packages/elgin_m10/README.md`.

Com essas seis respostas, o que hoje está marcado como PENDENTE vira código
definitivo, e a integração sai do POC para o fluxo de venda.
