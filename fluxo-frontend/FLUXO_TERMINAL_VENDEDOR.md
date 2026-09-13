# IMPLEMENTAÇÃO DO FLUXO PRINCIPAL DO TERMINAL VENDEDOR — FLUTTER

Atue como desenvolvedor Flutter sênior + especialista em UI para terminais POS.

Quero implementar no aplicativo `android-casa-das-bicicletas` o fluxo principal de venda mostrado nas referências visuais fornecidas.

IMPORTANTE:

- As imagens/referências visuais devem ser tratadas como referência de layout e fluxo.
- Não inventar telas fora do fluxo.
- Não mexer no backend.
- Não alterar contratos de API.
- Não alterar regras de negócio do backend.
- Não mexer no projeto Django.
- Não fazer commit.
- Antes de alterar qualquer arquivo, leia a arquitetura Flutter existente.
- Preserve a Clean Architecture atual.
- Preserve `domain`, `data`, `presentation` e `platform`.
- Reutilize os casos de uso, entidades, repositories e serviços já existentes.
- Não criar lógica de negócio dentro dos widgets.

==================================================
1. OBJETIVO

Implementar o fluxo visual e funcional:

INÍCIO
→ SENHA DO TERMINAL
→ SELEÇÃO DE VENDEDOR
→ NOVA VENDA
→ CLIENTE
→ COMPOSIÇÃO DA VENDA
→ DESCONTO
→ FORMA DE PAGAMENTO
→ CONFIRMAÇÃO
→ IMPRESSÃO
→ FINALIZAÇÃO

O fluxo deve funcionar em Android e ser preparado para o Elgin M10 Pro.

==================================================
2. REFERÊNCIA VISUAL

As telas fornecidas devem ser usadas como referência principal de:

- hierarquia visual;
- posicionamento;
- espaçamento;
- tamanho dos botões;
- cores;
- tipografia;
- ícones;
- cabeçalho;
- rodapé;
- mensagens;
- estados de carregamento;
- confirmação;
- navegação.

Não copiar literalmente elementos que não façam sentido no Flutter atual.

Não transformar a referência em imagem de fundo.

Implementar a interface com widgets reais.

==================================================
3. TELA INICIAL

Criar/ajustar a tela inicial conforme a referência.

Elementos:

- logo Casa das Bicicletas;
- identificação do terminal;
- botão grande:
  `INICIAR VENDA`

O botão deve ser extremamente fácil de tocar.

Ao tocar:

→ abrir autenticação do terminal.

==================================================
4. SENHA DO TERMINAL

Tela:

`INSIRA A SENHA DO TERMINAL`

Subtítulo:

`Digite sua senha para acessar o sistema`

Elementos:

- campo de senha;
- máscara;
- botão/ícone de visualizar senha;
- teclado numérico/touch;
- apagar;
- limpar;
- confirmar;
- estado de carregamento;
- mensagem de erro.

Usar o fluxo de autenticação existente.

Não criar autenticação nova.

Após sucesso:

→ seleção de vendedor.

==================================================
5. SELEÇÃO DE VENDEDOR

Tela:

`SELECIONE O VENDEDOR`

Subtítulo:

`Toque no nome do vendedor para continuar`

Exibir vendedores disponíveis no terminal.

Cada vendedor:

- ícone;
- nome;
- botão grande;
- área de toque adequada ao M10.

Ao tocar:

→ selecionar vendedor;
→ criar/usar sessão de venda existente;
→ entrar em Nova Venda.

Não pedir senha do vendedor.

O vendedor apenas é selecionado.

==================================================
6. NOVA VENDA

Criar tela seguindo a referência.

Cabeçalho:

- menu;
- `NOVA VENDA`;
- vendedor atual;
- botão sair.

A tela deve permitir:

### Valor/composição

Registrar os itens da venda por categoria:

- PEÇAS
- PNEUS
- ÓLEO

Não criar catálogo obrigatório se o fluxo atual trabalha com entrada manual.

Seguir o domínio existente.

### Valor

Permitir registrar:

- valor;
- quantidade quando aplicável;
- composição;
- total.

Não usar float.

==================================================
7. CLIENTE

A venda pode ser sem cliente, exceto quando for NOTINHA.

Quando o usuário precisar selecionar cliente:

Abrir:

`BUSCAR CLIENTE`

Permitir pesquisa por:

- nome;
- telefone.

Mostrar resultados grandes e fáceis de tocar.

Ao selecionar cliente:

