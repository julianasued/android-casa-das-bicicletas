/// Quando o catálogo guardado no terminal merece aviso (RF34, §13.9).
///
/// Sem rede, o preço que a tela mostra é o da última vez que aquele produto foi
/// consultado online. Se o catálogo mudou desde então, o vendedor fecha a venda
/// pelo preço velho e imprime o papel — e o servidor, ao receber, aplica o
/// preço de verdade. O aviso não impede a venda: dá ao vendedor a chance de
/// conferir antes de entregar a mercadoria.
library;

/// A partir de quando o catálogo local merece aviso.
///
/// Sete dias por decisão do dono (09/10/2026): catálogo de loja de bicicleta
/// muda devagar, avisar todo dia seria ruído que o vendedor aprende a ignorar,
/// e um mês já é tempo de o preço ter mudado sem ninguém notar.
const Duration idadeQueMereceAviso = Duration(days: 7);

/// Como a tela deve tratar a idade do catálogo em cache.
enum EstadoDoCatalogoLocal {
  /// Não há catálogo guardado: nada a dizer sobre idade.
  ausente,

  /// Recente o bastante para não atrapalhar.
  recente,

  /// Velho: merece aviso visível antes de fechar a venda.
  velho,
}

/// Classifica o catálogo guardado pela data da última atualização.
///
/// [agora] existe para o teste: data de referência injetável evita teste que
/// depende do relógio da máquina.
EstadoDoCatalogoLocal estadoDoCatalogoLocal(
  DateTime? atualizadoEm, {
  DateTime? agora,
}) {
  if (atualizadoEm == null) return EstadoDoCatalogoLocal.ausente;

  final referencia = agora ?? DateTime.now();
  final idade = referencia.difference(atualizadoEm);
  // `>=` e não `>`: sete dias cheios já é a fronteira anunciada ao dono.
  return idade >= idadeQueMereceAviso ? EstadoDoCatalogoLocal.velho : EstadoDoCatalogoLocal.recente;
}

/// Quantos dias inteiros o catálogo tem, para a frase do aviso.
int diasDeCatalogo(DateTime atualizadoEm, {DateTime? agora}) =>
    (agora ?? DateTime.now()).difference(atualizadoEm).inDays;
