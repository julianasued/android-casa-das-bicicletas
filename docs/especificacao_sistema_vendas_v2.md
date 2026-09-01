# Documento de Levantamento, Análise e Planejamento do Sistema

**Projeto:** Sistema de Gestão de Vendas e Caixa  
**Versão:** 1.0  
**Data:** 31/08/2026  
**Status:** Levantamento inicial

---

# 1. Levantamento e entendimento do problema

## 1.1 Contexto

O projeto consiste no desenvolvimento de um sistema de gestão de vendas integrado a terminais Android **Elgin M10 Pro**, destinado à operação de duas lojas.

O sistema deverá controlar o processo de venda desde o registro realizado pelo vendedor até o recebimento no caixa e, posteriormente, a retirada da compra pelo cliente.

O backend existente é desenvolvido em **Django** e deverá servir como base da solução, disponibilizando uma API para comunicação com os aplicativos Android.

Um requisito fundamental é o funcionamento **offline**, permitindo que as operações que forem tecnicamente possíveis continuem funcionando mesmo sem conexão com a internet. As operações realizadas offline deverão ser sincronizadas posteriormente com o servidor.

> **Importante:** o sistema não terá controle de estoque. Os produtos serão utilizados apenas para identificar e compor as vendas.

---

## 1.2 Problema a ser resolvido

O sistema deverá organizar e centralizar:

- vendas realizadas pelos vendedores;
- encaminhamento da venda para o caixa;
- recebimento e confirmação da venda;
- emissão do documento de retirada;
- cadastro de clientes;
- vendas em formato de notinha;
- controle de pendências de clientes;
- diferentes regras de comissão;
- cancelamentos;
- devoluções;
- solicitações de alteração de vendas;
- controle de acesso;
- operação de duas lojas;
- auditoria de todas as modificações relevantes;
- funcionamento offline e posterior sincronização.

O objetivo é reduzir erros operacionais, evitar alterações indevidas e permitir rastrear o histórico das operações.

---

# 1.3 Stakeholders

## Donos

Existem dois responsáveis com perfil de dono:

- Pai — proprietário;
- Usuário responsável pelo desenvolvimento/gestão do sistema.

O perfil de dono possui acesso administrativo máximo, incluindo as informações confidenciais de comissão.

## Gerentes

Responsáveis pela operação e gestão das lojas, incluindo autorizações de cancelamento e devolução.

## Vendedores

Responsáveis pelo atendimento e criação das vendas.

## Caixas

Responsáveis por localizar as vendas através do código de barras, receber o pagamento, confirmar a venda e emitir o documento de retirada.

## Clientes

Participam do processo de compra. Não possuem acesso direto ao sistema.

---

# 1.4 Usuários e permissões gerais

| Perfil | Principais responsabilidades |
|---|---|
| Dono | Administração completa, regras de comissão, relatórios e informações confidenciais |
| Gerente | Gestão operacional, cancelamentos e autorizações de devolução |
| Vendedor | Criação de vendas e notinhas |
| Caixa | Recebimento e confirmação de vendas |
| Cliente | Não possui acesso ao sistema |

O sistema deverá utilizar controle de acesso baseado em **perfis e permissões**.

---

# 1.5 Lojas

O sistema deverá suportar inicialmente **duas lojas**.

Cada operação deverá possuir vínculo com a loja correspondente.

As informações relevantes deverão registrar, quando aplicável:

- loja;
- usuário responsável;
- vendedor;
- caixa;
- data e hora;
- identificador da operação.

A arquitetura deverá permitir expansão para mais lojas no futuro.

---

# 1.6 Escopo

## Dentro do escopo

- autenticação;
- usuários;
- perfis e permissões;
- cadastro de lojas;
- cadastro de produtos;
- cadastro de clientes;
- registro de vendas;
- integração com M10 Pro;
- leitura de código de barras;
- impressão de documentos;
- operação de caixa;
- vendas em notinha;
- pendências de clientes;
- registro de pagamentos;
- regras de comissão;
- relatório de comissão para o dono;
- solicitação de alteração de vendas;
- aprovação/rejeição de alterações;
- cancelamento de vendas;
- devoluções;
- ajustes/estornos de comissão;
- auditoria;
- funcionamento offline;
- sincronização;
- relatórios operacionais.

## Fora do escopo inicial

O sistema **não possuirá controle de estoque**.

Não serão controlados:

- quantidade disponível em estoque;
- entrada de mercadorias;
- saída de mercadorias;
- inventário;
- estoque mínimo;
- transferência de estoque entre lojas.

Também não fazem parte do escopo inicial, salvo decisão posterior:

- TEF;
- NFC-e;
- NF-e;
- integração contábil;
- integração bancária;
- e-commerce;
- marketplace.

---

# 2. Análise e documentação

# 2.1 Requisitos funcionais

## RF01 — Autenticação

O sistema deverá permitir que os usuários realizem login utilizando suas credenciais.

