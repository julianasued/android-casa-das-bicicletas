# Checklist de teste no Elgin M10 físico

Roteiro do POC de integração. Abrir o aplicativo → **Teste Elgin M10** no menu
do terminal (ou rota `/m10`).

Antes de começar, confirme que os `.aar` da Elgin estão em `android/app/libs/`
(ver `android/app/libs/README.md`). Sem eles a impressora responde
`PRINTER_UNAVAILABLE` e o roteiro para no primeiro item.

## Preparação

- [ ] `.aar` do E1 e do minipdvm8 copiados para `android/app/libs/`
- [ ] `flutter pub get` sem erro
- [ ] `flutter analyze` sem erro
- [ ] `flutter test` verde
- [ ] `flutter build apk` gera o APK
- [ ] APK instalado no M10
- [ ] Aplicativo abre e chega à tela de configuração do terminal

## Impressora

- [ ] Conexão abre (status "disponível" no painel do POC)
- [ ] **Anotar** os valores de `StatusImpressora` bruto exibidos no painel
      (`paper`, `cover`, `drawer`, `general`) com a bobina **cheia**
- [ ] **Anotar** os mesmos valores com a bobina **vazia** — é este par que fecha
      o mapeamento que a documentação não publica
- [ ] **Anotar** os mesmos valores com a **tampa aberta**
- [ ] Imprimir texto: sai legível
- [ ] Formatação: negrito, sublinhado, altura dupla e largura dupla saem
      diferentes entre si
- [ ] Alinhamento: esquerda, centro e direita saem nas posições certas
- [ ] CODE 128 sai e é legível por um leitor
- [ ] EAN-13 sai e é legível
- [ ] EAN-8 sai e é legível
- [ ] QR Code sai e é legível por um celular
- [ ] Imagem: informar um caminho válido no aparelho e conferir a impressão
- [ ] Avançar papel move a bobina
- [ ] Cortar papel: **confirmar se o M10 tem guilhotina** ou se o comando apenas
      avança
- [ ] Sem papel: mensagem de erro específica, não genérica
- [ ] Falha de impressão: mensagem aparece no painel do POC
- [ ] Fechar e reabrir conexão volta a imprimir sem reiniciar o aplicativo
- [ ] Qual método de inicialização a versão instalada expõe: `setContext` ou
      `setActivity`? (o log avisa quando nenhum é encontrado)

## Scanner

- [ ] Abrir Configurações → Scanner do M10 e **anotar o modo** (broadcast ou
      teclado) e, se broadcast, **a ação e a chave de extra**
- [ ] "Classe do scanner SmartPOS presente" no painel: sim ou não?
- [ ] Iniciar scanner e disparar o gatilho: a leitura aparece?
- [ ] Se não aparecer, aplicar a ação anotada e testar de novo
- [ ] EAN-13 lido
- [ ] EAN-8 lido
- [ ] Code128 lido
- [ ] QR Code lido
- [ ] Simbologia vem preenchida na leitura?
- [ ] Leituras repetidas em sequência, sem travar
- [ ] Ler o código impresso pelo próprio terminal (documento 1)
- [ ] Modo teclado: digitar/bipar com o campo focado também registra

## Display do cliente

- [ ] "Tela secundária detectada" no painel: sim ou não?
- [ ] Se sim, **anotar** id e nome das telas listadas
- [ ] Se não, confirmar com a Elgin qual SDK controla o display de 2,4"
- [ ] Enviar texto (pendente de API)
- [ ] Atualizar texto (pendente de API)
- [ ] Limpar (pendente de API)
- [ ] Valor da venda / desconto / valor final (pendente de API)

## Aplicativo

- [ ] Instalar APK
- [ ] Iniciar
- [ ] Abrir a tela do POC
- [ ] Executar todos os testes acima
- [ ] Reiniciar o aplicativo e repetir os testes de impressora
- [ ] Reiniciar o aparelho e repetir
- [ ] Deixar o aplicativo em segundo plano por alguns minutos e repetir

## O que trazer de volta deste teste

1. A tabela de valores de `StatusImpressora` (papel cheio / vazio / tampa
   aberta).
2. O modo do leitor e, se for broadcast, a ação e o extra reais.
3. Se a classe do scanner do SmartPOS existe no M10.
4. Se o display aparece como tela secundária para o Android.
5. Se `Corte` corta ou apenas avança.
6. Qual método de inicialização da impressora a versão do SDK expõe.

Com essas seis respostas, o que hoje está marcado como PENDENTE DE VALIDAÇÃO
vira código definitivo.
