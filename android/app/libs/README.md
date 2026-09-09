# Bibliotecas nativas do terminal

Esta pasta recebe o **SDK E1 da Elgin** (`.aar`) para o M10 Pro, usado pela
impressora térmica integrada.

O arquivo não está versionado: é binário proprietário, distribuído pelo
fabricante junto com o terminal. O `.gitignore` do projeto ignora `*.aar` e
`*.jar` aqui.

## Como instalar

1. Obtenha o pacote do SDK E1 Android com a Elgin (portal do desenvolvedor ou
   suporte técnico do terminal).
2. Copie o `.aar` para esta pasta.
3. Rode `flutter build apk` — o Gradle já inclui `libs/*.aar`
   (`android/app/build.gradle`).
4. Confira as assinaturas usadas em
   `android/app/src/main/kotlin/br/com/casadasbicicletas/vendas/platform/ElginThermalPrinter.kt`
   (objeto `Sdk`) contra a versão recebida: os nomes dos métodos e os códigos de
   conexão variam entre versões do SDK.

## Sem o SDK

O projeto compila e roda. A impressora responde `PRINTER_UNAVAILABLE`, a tela de
diagnóstico mostra "Impressora indisponível" e a venda continua sendo
registrada normalmente — só o papel não sai, e a reimpressão fica disponível
(§3.4.3 da especificação da API).
