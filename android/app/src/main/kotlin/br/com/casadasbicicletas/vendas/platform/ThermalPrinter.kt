package br.com.casadasbicicletas.vendas.platform

/**
 * Contrato da impressora térmica, do ponto de vista do aplicativo.
 *
 * O Flutter manda uma lista de comandos ("texto centralizado", "código de
 * barras", "avança papel") e não sabe como eles viram bytes. Esta interface é a
 * fronteira: trocar o SDK, o modelo do terminal ou o protocolo troca a
 * implementação e nada mais.
 */
interface ThermalPrinter {

    /** Estado atual do hardware, para a tela decidir o que prometer ao operador. */
    fun status(): PrinterState

    /**
     * Executa a sequência de comandos.
     *
     * Lança [PrinterException] com o código combinado com o Dart quando falha —
     * é o que permite a interface distinguir falta de papel (com solução no
     * balcão) de impressora ausente (sem solução ali).
     */
    fun print(commands: List<PrintCommand>)

    fun feed(lines: Int)
}

/** Estado consultado da impressora (§4 e §11 da integração com o M10 Pro). */
data class PrinterState(
    val available: Boolean,
    val outOfPaper: Boolean,
    val detail: String = "",
)

/** Falha de impressão com o código que o Dart traduz em mensagem ao operador. */
class PrinterException(
    val errorCode: String,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause) {

    companion object {
        const val UNAVAILABLE = "PRINTER_UNAVAILABLE"
        const val OUT_OF_PAPER = "OUT_OF_PAPER"
        const val PRINT_FAILED = "PRINT_FAILED"
    }
}

/** Alinhamento de uma linha impressa. */
enum class PrintAlign { LEFT, CENTER, RIGHT }

/**
 * Um comando de impressão vindo do Dart.
 *
 * A lista de tipos é fechada de propósito: o documento é montado no Dart
 * (`document_layout.dart`), e o que atravessa o canal é sempre uma destas
 * quatro coisas. Comando desconhecido é erro de programação, não configuração.
 */
sealed class PrintCommand {

    data class Text(
        val value: String,
        val align: PrintAlign,
        val bold: Boolean,
        val doubleHeight: Boolean,
    ) : PrintCommand()

    data class Barcode(
        val data: String,
        val height: Int,
        val showText: Boolean,
    ) : PrintCommand()

    data class Feed(val lines: Int) : PrintCommand()

    data object Cut : PrintCommand()

    companion object {

        /** Lê o mapa que veio do `MethodChannel`, ignorando o que não reconhece. */
        fun fromMap(raw: Map<*, *>): PrintCommand? = when (raw["type"]) {
            "text" -> Text(
                value = raw["value"] as? String ?: "",
                align = alignOf(raw["align"] as? String),
                bold = raw["bold"] as? Boolean ?: false,
                doubleHeight = raw["double_height"] as? Boolean ?: false,
            )

            "barcode" -> Barcode(
                data = raw["data"] as? String ?: "",
                height = (raw["height"] as? Number)?.toInt() ?: DEFAULT_BARCODE_HEIGHT,
                showText = raw["show_text"] as? Boolean ?: true,
            )

            "feed" -> Feed((raw["lines"] as? Number)?.toInt() ?: 1)
            "cut" -> Cut
            else -> null
        }

        private fun alignOf(value: String?): PrintAlign = when (value) {
            "center" -> PrintAlign.CENTER
            "right" -> PrintAlign.RIGHT
            else -> PrintAlign.LEFT
        }

        private const val DEFAULT_BARCODE_HEIGHT = 60
    }
}
