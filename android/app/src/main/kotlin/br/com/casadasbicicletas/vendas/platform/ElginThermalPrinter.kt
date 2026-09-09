package br.com.casadasbicicletas.vendas.platform

import android.util.Log
import java.lang.reflect.Method

/**
 * Impressora térmica integrada do Elgin M10 Pro, pelo SDK E1 da Elgin.
 *
 * ## Por que reflexão
 *
 * O SDK da Elgin é distribuído como `.aar` pelo fabricante e **não** está em
 * repositório público — não há como declará-lo no Gradle e o binário não entra
 * no versionamento do projeto. Ligar as chamadas por reflexão resolve dois
 * problemas de uma vez: o aplicativo compila e roda em qualquer máquina sem o
 * `.aar`, e no terminal, onde o SDK existe, ele é encontrado em tempo de
 * execução. Sem SDK, cada chamada responde `PRINTER_UNAVAILABLE`, que é
 * exatamente o caso previsto no §11 da especificação de integração.
 *
 * ## Ao instalar o SDK
 *
 * Coloque o `.aar` da Elgin em `android/app/libs/` e confira as assinaturas em
 * [Sdk]: elas seguem a documentação do E1 Android SDK para o M10/PosGo, mas
 * variam entre versões do SDK. Se a impressão sair em branco ou o
 * `AbreConexaoImpressora` devolver erro, é aqui — e só aqui — que se ajusta.
 *
 * Nenhuma outra parte do aplicativo conhece esses nomes.
 */
class ElginThermalPrinter : ThermalPrinter {

    /**
     * Espelho das chamadas do SDK E1.
     *
     * Os nomes ficam em constantes, e não espalhados pelo código, porque é este
     * o ponto que muda quando a Elgin publica uma versão nova do SDK.
     */
    private object Sdk {
        const val CLASS_NAME = "com.elgin.e1.Impressora.Termica"

        const val OPEN = "AbreConexaoImpressora"
        const val CLOSE = "FechaConexaoImpressora"
        const val PRINT_TEXT = "ImpimeTexto"
        const val PRINT_BARCODE = "ImprimeCodigoBarras"
        const val FEED = "AvancaPapel"
        const val CUT = "Corte"
        const val STATUS = "StatusImpressora"

        /** Tipo de conexão da impressora interna do terminal. */
        const val CONNECTION_INTERNAL = 4

        /** Modelo declarado na abertura da conexão. */
        const val MODEL = "M10"

        /** `StatusImpressora` devolve 0 quando está tudo certo. */
        const val STATUS_OK = 0

        /** Código de falta de papel devolvido pelo SDK. */
        const val STATUS_OUT_OF_PAPER = 3

        /** CODE128 na tabela de simbologias do SDK. */
        const val BARCODE_CODE128 = 8

        /** Posição do texto legível abaixo do código de barras. */
        const val HRI_BELOW = 2
    }

    private val sdkClass: Class<*>? by lazy {
        runCatching { Class.forName(Sdk.CLASS_NAME) }
            .onFailure { Log.i(TAG, "SDK da impressora Elgin ausente neste aparelho.") }
            .getOrNull()
    }

    val isSdkPresent: Boolean get() = sdkClass != null

    // -----------------------------------------------------------------------
    // ThermalPrinter
    // -----------------------------------------------------------------------

    override fun status(): PrinterState {
        val sdk = sdkClass
            ?: return PrinterState(
                available = false,
                outOfPaper = false,
                detail = "SDK da impressora não instalado neste terminal.",
            )

        return try {
            openConnection(sdk)
            val code = invoke(sdk, Sdk.STATUS, arrayOf(Int::class.javaPrimitiveType!!), 0) as? Int
                ?: Sdk.STATUS_OK

            PrinterState(
                available = true,
                outOfPaper = code == Sdk.STATUS_OUT_OF_PAPER,
                detail = if (code == Sdk.STATUS_OK) "" else "Status do SDK: $code",
            )
        } catch (error: Throwable) {
            PrinterState(
                available = false,
                outOfPaper = false,
                detail = error.message ?: "Falha ao consultar a impressora.",
            )
        }
    }