---

## RF02 — Controle de acesso

O sistema deverá controlar o acesso às funcionalidades de acordo com o perfil e as permissões do usuário.

Permissões deverão ser verificadas no backend e, quando aplicável, também na interface do aplicativo.

---

## RF03 — Cadastro de lojas

Usuários autorizados deverão poder cadastrar e gerenciar as lojas.

---

## RF04 — Cadastro de produtos

O sistema deverá permitir cadastrar produtos para identificação e composição das vendas.

O cadastro poderá conter uma categoria utilizada para o cálculo de comissão.

As categorias inicialmente utilizadas para comissão serão:

- Peças;
- Pneus;
- Óleos.

O produto não terá controle de estoque.

---

## RF05 — Cadastro de clientes

O sistema deverá permitir cadastrar clientes e consultar informações relacionadas às suas vendas e pendências.

---

## RF06 — Criação de venda

O vendedor deverá poder criar uma venda adicionando produtos, quantidades e valores.

Cada venda deverá possuir **um único vendedor responsável**.

Não será permitido dividir uma mesma venda entre vendedores.

---

## RF07 — Identificação da venda

Cada venda deverá possuir um identificador único.

Esse identificador será utilizado na comunicação entre vendedor e caixa.

---

## RF08 — Documento de encaminhamento ao caixa

Após a criação/finalização da venda pelo vendedor, o sistema deverá gerar e imprimir o primeiro documento.

Esse documento deverá conter, entre outras informações relevantes:

- identificação da loja;
- identificação da venda;
- vendedor;
- produtos e valores;
- valor total;
- código de barras da venda.

O cliente levará esse documento até o caixa.

---

## RF09 — Leitura da venda pelo caixa

O caixa deverá possuir leitor de código de barras.

Ao ler o código presente no documento de encaminhamento, o sistema deverá localizar automaticamente a venda e apresentá-la na tela do caixa.

O caixa não deverá precisar digitar manualmente o número da venda.

---

## RF10 — Conferência e recebimento

O caixa deverá visualizar as informações da venda antes de confirmar o recebimento.

As formas de pagamento disponíveis serão:

- PIX;
- dinheiro;
- crédito;
- débito;
- notinha.

Haverá pagamento dividido.

A venda terá uma única forma de pagamento registrada.

---

## RF11 — Confirmação da venda

Após o caixa confirmar o recebimento, a venda deverá ser marcada como confirmada/paga.

O sistema deverá registrar:

- usuário do caixa;
- data e hora;
- loja;
- forma de pagamento;
- identificação da venda.

---

## RF12 — Documento de retirada

Após a confirmação do pagamento, o sistema deverá imprimir um **segundo documento**.

Esse documento será utilizado **exclusivamente para a retirada da compra**.

O primeiro documento não deverá ser considerado comprovante de pagamento.

O segundo documento somente deverá ser emitido após a confirmação da venda pelo caixa.

### Etapa de "compra retirada"

A existência de uma etapa específica para registrar que a mercadoria foi efetivamente retirada ainda está em definição.

Essa funcionalidade poderá ser adicionada posteriormente.

---

# 2.2 Vendas em notinha

## RF13 — Criação de notinha

O vendedor poderá criar uma venda utilizando a forma de pagamento **NOTINHA**.

A notinha será utilizada como controle interno e não terá finalidade fiscal.

---

## RF14 — Cliente obrigatório para notinha

Uma notinha deverá estar vinculada a um cliente cadastrado.

O sistema deverá criar uma pendência financeira vinculada ao cliente.

---

## RF15 — Controle de pendências

O sistema deverá permitir consultar as pendências de um cliente.

Deverá ser possível identificar:

- valor original;
- valor já pago, quando aplicável;
- valor pendente;
- data da venda;
- venda relacionada;
- status da pendência.

---

## RF16 — Pagamento de notinha

O caixa deverá poder registrar o pagamento de uma pendência.

A regra de liberação de comissão em caso de pagamento parcial ainda deverá ser definida.

### Regras em aberto

Deverá ser escolhida uma das alternativas:

1. liberar comissão proporcionalmente aos pagamentos realizados; ou
2. liberar a comissão somente após a quitação integral.

---

# 2.3 Comissão

## RF17 — Regra de comissão

A comissão será definida pelo **dono**.

A porcentagem de comissão poderá variar de acordo com:

- vendedor;
- categoria do produto.

As categorias inicialmente contempladas serão:

- Peças;
- Pneus;
- Óleos.

Exemplo:

| Vendedor | Peças | Pneus | Óleos |
|---|---:|---:|---:|
| Vendedor A | 5% | 3% | 4% |
| Vendedor B | 6% | 4% | 5% |

Os valores acima são apenas exemplos.

---

## RF18 — Sigilo da comissão

As informações de comissão serão **confidenciais**.

Somente usuários com perfil de **dono** poderão:

