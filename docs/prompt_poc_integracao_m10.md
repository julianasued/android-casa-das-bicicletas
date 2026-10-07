# PROMPT — PREPARAR POC DE INTEGRAÇÃO ELGIN M10

## Objetivo

Analise o projeto Android/Flutter atual e implemente somente o necessário para deixar um POC (Proof of Concept) do Elgin M10 funcional e pronto para testes no aparelho físico.

O POC deve validar:
1. Impressora térmica interna.
2. Scanner integrado para código de barras/QR Code.
3. Display do cliente.
4. Comunicação Flutter ↔ Android ↔ hardware.
5. Tratamento básico de erros e reconexão da impressora.

NÃO integrar neste POC Django, vendas, comissão, estoque, notinha, pagamentos ou regras de negócio.

---

## REGRAS IMPORTANTES

- Antes de alterar qualquer arquivo, inspecione o projeto atual.
- Preserve a arquitetura existente sempre que possível.
- Não reescreva partes que já funcionam sem necessidade.
- Não invente APIs, métodos, intents, extras, códigos de status ou constantes da Elgin.
- Use a documentação oficial da Elgin como fonte para a integração do M10.
- Diferencie: dependência instalada; API disponível; API usada; funcionalidade implementada; funcionalidade validada no hardware.
- Se algo não puder ser confirmado, marque como PENDENTE DE VALIDAÇÃO.
- Não remover funcionalidades existentes.
- Não implementar offline completo neste POC.
- O POC deve funcionar sem depender do backend.

## DOCUMENTAÇÃO OFICIAL

E1 / M10 / PosGo:
https://elgindevelopercommunity.github.io/group__g30.html

Impressora M10:
https://elgindevelopercommunity.github.io/group__m80.html

Use essas fontes para confirmar AARs, dependências, versões, classes, métodos, assinaturas, parâmetros e funções da impressora.

---

# 1. DEPENDÊNCIAS

Verifique `android/app/build.gradle` e `android/app/libs/`.

O projeto deve utilizar, conforme exigido pela documentação oficial atual:

- `e1-vx.y.z-release.aar`
- `minipdvm8.aar`
- `androidx.startup:startup-runtime:1.0.0`
- `com.google.zxing:core:3.4.0`
- `io.reactivex.rxjava2:rxandroid:2.0.1`
- `io.reactivex.rxjava2:rxjava:2.1.8`

Os `.aar` precisam ser arquivos reais fornecidos pela Elgin. NÃO criar AAR falso e NÃO baixar SDK de origem não oficial.

Se os AARs não estiverem disponíveis:
- não invente conteúdo;
- configure somente o que for seguro;
- informe que os arquivos precisam ser fornecidos;
- não declare a integração concluída.

---

# 2. IMPRESSORA

Corrija `ElginThermalPrinter.kt` para usar a API oficial E1 quando os AARs estiverem disponíveis.

Evite reflexão se a API puder ser referenciada diretamente pelo SDK.

Garanta que a Activity seja fornecida corretamente à camada da impressora.

Arquitetura desejada:

`MainActivity → PrinterChannel → ElginThermalPrinter → Termica`

Não colocar toda a lógica dentro da MainActivity.

A documentação oficial do M10 mostra a inicialização com `Termica.setActivity(...)` e a conexão da impressora interna usando o tipo de comunicação documentado pela Elgin. Não assumir parâmetros diferentes da documentação.

---

# 3. FUNÇÕES DO POC DA IMPRESSORA

Criar testes separados para:

- imprimir texto;
- testar formatação realmente suportada;
- imprimir código de barras nas simbologias realmente suportadas;
- imprimir QR Code;
- imprimir imagem/logo;
- avançar papel;
- cortar papel;
- consultar status;
- tratar impressora indisponível;
- tratar sem papel;
- tratar falha de impressão;
- fechar/reabrir conexão após erro.

Não limitar artificialmente funcionalidades que o SDK oficial disponibilizar.

---

# 4. TELA DO POC

Criar:

`lib/presentation/m10_poc/m10_poc_page.dart`

Tela independente do fluxo de venda, com:

```text
================================
       TESTE ELGIN M10
================================

IMPRESSORA
[ Imprimir Texto ]
[ Imprimir Código de Barras ]
[ Imprimir QR Code ]
[ Imprimir Imagem ]
[ Avançar Papel ]
[ Cortar Papel ]
[ Consultar Status ]

SCANNER
[ Iniciar Scanner ]
[ Parar Scanner ]

Última leitura:
Código: __________
Tipo: ____________
Origem: __________

DISPLAY
Mensagem: __________________
[ Enviar ao Display ]
[ Limpar Display ]

STATUS
Impressora: ...
Scanner: ...
Display: ...
Último erro: ...
================================
```

Cada botão deve chamar apenas a interface correspondente do hardware.

---

# 5. SCANNER

Manter a arquitetura existente de `ScannerChannel.kt`, mas confirmar a integração somente com a API real do M10.

Investigar:
- pacote;
- BroadcastReceiver;
- ação;
- extras;
- formato do resultado;
- modo teclado;
- configuração do scanner.

Não assumir que estes nomes são oficiais sem confirmação:

- `com.elgin.scanner.ACTION_BARCODE`
- `com.elgin.e1.scanner.SCAN_RESULT`
- `android.intent.ACTION_DECODE_DATA`
- `scan.rcv.message`

Se não forem confirmados, não tratá-los como API oficial.

O POC deve mostrar:
- código recebido;
- simbologia, quando disponível;
- horário;
- origem.

Testar, quando suportado pelo hardware:
- EAN-13;
- EAN-8;
- Code128;
- QR Code.