    override fun print(commands: List<PrintCommand>) {
        val sdk = sdkClass ?: throw PrinterException(
            PrinterException.UNAVAILABLE,
            "Impressora indisponível: SDK não instalado neste terminal.",
        )

        // A conferência de papel acontece antes de escrever qualquer coisa: meio
        // documento impresso é pior do que nenhum, porque o cliente sai do
        // balcão com um papel incompleto na mão.
        val state = status()
        if (state.outOfPaper) {
            throw PrinterException(
                PrinterException.OUT_OF_PAPER,
                "Sem papel na impressora do terminal.",
            )
        }

        try {
            openConnection(sdk)
            commands.forEach { execute(sdk, it) }
        } catch (error: PrinterException) {
            throw error
        } catch (error: Throwable) {
            throw PrinterException(
                PrinterException.PRINT_FAILED,
                error.message ?: "Falha ao imprimir no terminal.",
                error,
            )
        } finally {
            runCatching { invoke(sdk, Sdk.CLOSE, emptyArray()) }
        }
    }

    override fun feed(lines: Int) {
        val sdk = sdkClass ?: throw PrinterException(
            PrinterException.UNAVAILABLE,
            "Impressora indisponível: SDK não instalado neste terminal.",
        )

        try {
            openConnection(sdk)
            invoke(sdk, Sdk.FEED, arrayOf(Int::class.javaPrimitiveType!!), lines)
        } catch (error: Throwable) {
            throw PrinterException(
                PrinterException.PRINT_FAILED,
                error.message ?: "Falha ao avançar o papel.",
                error,
            )
        } finally {
            runCatching { invoke(sdk, Sdk.CLOSE, emptyArray()) }
        }
    }

    // -----------------------------------------------------------------------
    // Tradução dos comandos
    // -----------------------------------------------------------------------

    private fun execute(sdk: Class<*>, command: PrintCommand) {
        when (command) {
            is PrintCommand.Text -> invoke(
                sdk,
                Sdk.PRINT_TEXT,
                arrayOf(
                    String::class.java,
                    Int::class.javaPrimitiveType!!,
                    Int::class.javaPrimitiveType!!,
                    Int::class.javaPrimitiveType!!,
                ),
                command.value + "\n",
                alignCode(command.align),
                styleCode(command),
                sizeCode(command),
            )

            is PrintCommand.Barcode -> invoke(
                sdk,
                Sdk.PRINT_BARCODE,
                arrayOf(
                    Int::class.javaPrimitiveType!!,
                    String::class.java,
                    Int::class.javaPrimitiveType!!,
                    Int::class.javaPrimitiveType!!,
                    Int::class.javaPrimitiveType!!,
                ),
                Sdk.BARCODE_CODE128,
                command.data,
                command.height,
                BARCODE_WIDTH,
                if (command.showText) Sdk.HRI_BELOW else 0,
            )

            is PrintCommand.Feed -> invoke(
                sdk,
                Sdk.FEED,
                arrayOf(Int::class.javaPrimitiveType!!),
                command.lines,
            )

            // O M10 Pro não tem guilhotina: o "corte" avança o papel o bastante
            // para o operador destacar na serrilha sem perder linha impressa.
            PrintCommand.Cut -> invoke(
                sdk,
                Sdk.CUT,
                arrayOf(Int::class.javaPrimitiveType!!),
                CUT_FEED_LINES,
            )
        }
    }

    private fun openConnection(sdk: Class<*>) {
        invoke(
            sdk,
            Sdk.OPEN,
            arrayOf(
                Int::class.javaPrimitiveType!!,
                String::class.java,
                String::class.java,
                Int::class.javaPrimitiveType!!,
            ),
            Sdk.CONNECTION_INTERNAL,
            Sdk.MODEL,
            "",
            0,
        )
    }

    private fun alignCode(align: PrintAlign): Int = when (align) {
        PrintAlign.LEFT -> 0
        PrintAlign.CENTER -> 1
        PrintAlign.RIGHT -> 2
    }

    private fun styleCode(command: PrintCommand.Text): Int = if (command.bold) 1 else 0

    private fun sizeCode(command: PrintCommand.Text): Int =
        if (command.doubleHeight) 2 else 1

    // -----------------------------------------------------------------------
    // Reflexão
    // -----------------------------------------------------------------------

    private val methods = mutableMapOf<String, Method>()

    private fun invoke(
        sdk: Class<*>,
        name: String,
        parameterTypes: Array<Class<*>>,
        vararg arguments: Any?,
    ): Any? {
        val method = methods.getOrPut(name) {
            sdk.getMethod(name, *parameterTypes)
        }
        return method.invoke(null, *arguments)
    }

    private companion object {
        const val TAG = "ElginThermalPrinter"
        const val BARCODE_WIDTH = 2
        const val CUT_FEED_LINES = 3
    }
}