- visualizar percentuais;
- criar regras de comissão;
- alterar percentuais;
- visualizar valores de comissão;
- visualizar comissão por vendedor;
- visualizar comissão por venda;
- visualizar comissão por categoria;
- consultar histórico das alterações de comissão.

### Gerente

Não poderá visualizar:

- percentuais de comissão;
- valores de comissão;
- relatório de comissão.

### Vendedor

Não poderá visualizar:

- seu percentual de comissão;
- valores de comissão;
- comissão de outros vendedores.

### Caixa

Não poderá visualizar:

- percentuais de comissão;
- valores de comissão.

A restrição deverá ser aplicada no backend/API, não apenas escondendo informações na interface.

---

## RF19 — Comissão por item

A comissão deverá ser calculada e armazenada **por item da venda**, considerando o vendedor e a categoria do produto.

Exemplo:

```text
Venda #10482

Pneu
Valor: R$ 500,00
Comissão: 3%
Comissão gerada: R$ 15,00

Peças
Valor: R$ 1.000,00
Comissão: 5%
Comissão gerada: R$ 50,00
```

---

## RF20 — Preservação histórica da comissão

No momento em que a venda for registrada, o sistema deverá armazenar o percentual e o valor da comissão efetivamente utilizados em cada item.

Dessa forma, uma alteração futura da regra de comissão não deverá modificar vendas antigas.

Exemplo:

```text
01/08
João — Pneus = 3%

10/08
Dono altera:
João — Pneus = 4%

Venda realizada em 05/08
→ permanece com 3%

Venda realizada em 15/08
→ utiliza 4%
```

---

## RF21 — Comissão de venda paga

Em uma venda normal, a comissão deverá ser liberada conforme a confirmação do pagamento, respeitando as regras de negócio definidas.

---

## RF22 — Comissão de notinha

Em uma venda em notinha, a comissão inicialmente ficará pendente até que seja definida a regra para pagamentos parciais.

O sistema deverá permitir posteriormente implementar:

- comissão proporcional ao pagamento; ou
- comissão somente na quitação.

---

## RF23 — Relatório de comissão

O dono deverá poder consultar as comissões por período, vendedor e categoria.

Exemplo:

```text
Período: 01/08/2026 a 31/08/2026

Vendedor: João

Peças:
Vendas: R$ 20.000
Comissão: R$ 1.000

Pneus:
Vendas: R$ 15.000
Comissão: R$ 450

Óleos:
Vendas: R$ 5.000
Comissão: R$ 200

Total:
R$ 1.650
```

Não será obrigatório possuir um processo formal de "fechamento mensal" na primeira versão.

---

# 2.4 Alterações, cancelamentos e devoluções

## RF24 — Solicitação de alteração de venda

Vendedores não poderão alterar diretamente uma venda que já esteja em estado que impeça alterações.

Quando necessário, o vendedor deverá solicitar uma alteração.

A solicitação deverá conter:

- venda;
- usuário solicitante;
- data/hora;
- alteração solicitada;
- motivo;
- status.

---

## RF25 — Aprovação de alteração

Usuários autorizados poderão:

- aprovar;
- rejeitar.

A decisão deverá ser registrada na auditoria.

---

## RF26 — Cancelamento de venda

Somente:

- dono;
- gerente.

poderão cancelar uma venda.

O cancelamento deverá exigir um motivo.

O sistema deverá registrar a operação na auditoria.

---

## RF27 — Devolução

Somente:

- dono;
- gerente.

poderão autorizar devoluções.

A devolução deverá ser registrada e vinculada à venda original.

---

## RF28 — Ajuste de comissão após cancelamento/devolução

Quando uma venda for cancelada ou devolvida, o sistema deverá identificar a comissão relacionada e realizar o ajuste/estorno correspondente.

A operação deverá ser registrada na auditoria.

---

# 2.5 Auditoria

## RF29 — Auditoria completa

O sistema deverá possuir um mecanismo central de auditoria.

Toda alteração ou operação relevante deverá gerar um registro de auditoria.

Exemplos:

- criação de venda;
- alteração de venda;
- solicitação de alteração;
- aprovação;
- rejeição;
- cancelamento;
- devolução;
- pagamento;
- alteração de comissão;
- alteração de permissões;
- criação/alteração de usuário;
- login;
- operações relevantes realizadas offline;
- sincronização.

---

## RF30 — Dados da auditoria

Cada evento deverá registrar, quando aplicável:

- data/hora;
- usuário;
- perfil;
- loja;
- ação;
- entidade;
- identificador da entidade;
- dados anteriores;
- dados novos;
- motivo;
- dispositivo;
- IP;
- identificador único da operação.

---

## RF31 — Imutabilidade

Usuários não deverão poder apagar registros de auditoria.

Uma correção deverá gerar uma nova operação e um novo registro de auditoria.

---

## RF32 — Auditoria de comissão

Alterações nas regras de comissão deverão obrigatoriamente gerar auditoria.