---

# 6. ZXING

Adicionar ZXing conforme a documentação oficial se necessário:

`com.google.zxing:core:3.4.0`

Não implementar leitura por câmera apenas para usar ZXing.

Diferenciar o scanner integrado do M10 de decodificação por câmera.

---

# 7. DISPLAY DO CLIENTE

Investigar se existe API oficial para o display de cliente de 2,4".

Se existir:
- implementar;
- enviar texto;
- limpar;
- mostrar valor;
- mostrar desconto;
- mostrar valor final.

Se não existir API pública confirmada:
- criar apenas a abstração `CustomerDisplay`;
- criar `M10CustomerDisplay` como implementação pendente;
- NÃO inventar comandos/intents.

Arquitetura:

```text
CustomerDisplay
├── FakeCustomerDisplay
└── M10CustomerDisplay
```

---

# 8. ABSTRAÇÃO DE HARDWARE

Preservar:

```text
DocumentPrinter
├── FakeDocumentPrinter
└── PrinterChannel
    └── ElginThermalPrinter
```

e:

```text
BarcodeScanner
├── FakeBarcodeScanner
└── ScannerChannel
```

Se necessário, criar:

```text
CustomerDisplay
├── FakeCustomerDisplay
└── M10CustomerDisplay
```

Não duplicar lógica de hardware no Flutter.

---

# 9. ANDROID / BUILD

Verificar:
- minSdk;
- compileSdk;
- targetSdk;
- Kotlin;
- Java;
- Gradle;
- Android Gradle Plugin;
- Manifest;
- permissões;
- carregamento dos AARs.

Não adicionar permissões sem necessidade comprovada.

Depois executar, se o ambiente permitir:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk
```

e, quando apropriado:

```bash
./gradlew assembleDebug
```

Corrigir erros de compilação relacionados à integração. Não mascarar erros.

---

# 10. NÃO IMPLEMENTAR NESTE POC

Não implementar agora:
- Django;
- autenticação de vendedor;
- comissão;
- estoque;
- notinha;
- pagamentos;
- venda real;
- sincronização offline;
- SQLite das vendas;
- cancelamento;
- devolução;
- regras de negócio;
- emissão fiscal.

Objetivo: provar a comunicação com o hardware M10.

---

# 11. TESTE NO M10 FÍSICO

Preparar checklist:

## Impressora
[ ] conexão
[ ] texto
[ ] formatação
[ ] código de barras
[ ] QR Code
[ ] imagem
[ ] avanço
[ ] corte
[ ] status
[ ] sem papel
[ ] erro
[ ] repetição/reabertura

## Scanner
[ ] detectado
[ ] EAN-13
[ ] EAN-8
[ ] Code128
[ ] QR Code
[ ] leituras repetidas
[ ] papel impresso

## Display
[ ] detectado
[ ] texto
[ ] atualização
[ ] limpar
[ ] valor
[ ] desconto
[ ] valor final

## Aplicativo
[ ] instalar APK
[ ] iniciar
[ ] abrir POC
[ ] executar testes
[ ] reiniciar app
[ ] reiniciar aparelho
[ ] testar novamente

---

# 12. RELATÓRIO FINAL OBRIGATÓRIO

Ao terminar, informe:

## A. Arquivos alterados

Para cada arquivo:
- caminho;
- alteração;
- motivo.

## B. Arquivos criados

Para cada arquivo:
- caminho;
- finalidade.

## C. Dependências

| Dependência | Versão | Situação |
|---|---|---|
| E1 AAR | ... | ... |
| minipdvm8 | ... | ... |
| startup-runtime | ... | ... |
| ZXing | ... | ... |
| RxJava | ... | ... |
| RxAndroid | ... | ... |

## D. Impressora

Informar:
- API utilizada;
- funções implementadas;
- funções não implementadas;
- funções pendentes de teste físico.

## E. Scanner

Informar:
- API utilizada;
- Intent;
- extras;
- modo;
- o que foi confirmado;
- o que ainda precisa ser confirmado.

## F. Display

Informar:
- API encontrada ou não;
- implementação feita ou não;
- o que precisa ser confirmado no aparelho.

## G. Build

```text
flutter analyze: PASS/FAIL
flutter test: PASS/FAIL
flutter build apk: PASS/FAIL
```

## H. Status final

Usar somente:
- `PRONTO PARA TESTE`
- `PARCIAL`
- `BLOQUEADO POR DEPENDÊNCIA`
- `PENDENTE DE HARDWARE`
- `NÃO IMPLEMENTADO`

Não declarar integração pronta enquanto o M10 físico não tiver sido testado.

---

# CRITÉRIO DE SUCESSO

O POC será considerado pronto quando:

1. As dependências oficiais necessárias estiverem integradas.
2. O projeto compilar.
3. O APK puder ser instalado no M10.
4. A impressora puder ser testada pela tela POC.
5. Texto, código de barras, QR Code, imagem, avanço, corte e status puderem ser testados quando suportados pelo SDK.
6. O scanner puder ser testado usando a API real do M10, ou ficar claramente marcado como pendente se a API não estiver disponível.
7. O display puder ser testado usando API oficial, ou ficar claramente marcado como pendente.
8. Nenhuma API fictícia/não confirmada for tratada como oficial.
9. O POC permanecer separado das regras de negócio.

## REGRA FINAL

Compare cada chamada do código com a documentação oficial da Elgin.

Se houver diferença em:
- nome do método;
- assinatura;
- parâmetro;
- código de comunicação;
- código de status;
- Intent;
- extra;
- classe;

não faça suposição. Marque a diferença e informe exatamente o que precisa ser confirmado.
