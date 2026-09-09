package br.com.casadasbicicletas.vendas.platform

/**
 * Contrato da impressora térmica, do ponto de vista do aplicativo.
 *
 * O Flutter manda uma lista de comandos ("texto centralizado", "código de
 * barras", "QR Code") e não sabe como eles viram bytes. Esta interface é a
 * fronteira: trocar o SDK, o modelo do terminal ou o protocolo troca a
 * implementação e nada mais.
 *
 * Os valores dos enums abaixo espelham a documentação oficial da Elgin
 * (elgindevelopercommunity.github.io, módulo "Térmica" — group___m1.html), e a
 * tradução para os inteiros do SDK acontece só em [ElginThermalPrinter].
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

    /** Corte parcial do papel (`Corte`), avançando antes o número de linhas dado. */
    fun cut(advance: Int)

    /** Reinicializa a impressora e limpa o buffer (`InicializaImpressora`). */
    fun reset()

    /** Fecha a conexão. Usado pelo POC para testar reabertura após erro. */
    fun disconnect()
}

/**
 * Estado consultado da impressora.
 *
 * `StatusImpressora(param)` é consultado por assunto — 1 gaveta, 2 tampa,
 * 3 papel, 4 ejetor, 5 geral —, e não devolve um estado único. Esta classe
 * junta as consultas que interessam ao balcão em uma resposta só.
 */
data class PrinterState(
    val available: Boolean,
    val outOfPaper: Boolean,
    val coverOpen: Boolean = false,
    val detail: String = "",
    /** Retorno cru de `StatusImpressora`, por assunto, para diagnóstico. */
    val rawStatus: Map<String, Int> = emptyMap(),
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

/** Alinhamento de uma linha impressa (`posicao` de `ImpressaoTexto`). */
enum class PrintAlign(val sdkValue: Int) {
    LEFT(0),
    CENTER(1),
    RIGHT(2),
}

/**
 * Simbologias de `ImpressaoCodigoBarras`, com o código da documentação oficial.
 *
 * A tabela é do SDK, não uma escolha nossa: `2` é EAN-13 porque a Elgin
 * documenta `2` como JAN13/EAN13, e o comprimento aceito de cada uma também é
 * dela.
 */
enum class BarcodeSymbology(val sdkValue: Int) {
    UPCA(0),
    UPCE(1),
    EAN13(2),
    EAN8(3),
    CODE39(4),
    ITF(5),
    CODEBAR(6),
    CODE93(7),
    CODE128(8);

    companion object {
        fun fromName(name: String?): BarcodeSymbology =
            entries.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: CODE128
    }
}

/** Posição do texto legível sob o código de barras (`HRI`). */
enum class HriPosition(val sdkValue: Int) {
    ABOVE(1),
    BELOW(2),
    BOTH(3),
    NONE(4),
}

/**
 * Um comando de impressão vindo do Dart.
 *
 * O documento é montado no Dart (`document_layout.dart`); o que atravessa o
 * canal é sempre um destes. Comando desconhecido é erro de programação, não
 * configuração — por isso a lista é fechada.
 */
sealed class PrintCommand {

    data class Text(
        val value: String,
        val align: PrintAlign,
        val bold: Boolean,
        val underline: Boolean,
        val doubleHeight: Boolean,
        val doubleWidth: Boolean,
    ) : PrintCommand()

    data class Barcode(
        val data: String,
        val symbology: BarcodeSymbology,
        val height: Int,
        val width: Int,
        val hri: HriPosition,
    ) : PrintCommand()

    /** `ImpressaoQRCode(dados, tamanho 1..6, nivelCorrecao 1..4)`. */
    data class QrCode(
        val data: String,
        val size: Int,
        val correctionLevel: Int,
    ) : PrintCommand()

    /** Caminho de arquivo, como `ImprimeImagem` espera. */
    data class Image(val path: String) : PrintCommand()

    data class Feed(val lines: Int) : PrintCommand()

    data class Cut(val advance: Int) : PrintCommand()

    companion object {

        /** Lê o mapa que veio do `MethodChannel`, ignorando o que não reconhece. */
        fun fromMap(raw: Map<*, *>): PrintCommand? = when (raw["type"]) {
            "text" -> Text(
                value = raw["value"] as? String ?: "",
                align = alignOf(raw["align"] as? String),
                bold = raw["bold"] as? Boolean ?: false,
                underline = raw["underline"] as? Boolean ?: false,
                doubleHeight = raw["double_height"] as? Boolean ?: false,
                doubleWidth = raw["double_width"] as? Boolean ?: false,
            )

            "barcode" -> Barcode(
                data = raw["data"] as? String ?: "",
                symbology = BarcodeSymbology.fromName(raw["symbology"] as? String),
                height = (raw["height"] as? Number)?.toInt() ?: DEFAULT_BARCODE_HEIGHT,
                width = (raw["width"] as? Number)?.toInt() ?: DEFAULT_BARCODE_WIDTH,
                hri = hriOf(raw["hri"] as? String),
            )

            "qrcode" -> QrCode(
                data = raw["data"] as? String ?: "",
                size = (raw["size"] as? Number)?.toInt() ?: DEFAULT_QRCODE_SIZE,
                correctionLevel =
                    (raw["correction_level"] as? Number)?.toInt() ?: DEFAULT_QRCODE_CORRECTION,
            )

            "image" -> Image(path = raw["path"] as? String ?: "")
            "feed" -> Feed((raw["lines"] as? Number)?.toInt() ?: 1)
            "cut" -> Cut((raw["advance"] as? Number)?.toInt() ?: DEFAULT_CUT_ADVANCE)
            else -> null
        }

        private fun alignOf(value: String?): PrintAlign = when (value) {
            "center" -> PrintAlign.CENTER
            "right" -> PrintAlign.RIGHT
            else -> PrintAlign.LEFT
        }

        private fun hriOf(value: String?): HriPosition = when (value) {
            "above" -> HriPosition.ABOVE
            "both" -> HriPosition.BOTH
            "none" -> HriPosition.NONE
            else -> HriPosition.BELOW
        }

        private const val DEFAULT_BARCODE_HEIGHT = 60
        private const val DEFAULT_BARCODE_WIDTH = 2
        private const val DEFAULT_QRCODE_SIZE = 4
        private const val DEFAULT_QRCODE_CORRECTION = 2
        private const val DEFAULT_CUT_ADVANCE = 3
    }
}