Exemplo:

```text
Data: 10/08/2026 09:32

Usuário: Dono
Ação: ALTERAÇÃO DE COMISSÃO

Vendedor: João
Categoria: Pneus

Anterior: 3%
Novo: 4%
```

Essas informações também serão restritas ao dono.

---

# 2.6 Funcionamento offline

## RF33 — Operação offline

O aplicativo deverá continuar funcionando sem internet nas operações que forem tecnicamente possíveis.

As funcionalidades dependentes obrigatoriamente do servidor deverão ser identificadas e tratadas de forma adequada.

---

## RF34 — Armazenamento local

O aplicativo deverá possuir banco local para armazenar dados necessários à operação offline.

A tecnologia inicialmente prevista é **SQLite**.

---

## RF35 — Fila de sincronização

Operações realizadas offline deverão ser armazenadas em uma fila de sincronização.

Exemplo:

```text
Operação #001
Venda criada
Aguardando sincronização

Operação #002
Pagamento registrado
Aguardando sincronização
```

Quando a conexão retornar, o aplicativo deverá enviar as operações ao servidor.

---

## RF36 — Idempotência

O sistema deverá utilizar identificadores únicos para evitar que uma mesma operação seja processada mais de uma vez durante a sincronização.

---

## RF37 — Auditoria offline

Operações realizadas offline também deverão gerar registros de auditoria.

A auditoria deverá ser sincronizada posteriormente com o servidor, preservando a origem e os dados da operação.

---

# 3. Requisitos não funcionais

## RNF01 — Segurança

A comunicação entre aplicativo e servidor deverá utilizar HTTPS.

---

## RNF02 — Autorização

Todas as operações sensíveis deverão ser validadas no backend.

Não será suficiente ocultar botões ou informações na interface.

---

## RNF03 — Proteção das informações de comissão

As informações de comissão deverão possuir controle de acesso específico e ser disponibilizadas exclusivamente para o perfil de dono.

---

## RNF04 — Integridade

O sistema deverá evitar:

- vendas duplicadas;
- pagamentos duplicados;
- sincronizações duplicadas;
- cancelamentos indevidos;
- alteração não autorizada de vendas.

---

## RNF05 — Desempenho

A leitura do código de barras e localização da venda deverão ocorrer rapidamente, de modo a não prejudicar o atendimento no caixa.

---

## RNF06 — Disponibilidade

O sistema deverá suportar períodos de indisponibilidade da internet através do modo offline.

---

## RNF07 — Escalabilidade

A arquitetura deverá permitir a expansão de duas lojas para uma quantidade maior de lojas futuramente.

---

## RNF08 — Manutenibilidade

O código deverá ser organizado, versionado, testado e documentado.

---

# 4. Casos de uso principais

## UC01 — Realizar venda

```text
Vendedor
  ↓
Login
  ↓
Nova venda
  ↓
Seleciona produtos
  ↓
Finaliza venda
  ↓
Sistema gera identificador
  ↓
Imprime documento 1
  ↓
Cliente leva ao caixa
```

---

## UC02 — Receber venda

```text
Cliente apresenta documento
  ↓
Caixa escaneia código
  ↓
Sistema localiza venda
  ↓
Caixa confere venda
  ↓
Registra forma de pagamento
  ↓
Confirma recebimento
  ↓
Venda confirmada
  ↓
Imprime documento 2
  ↓
Cliente utiliza documento para retirada
```

---

## UC03 — Criar notinha

```text
Vendedor
  ↓
Seleciona cliente
  ↓
Cria venda
  ↓
Seleciona NOTINHA
  ↓
Sistema cria pendência
  ↓
Comissão fica pendente
```

---

## UC04 — Receber notinha

```text
Cliente paga
  ↓
Caixa localiza pendência
  ↓
Registra pagamento
  ↓
Pendência é atualizada
  ↓
Comissão segue a regra definida para pagamento
```

---

## UC05 — Solicitar alteração

```text
Vendedor
  ↓
Solicita alteração
  ↓
Informa motivo
  ↓
Gerente/Dono analisa
  ↓
Aprova ou rejeita
  ↓
Sistema registra auditoria
```

---

## UC06 — Cancelar venda

```text
Dono/Gerente
  ↓
Seleciona venda
  ↓
Solicita cancelamento
  ↓
Informa motivo
  ↓
Sistema cancela
  ↓
Comissão é ajustada
  ↓
Auditoria registrada
```

---

# 5. Critérios de aceitação

## CA01 — Criação de venda

**Dado** que o vendedor está autenticado,

**quando** finalizar uma venda,

**então** o sistema deverá gerar um identificador único e imprimir o documento de encaminhamento.

---

## CA02 — Leitura no caixa

**Dado** que existe uma venda aguardando recebimento,

**quando** o caixa escanear o código de barras,

**então** a venda deverá aparecer automaticamente na tela.

---

## CA03 — Confirmação