- mostrar cliente;
- mostrar suas pendências;
- usar o endpoint já existente;
- lembrar que o vendedor vê TODAS as pendências desse cliente na loja.

Mostrar algo como:

`Total em aberto`

e indicação de vencidas quando disponível pelo contrato existente.

Não criar regra nova de crédito.

==================================================
8. CADASTRAR CLIENTE

Quando não encontrar cliente:

permitir:

`CADASTRAR CLIENTE`

Campos conforme contrato atual do backend.

Não inventar obrigatoriedade adicional.

Após salvar:

→ retornar automaticamente para a venda;
→ cliente fica selecionado.

==================================================
9. FORMA DE PAGAMENTO

Seguir as referências.

Formas existentes:

- PIX
- DINHEIRO
- DÉBITO
- CRÉDITO
- NOTINHA

D1:

- máximo de 2 formas;
- pagamento dividido permitido.

Se usar duas formas:

- mostrar claramente os dois valores;
- total deve fechar exatamente.

Não permitir terceira forma.

==================================================
10. REGRA DO DESCONTO

Desconto máximo:

5%.

Regra especial:

Se houver cartão de CRÉDITO,
o desconto não pode permanecer.

Não remover desconto automaticamente.

Se a venda possuir desconto e o usuário tentar confirmar uma forma que inclua crédito:

→ exibir o erro retornado pelo backend;
→ explicar que é necessária alteração da venda;
→ oferecer o fluxo de solicitação de alteração já existente.

Não criar lógica paralela.

==================================================
11. NOTINHA

Quando pagamento = NOTINHA:

Exigir cliente.

Mostrar os dados necessários:

- cliente;
- data;
- prazo;
- observação opcional;
- valor;
- composição.

A referência visual mostra:

`DETALHES DA NOTINHA`

Manter essa organização.

Não implementar pagamento parcial.

Não criar limite de crédito.

==================================================
12. RESUMO DA VENDA

Manter um painel/resumo visual da venda.

Mostrar:

- valor total;
- forma de pagamento;
- composição;
- cliente quando existir;
- detalhes da notinha quando aplicável;
- desconto quando houver;
- valor final.

O resumo deve acompanhar as alterações em tempo real.

==================================================
13. BOTÃO FINAL

Usar ação principal equivalente a:

`GERAR VENDA E IMPRIMIR`

Ao pressionar:

1. validar venda;
2. validar regras locais;
3. enviar para o caso de uso existente;
4. persistir online/offline conforme arquitetura existente;
5. gerar documento 1;
6. enviar para impressão pelo serviço existente;
7. mostrar progresso.

Não duplicar impressão.

==================================================
14. VENDA FINALIZADA

Tela equivalente à referência:

`VENDA FINALIZADA!`

Mostrar:

- número da venda;
- valor;
- cliente;
- forma de pagamento;
- status;
- itens;
- indicação de documento gerado.

Disponibilizar as ações necessárias conforme o fluxo existente.

Não inventar WhatsApp se não existir funcionalidade real correspondente.

Se o botão estiver na referência mas a funcionalidade ainda não existir:
- manter desabilitado ou marcar como futuro;
- não criar fake.

==================================================
15. IMPRESSÃO

Tela de espera equivalente a:

`Aguarde a impressão da nota...`

Usar o `DocumentPrinter`/abstração existente.

Não chamar diretamente código Elgin nos widgets.

O fluxo deve funcionar com:

- FakeDocumentPrinter;
- impressora real M10.

Se a impressão falhar:

mostrar:

- mensagem clara;
- opção de tentar novamente;
- opção de continuar somente quando isso for seguro segundo o fluxo atual.

Não duplicar documento por retry.

==================================================
16. NOTINHA / DOCUMENTO

Após geração:

mostrar a mensagem de orientação equivalente à referência:

`Não esqueça de entregar a notinha para o cliente...`

Manter o usuário consciente de que o documento 1 acompanha o cliente até o caixa.

Não confundir documento 1 com documento 2.

==================================================
17. ESTADO OFFLINE

O fluxo de venda deve continuar respeitando o offline-first já existente.

Se estiver offline:

- criação de venda continua possível;
- operação entra na fila;
- usuário não deve receber indicação falsa de sincronização concluída;
- estado deve ser claramente apresentado.

IMPORTANTE:

Reembolso continua proibido offline.

==================================================
18. ESTADOS DE UI

Todas as telas devem tratar:

