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

- [ ] Texto sai legível
- [ ] Alinhamento: esquerda, centro e direita nas posições certas
- [ ] Negrito, sublinhado, altura dupla e largura dupla saem diferentes entre si
- [ ] CODE 128 sai e é legível por um leitor
- [ ] EAN-13 sai e é legível
- [ ] EAN-8 sai e é legível
- [ ] QR Code sai e é legível por um celular
- [ ] Imagem de teste (moldura com "X") sai inteira, sem cortar nem inverter
- [ ] Avançar papel move a bobina
- [ ] Cortar papel: **confirmar se o M10 tem guilhotina** ou se apenas avança
- [ ] Sinal sonoro toca
- [ ] Sem papel: o erro aparece no painel com o código do SDK
- [ ] Fechar e reabrir volta a imprimir sem reiniciar o aplicativo
- [ ] Imprimir com o aplicativo voltando do background ainda funciona

## Display do cliente

- [ ] **Enviar** abre o display e escreve — funciona com `M10_PRO`?
- [ ] Se falhar, **anotar** a mensagem: "Serviço M11 indisponível" aponta para o
      bind AIDL, outro erro aponta para outra coisa
- [ ] Texto aparece na tela do cliente
- [ ] Texto atualiza quando reenviado
- [ ] **Limpar** (reinicializar) devolve o display ao estado inicial
- [ ] Fechar display e reabrir funciona
- [ ] Testar `DisplayDevice.auto` se `M10_PRO` falhar — e anotar a diferença

## Scanner

- [ ] **Iniciar** liga o leitor sem erro
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