**Dado** que a venda foi localizada,

**quando** o caixa confirmar o pagamento,

**então** a venda deverá ser marcada como confirmada e o documento de retirada deverá ser impresso.

---

## CA04 — Notinha

**Dado** que o vendedor está criando uma venda,

**quando** selecionar NOTINHA,

**então** deverá existir um cliente vinculado e uma pendência deverá ser criada.

---

## CA05 — Comissão

**Dado** que o dono definiu uma regra de comissão,

**quando** uma venda for realizada,

**então** o sistema deverá calcular a comissão de cada item de acordo com o vendedor e a categoria do produto.

---

## CA06 — Sigilo

**Dado** que o usuário não possui perfil de dono,

**quando** consultar uma venda,

**então** o sistema não deverá fornecer percentual ou valor de comissão.

---

## CA07 — Alteração de comissão

**Dado** que o dono alterou uma regra,

**quando** uma nova venda for realizada,

**então** ela deverá utilizar a nova regra, enquanto vendas anteriores deverão manter o percentual armazenado no momento de sua realização.

---

## CA08 — Cancelamento

**Dado** que o usuário é vendedor ou caixa,

**quando** tentar cancelar uma venda,

**então** o sistema deverá negar a operação.

**Dado** que o usuário é dono ou gerente,

**quando** cancelar uma venda,

**então** o sistema deverá permitir a operação e registrar a auditoria.

---

## CA09 — Auditoria

**Dado** que uma operação relevante foi realizada,

**quando** ela for concluída,

**então** deverá existir um registro de auditoria contendo usuário, data/hora, operação e demais informações aplicáveis.

---

## CA10 — Offline

**Dado** que o dispositivo esteja sem internet,

**quando** o usuário realizar uma operação permitida offline,

**então** a operação deverá ser armazenada localmente e sincronizada posteriormente.

---

# 6. Viabilidade

## 6.1 Viabilidade técnica

O projeto é tecnicamente viável utilizando:

- Python;
- Django;
- Django REST Framework;
- PostgreSQL;
- Flutter;
- Android;
- SQLite;
- APIs REST;
- mecanismos de sincronização offline.

A maior complexidade técnica estará em:

- integração com o hardware do M10 Pro;
- impressão;
- leitura de código de barras;
- operação offline;
- sincronização;
- controle de conflitos;
- integridade das operações;
- auditoria;
- regras de comissão.

A ausência de controle de estoque reduz consideravelmente a complexidade do sistema.

---

# 6.2 Viabilidade de prazo e custo

O projeto possui complexidade **média/alta**.

Os principais fatores de complexidade são:

- aplicação Android;
- integração com M10 Pro;
- funcionamento offline;
- sincronização;
- múltiplas lojas;
- permissões;
- auditoria;
- comissão por vendedor e categoria;
- cancelamentos e devoluções.

A implementação deverá ser dividida em etapas.

---

# 6.3 Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Integração com M10 Pro | Alto | Validar SDK e hardware antes da implementação completa |
| Falha de sincronização | Alto | Fila local + operações idempotentes |
| Venda duplicada | Alto | Identificadores únicos e idempotência |
| Alteração indevida | Alto | Permissões + auditoria |
| Exposição de comissão | Alto | Autorização no backend |
| Erro de comissão | Alto | Regras centralizadas e armazenadas por item |
| Internet indisponível | Alto | Banco local e sincronização |
| Perda de dados locais | Alto | Sincronização e mecanismos de recuperação |
| Crescimento para mais lojas | Médio | Arquitetura multi-loja |
| Conflitos offline | Alto | Estratégia explícita de sincronização |

---

# 7. Arquitetura e design

# 7.1 Stack tecnológica

## Backend

- Python;
- Django;
- Django REST Framework;
- PostgreSQL.

## Aplicativo M10 Pro

- Flutter/Dart;
- Android;
- Kotlin para integrações nativas específicas quando necessário.

## Armazenamento offline

- SQLite.

## Comunicação

- API REST;
- HTTPS.

---

# 7.2 Arquitetura

Inicialmente será utilizado um **monólito modular Django**, evitando a complexidade de microsserviços.

```text
                         ┌──────────────────────┐
                         │       Django         │
                         │                      │
                         │ Autenticação         │
                         │ Usuários             │
                         │ Lojas                │
                         │ Produtos             │
                         │ Clientes             │
                         │ Vendas               │
                         │ Caixa                │
                         │ Pendências           │
                         │ Comissões            │
                         │ Auditoria            │
                         │ Sincronização        │
                         └──────────┬───────────┘
                                    │
                                REST API
                                    │
                   ┌────────────────┴────────────────┐
                   │                                 │
                   ▼                                 ▼
              M10 Loja 01                       M10 Loja 02
              Flutter/Android                   Flutter/Android
                   │                                 │
                 SQLite                            SQLite
```

---

# 7.3 Modelagem inicial

Entidades previstas:

