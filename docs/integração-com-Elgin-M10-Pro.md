# Especificação de integração com o Elgin M10 Pro

## 1. Objetivo

Definir a integração entre o aplicativo Android do sistema e o hardware
do Elgin M10 Pro, incluindo impressora térmica integrada e leitor de
código de barras.

## 2. Equipamento

- Fabricante: Elgin
- Modelo: M10 Pro
- Part number: 46PGM1021600
- Sistema operacional: Android 11
- Impressora térmica integrada: 2"
- Leitor integrado: 1D/2D
- Conectividade: Wi-Fi, Bluetooth e 4G

## 3. Aplicação

O aplicativo Android será responsável pela interface de operação do
terminal e pela comunicação com a API Django.

A comunicação com o hardware deverá utilizar as bibliotecas/SDKs
oficiais disponibilizados pela Elgin para o M10/PosGo.

## 4. Impressora

O sistema deverá permitir:

- inicializar a impressora;
- verificar disponibilidade;
- imprimir texto;
- imprimir código de barras;
- imprimir os documentos da venda;
- imprimir o documento de retirada;
- detectar erros de impressão quando suportado;
- detectar falta de papel quando suportado;
- controlar avanço de papel.

A integração deverá utilizar o módulo de impressora térmica
disponibilizado pela Elgin para o M10.

## 5. Código de barras

O sistema deverá gerar um código de barras para identificar cada venda.

O código deverá conter um identificador único da venda.

O código será impresso na notinha entregue ao cliente.

No caixa, o leitor integrado deverá realizar a leitura do código e o
sistema deverá localizar automaticamente a venda correspondente.

## 6. Fluxo de leitura

1. Cliente apresenta a notinha.
2. Caixa realiza a leitura do código de barras.
3. Sistema identifica a venda.
4. Sistema apresenta os dados da venda.
5. Caixa confirma a venda.
6. Sistema registra a confirmação.
7. Sistema imprime o documento de retirada.

## 7. Documento de venda

O documento deverá conter, no mínimo:

- identificação da empresa;
- número/identificador da venda;
- data e hora;
- vendedor;
- itens;
- quantidade;
- valor dos itens;
- desconto, quando aplicável;
- valor total;
- forma de pagamento;
- código de barras da venda.

## 8. Documento de retirada

O segundo documento deverá conter:

- identificação da empresa;
- número da venda;
- data e hora;
- indicação de que a venda foi confirmada pelo caixa;
- identificação para retirada.

O documento será utilizado exclusivamente para retirada da compra.

## 9. Comunicação com a API

O aplicativo Android deverá se comunicar com a API Django através de
HTTPS.

O aplicativo não deverá acessar diretamente o banco de dados Django.

Toda comunicação deverá ocorrer através da API.

## 10. Funcionamento offline

O aplicativo deverá possuir armazenamento local para as operações que
forem permitidas durante a ausência de conexão.

As operações deverão ser sincronizadas posteriormente com a API.

## 11. Tratamento de erros

O aplicativo deverá tratar, no mínimo:

- impressora indisponível;
- falta de papel;
- falha de impressão;
- falha na leitura do código;
- venda inexistente;
- venda já processada;
- terminal não autorizado;
- API indisponível;
- falha de sincronização.

## 12. Segurança

A comunicação entre Android e Django deverá utilizar HTTPS.

O terminal deverá possuir uma credencial própria para autenticação.

A identificação do vendedor será realizada através da seleção do nome
na tela do terminal.

A seleção do vendedor não deverá conceder permissões administrativas.

## 13. Auditoria

As operações realizadas pelo terminal deverão registrar:

- loja;
- terminal;
- vendedor selecionado;
- operação;
- data/hora;
- identificador da operação.

Operações administrativas deverão registrar também o responsável pela
autorização.
