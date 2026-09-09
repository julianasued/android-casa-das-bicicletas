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

- [ ] Com `tipo 6` e modelo `M8` (padrão), **Abrir** funciona?
- [ ] Se não, tentar `tipo 5` e modelo vazio na própria tela
- [ ] **Anotar** qual combinação funcionou e o código de erro da que falhou
- [ ] Versão do SDK e número de série aparecem no painel após abrir

### Status — a segunda pergunta

- [ ] **Anotar** `StatusImpressora` bruto com a bobina **cheia**
- [ ] **Anotar** com a bobina **vazia**
- [ ] **Anotar** com a **tampa aberta**
- [ ] **Anotar** com a impressora ocupada, se der para reproduzir

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