```text
User
Role
Permission

Store

Product
ProductCategory
Customer

Sale
SaleItem

CashRegister
CashSession
Payment

Receivable
ReceivablePayment

CommissionRule
CommissionItem

SaleChangeRequest
SaleCancellation
SaleReturn

SyncOperation

AuditLog
```

A modelagem definitiva deverá ser elaborada antes da implementação das funcionalidades principais.

---

# 7.4 Modelo conceitual de comissão

A regra deverá considerar:

```text
Vendedor
    +
Categoria do Produto
    ↓
Regra de Comissão
    ↓
Percentual
```

Na venda:

```text
Venda
 ├── Item 1
 │    ├── Categoria
 │    ├── Valor
 │    ├── Percentual aplicado
 │    └── Comissão calculada
 │
 ├── Item 2
 │    ├── Categoria
 │    ├── Valor
 │    ├── Percentual aplicado
 │    └── Comissão calculada
 │
 └── ...
```

---

# 7.5 API

Exemplos de endpoints:

```text
POST   /api/auth/login/

GET    /api/products/
GET    /api/products/{id}/

POST   /api/customers/
GET    /api/customers/{id}/

POST   /api/sales/
GET    /api/sales/{id}/
POST   /api/sales/{id}/confirm/
POST   /api/sales/{id}/cancel/
POST   /api/sales/{id}/return/
POST   /api/sales/{id}/change-request/

GET    /api/cash/pending-sales/
POST   /api/cash/payments/

GET    /api/receivables/
POST   /api/receivables/{id}/payments/

GET    /api/commissions/
GET    /api/commission-rules/

POST   /api/sync/
```

Os endpoints de comissão deverão possuir autorização exclusiva para usuários com perfil de dono.

Os endpoints deverão possuir mecanismos de **idempotência** quando necessário.

---

# 8. Planejamento do projeto

## Sprint 1 — Fundação

- estrutura Django;
- PostgreSQL;
- autenticação;
- usuários;
- perfis;
- permissões;
- lojas.

## Sprint 2 — Produtos e clientes

- produtos;
- categorias;
- clientes;
- APIs.

## Sprint 3 — Vendas

- criação de venda;
- itens;
- vendedores;
- estados;
- identificadores;
- documento de encaminhamento.

## Sprint 4 — Aplicativo M10

- aplicativo Android;
- integração com M10;
- leitor;
- impressora;
- impressão do primeiro documento.

## Sprint 5 — Caixa

- leitura do código;
- consulta da venda;
- confirmação;
- formas de pagamento;
- impressão do segundo documento.

## Sprint 6 — Comissão

- regras por vendedor;
- categorias;
- cálculo por item;
- relatórios exclusivos do dono;
- histórico de regras.

## Sprint 7 — Notinhas

- clientes;
- pendências;
- recebimentos;
- comissão pendente.

## Sprint 8 — Alterações e cancelamentos

- solicitação;
- aprovação;
- rejeição;
- cancelamento;
- devolução;
- ajuste de comissão.

## Sprint 9 — Offline

- SQLite;
- fila de operações;
- sincronização;
- idempotência;
- tratamento de conflitos.

## Sprint 10 — Auditoria e testes

- auditoria;
- segurança;
- testes unitários;
- testes de integração;
- testes E2E;
- testes offline;
- testes de sincronização;
- testes no M10.

---

# 9. Infraestrutura e ambiente

## 9.1 Desenvolvimento

Ferramentas previstas:

```text
Python
Django
PostgreSQL
Flutter
Android Studio
Git
```

---

## 9.2 Ambientes

Deverão existir, preferencialmente:

- desenvolvimento;
- homologação;
- produção.

---

## 9.3 Controle de versão

Git será utilizado para controle do código.

Estratégia sugerida:

```text
main
develop
feature/*
fix/*
hotfix/*
```

Alterações importantes deverão passar por Pull Request e revisão.

---

# 9.4 CI/CD

Pipeline sugerido:

```text
Git Push
   ↓
Lint
   ↓
Testes
   ↓
Build
   ↓
Deploy
```

---

# 10. Definição de padrões

## 10.1 Backend

Utilizar:

- PEP 8;
- Black;
- Ruff;
- type hints quando aplicável;
- testes automatizados;
- migrations controladas.

---

## 10.2 Flutter

Utilizar:

- Dart Formatter;
- análise estática;
- arquitetura definida;
- separação entre interface, domínio e infraestrutura;
- testes automatizados.

---

## 10.3 Commits

Padrão sugerido:

```text
feat: adiciona criação de venda
fix: corrige cálculo de comissão
refactor: reorganiza serviço de vendas
test: adiciona testes de cancelamento
docs: atualiza documentação da API
```

---

# 11. Estratégia de testes

## Testes unitários

Deverão cobrir principalmente:

- cálculo de comissão;
- regras de comissão;
- estados de venda;
- cancelamento;
- devolução;
- pendências;
- pagamentos;
- permissões;
- sincronização.