- loading;
- sucesso;
- erro;
- offline;
- retry;
- campos inválidos;
- transição;
- operação duplicada.

Não usar `pumpAndSettle` como solução para animações infinitas nos testes.

==================================================
19. NAVEGAÇÃO

Implementar o fluxo de forma previsível:

INICIAL
→ AUTENTICAÇÃO TERMINAL
→ VENDEDORES
→ NOVA VENDA
→ CLIENTE quando necessário
→ VENDA
→ FINALIZAÇÃO

Evitar navegação excessivamente aninhada.

Back deve:

- preservar rascunho quando apropriado;
- não perder venda acidentalmente;
- pedir confirmação quando houver dados relevantes.

==================================================
20. ARQUITETURA

Manter:

presentation
→ domain/use cases
→ repositories
→ data
→ remote/local

Widgets NÃO devem:

- chamar HTTP diretamente;
- manipular SQLite diretamente;
- calcular regras complexas;
- acessar MethodChannel diretamente.

==================================================
21. RESPONSIVIDADE PARA M10

O alvo principal é o Elgin M10 Pro.

Garantir:

- toque confortável;
- fonte legível;
- botões grandes;
- sem elementos cortados;
- sem overflow;
- teclado não cobrindo campos importantes;
- rolagem onde necessário.

Não projetar a tela para desktop como prioridade.

O desktop pode servir apenas para desenvolvimento/preview.

==================================================
22. TESTES

Adicionar/atualizar testes de widget para o fluxo.

Cobrir:

1. abrir venda;
2. autenticar terminal;
3. selecionar vendedor;
4. abrir nova venda;
5. buscar cliente;
6. cadastrar cliente;
7. selecionar cliente;
8. mostrar pendências;
9. criar venda sem cliente;
10. criar venda com notinha;
11. desconto 5%;
12. desconto + crédito → bloqueio;
13. duas formas de pagamento;
14. terceira forma → bloqueio;
15. gerar venda;
16. impressão;
17. erro de impressão;
18. retry;
19. offline;
20. venda finalizada.

Não criar testes frágeis baseados em tempos arbitrários.

==================================================
23. INTEGRAÇÃO COM BACKEND

Usar os contratos existentes.

Em especial:

- `/auth/terminal/`
- `/auth/terminal/sellers/`
- `/auth/select-seller/`
- `/customers/`
- `/customers/{id}/receivables/`
- `/sales/`
- `/sales/by-barcode/`
- `/cash/payments/`
- `/sales/{id}/change-request/`

Não alterar o backend para facilitar o frontend.

==================================================
24. ERROS DO SYNC

O backend retorna:

`error: {code, message}`

O app atualmente possui uma divergência nesse contrato.

Corrigir no Flutter quando chegar nessa parte:

o mapper deve aceitar o formato real do backend.

Não alterar backend.

==================================================
25. AUDIT_BATCH

Não inventar produtor de auditoria offline nesta etapa caso ele ainda não exista.

A venda offline deve continuar seguindo o mecanismo atual.

Registrar como pendência de integração se necessário.

==================================================
26. CRITÉRIO VISUAL

Comparar as telas implementadas lado a lado com as referências.

Verificar:

- proporções;
- hierarquia;
- espaçamento;
- alinhamento;
- cores;
- tamanhos dos botões;
- textos;
- estados.

Não buscar uma cópia pixel-perfect se isso prejudicar usabilidade no M10.

==================================================
27. NÃO FAZER

Não implementar:

- CashSession;
- abertura/fechamento de caixa;
- relatórios administrativos;
- comissão administrativa;
- reembolso;
- novas regras de negócio;
- catálogo diferente do contrato existente;
- integração fiscal.

==================================================
28. VALIDAÇÃO

Executar:

flutter pub get
flutter test
dart analyze

Se `flutter analyze` falhar exclusivamente pelo problema já conhecido do caminho `Área de trabalho`, registrar e usar `dart analyze` como validação principal.

Também gerar:

flutter build apk --debug

Não fazer commit.

==================================================
29. RELATÓRIO FINAL

Informar:

1. telas implementadas;
2. fluxo completo;
3. arquivos alterados;
4. casos de uso reutilizados;
5. APIs utilizadas;
6. integração de impressão;
7. comportamento offline;
8. testes;
9. resultado do `flutter test`;
10. resultado do `dart analyze`;
11. resultado do APK;
12. qualquer função visual das referências que ficou propositalmente sem ação por não existir backend correspondente.

Não alterar backend.

Não fazer commit.