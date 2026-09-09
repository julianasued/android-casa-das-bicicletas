# Bibliotecas nativas do terminal

Esta pasta recebe os SDKs da **Elgin** para o M10/PosGo. Os arquivos não são
versionados: são binários proprietários, distribuídos pelo fabricante junto com
o terminal. O `.gitignore` do projeto ignora `*.aar` e `*.jar` aqui.

## Arquivos esperados

Nomes conforme o repositório oficial de exemplos da Elgin
([`PDV_Android_M8_M10`](https://github.com/ElginDeveloperCommunity/PDV_Android_M8_M10),
pasta `Exemplos/App_eXperience_Flutter/.../android/app/libs`):

| Arquivo | Para quê | Necessário agora? |
|---|---|---|
| `e1-V02.20.00-release.aar` | SDK E1 — impressora térmica (`com.elgin.e1.Impressora.Termica`) | **Sim** |
| `minipdvm8-v01.00.00-release.aar` | Camada do Mini PDV M8/M10 | **Sim** |
| `display-v02.00.00-release.aar` | Display do cliente (sem API pública documentada) | A avaliar |
| `satelgin-8.1.1-release.aar` | SAT fiscal | Não (fora do escopo) |
| `InterfaceAutomacao-v2.0.0.12.aar` | TEF | Não (fora do escopo) |

As versões acima são as do exemplo oficial na data desta análise. Use as que
vierem com o seu terminal.

## Como instalar

1. Obtenha o pacote do SDK E1 Android com a Elgin (portal do desenvolvedor ou
   suporte técnico do terminal).
2. Copie os `.aar` para esta pasta.
3. Rode `flutter build apk` — o Gradle já inclui `libs/*.aar` e `libs/*.jar`
   (`android/app/build.gradle`).
4. Confira as constantes de `ElginThermalPrinter.kt` (objeto `Sdk`) contra a
   versão recebida. Elas foram conferidas contra a documentação oficial
   (`group___m1.html`), mas variam entre versões do SDK.

## Sem os SDKs

O projeto compila e roda. A impressora responde `PRINTER_UNAVAILABLE`, a tela de
diagnóstico e a tela do POC mostram "Impressora indisponível", e a venda
continua sendo registrada normalmente — só o papel não sai, e a reimpressão fica
disponível (§3.4.3 da especificação da API).

## Pendências de validação no aparelho

- **Inicialização:** o exemplo oficial em Flutter chama `Termica.setContext(activity)`;
  a lista de funções do módulo M10 cita `setActivity`. O código tenta os dois,
  nessa ordem. Confirme qual existe na versão instalada.
- **`StatusImpressora`:** a documentação publica o significado do *parâmetro*
  (1 gaveta, 2 tampa, 3 papel, 4 ejetor, 5 geral), mas não o dos valores
  devolvidos. O POC mostra os números crus para que o mapeamento seja feito no
  M10 físico.
- **Corte:** `Corte(avanco)` é documentado como corte parcial. Confirmar se o
  M10 tem guilhotina ou se o comando apenas avança o papel.