---

## Testes de integração

Deverão validar:

- Django ↔ PostgreSQL;
- API ↔ aplicativo;
- venda ↔ caixa;
- pagamento ↔ comissão;
- offline ↔ sincronização;
- auditoria.

---

## Testes E2E

### Venda normal

```text
Vendedor
 ↓
Cria venda
 ↓
Imprime documento 1
 ↓
Caixa escaneia
 ↓
Recebe pagamento
 ↓
Confirma venda
 ↓
Imprime documento 2
```

### Notinha

```text
Vendedor
 ↓
Cria notinha
 ↓
Pendência
 ↓
Cliente paga
 ↓
Comissão segue regra definida
```

### Cancelamento

```text
Venda
 ↓
Cancelamento autorizado
 ↓
Venda cancelada
 ↓
Comissão ajustada
 ↓
Auditoria
```

---

# 12. Regras de negócio consolidadas

| Regra | Definição |
|---|---|
| Lojas | 2 inicialmente |
| Estoque | Não existe |
| Produtos | Utilizados para identificação/composição da venda |
| Vendedores por venda | Apenas 1 |
| Comissão | Varia por vendedor e categoria |
| Categorias de comissão | Peças, Pneus e Óleos |
| Quem define comissão | Somente dono |
| Quem visualiza comissão | Somente dono |
| Notinha | Permitida ao vendedor |
| Notinha | Controle interno |
| Cliente na notinha | Obrigatório |
| Pagamento | PIX, dinheiro, crédito, débito ou notinha |
| Pagamento dividido | Não |
| Cancelamento | Dono ou gerente |
| Devolução | Dono ou gerente |
| Papel 1 | Encaminhamento ao caixa |
| Papel 2 | Exclusivamente retirada |
| Cupom | Comprovante, não fiscal |
| Auditoria | Obrigatória |
| Auditoria apagável | Não |
| Offline | Operações tecnicamente possíveis |
| Comissão parcial de notinha | A definir |
| Etapa "compra retirada" | A definir |
| Fechamento mensal de comissão | Não obrigatório na V1 |

---

# 13. Requisitos anteriormente em aberto — definição

## 13.1 Pagamento parcial de notinha

Não será permitido pagamento parcial de uma notinha. Uma pendência deverá ser quitada integralmente em uma operação de pagamento.

## 13.2 Compra retirada

Não haverá uma terceira etapa obrigatória de "compra retirada" no sistema. Após a confirmação da venda pelo caixa, será emitido o documento destinado à retirada. A entrega será realizada pelo próprio vendedor responsável pela venda.

## 13.3 Desconto

O vendedor poderá conceder desconto. O valor registrado deverá representar o valor efetivamente vendido após o desconto. A comissão será calculada sobre o valor efetivamente vendido. Não será necessário registrar separadamente se houve desconto.

## 13.4 Devolução

A devolução somente poderá ser realizada mediante apresentação da notinha/documento de retirada entregue pelo caixa ao cliente. Sem esse documento, a devolução não poderá ser realizada. A autorização é restrita ao dono ou gerente. A operação deverá estar vinculada à venda original e gerar auditoria.

## 13.5 Devolução parcial

A devolução, inclusive quando envolver itens específicos da venda, exige o documento de retirada e autorização do dono ou gerente.

## 13.6 Alteração de venda

O vendedor poderá solicitar alteração de uma venda quando necessário. Os campos necessários poderão ser alterados mediante solicitação e aprovação. Alterações relevantes deverão registrar solicitante, data/hora, motivo, dados anteriores, novos dados, decisão e auditoria.

## 13.7 Formas de pagamento

As formas de pagamento serão PIX, dinheiro, crédito, débito e notinha. Não haverá pagamento dividido. Não será necessário registrar valor recebido ou troco.

## 13.8 Limite de notinha

Não haverá limite de crédito ou valor para notinhas na primeira versão. Futuramente poderão existir alertas para clientes com pendências de valor elevado, antigas ou numerosas.

## 13.9 Funcionamento offline

O sistema deverá funcionar offline nas operações que puderem ser executadas com segurança localmente. Poderão funcionar offline, quando os dados estiverem disponíveis: consulta de produtos e clientes, criação de vendas, descontos, cálculo, geração de identificador, impressão, consulta de dados sincronizados e armazenamento para sincronização.

Cancelamentos, autorizações de devolução, alterações de regras de comissão, permissões, usuários e operações administrativas sensíveis deverão exigir servidor sempre que possível.

Estados de sincronização: `PENDENTE_SINCRONIZACAO`, `SINCRONIZADO`, `ERRO_SINCRONIZACAO` e `CONFLITANTE`.

## 13.10 Sincronização

Operações offline serão armazenadas localmente e enviadas ao servidor quando a conexão retornar. Cada operação terá identificador único e o servidor deverá garantir idempotência.

## 13.11 Conflitos de sincronização

O servidor será a fonte de verdade. Alterações incompatíveis na mesma entidade não deverão ser sobrescritas silenciosamente nem resolvidas apenas por "última alteração vence". O conflito deverá ser marcado para resolução por usuário autorizado e a resolução deverá gerar auditoria.

## 13.12 Equipamento

O dispositivo alvo será o **Elgin M10 Pro, modelo 46PGM1021600**, Android 11, 2 GB de RAM, 64 GB de armazenamento, processador Octa-Core (2 A75 até 1,8 GHz + 6 A55 até 1,8 GHz), GPU Mali-G52, Bluetooth e USB. A integração deverá considerar leitor de código de barras, impressora integrada, armazenamento local, conectividade e APIs/SDKs disponibilizados para o equipamento.

## 13.13 Impressão

### Documento 1 — Encaminhamento ao caixa

Emitido após a finalização da venda pelo vendedor e contendo código de barras para identificação da venda.

### Documento 2 — Retirada

Emitido pelo caixa após a confirmação da venda e utilizado exclusivamente para retirada da compra.

## 13.14 Responsabilidade pela retirada

Não haverá etapa adicional de confirmação de retirada no sistema. O fluxo será: vendedor realiza venda → documento 1 → cliente vai ao caixa → caixa lê código → caixa confirma pagamento → documento 2 é impresso → cliente apresenta o documento → vendedor responsável pela venda entrega a compra.

---

# 14. Princípios do sistema

O desenvolvimento deverá seguir os seguintes princípios:

### Segurança

Informações sensíveis, principalmente comissão, deverão possuir acesso restrito.

### Rastreabilidade

Toda operação relevante deverá poder ser rastreada através da auditoria.

### Integridade

O sistema deverá evitar duplicidade, alterações indevidas e inconsistências.

### Offline-first para operações aplicáveis

A ausência de internet não deverá impedir as operações que puderem funcionar localmente.

### Histórico

Informações importantes que impactam o passado, como comissão, deverão preservar os valores utilizados no momento da operação.

### Simplicidade

O sistema não deverá implementar funcionalidades que não façam parte do processo real da loja.

---

# 15. Resumo do fluxo principal

```text
                         VENDA
                           │
                       VENDEDOR
                           │
                           ▼
                    Cria a venda
                           │
                           ▼
                 Imprime documento 1
                           │
                    Código de barras
                           │
                           ▼
                        CLIENTE
                           │
                           ▼
                         CAIXA
                           │
                  Escaneia o código
                           │
                           ▼
                  Venda aparece na tela
                           │
                    Confere a venda
                           │
                           ▼
                  Registra pagamento
                           │
                           ▼
                   Venda confirmada
                           │
                           ▼
                 Imprime documento 2
                           │
                           ▼
                    CLIENTE RETIRA
```

Para notinha:

```text
VENDEDOR
   ↓
Cria venda
   ↓
NOTINHA
   ↓
Cliente obrigatório
   ↓
Pendência criada
   ↓
Cliente paga posteriormente
   ↓
Pendência atualizada
   ↓
Comissão liberada conforme regra definida
```

Para alteração:

```text
VENDEDOR
   ↓
Solicita alteração
   ↓
Motivo
   ↓
DONO / GERENTE
   ↓
Aprova ou rejeita
   ↓
Auditoria
```

Para cancelamento:

```text
DONO / GERENTE
   ↓
Cancela
   ↓
Motivo obrigatório
   ↓
Venda cancelada
   ↓
Comissão ajustada
   ↓
Auditoria
```

---

# 16. Próximos documentos técnicos

Após a aprovação deste documento, recomenda-se produzir, nesta ordem:

1. **Diagrama de casos de uso**
2. **Diagrama ER / modelo de dados**
3. **Modelo de estados da venda**
4. **Modelo de estados da notinha**
5. **Modelo de comissão**
6. **Especificação completa da API**
7. **Fluxo de sincronização offline**
8. **Arquitetura do aplicativo Android**
9. **Especificação de integração com o M10 Pro**
10. **Protótipos das telas**
11. **Plano de testes**
12. **Plano de implantação**

---

# 17. Conclusão

O sistema será uma plataforma de gestão de vendas para duas lojas, integrada aos terminais M10 Pro, com operação de vendedores e caixas, suporte a vendas normais e notinhas, controle de pendências, comissões por vendedor e categoria, cancelamentos, devoluções, controle de acesso, auditoria e funcionamento offline.

O sistema **não terá controle de estoque**.

As informações de comissão serão tratadas como **confidenciais**, sendo definidas e visualizadas exclusivamente pelos donos.

A arquitetura inicial será baseada em **Django + Django REST Framework + PostgreSQL**, com aplicativo Android para os M10 Pro e armazenamento local para operação offline.

A auditoria, segurança, integridade das vendas e capacidade de operar offline serão requisitos fundamentais da solução.
