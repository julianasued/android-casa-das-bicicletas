package br.com.casadasbicicletas.vendas.platform

import android.app.Activity
import android.util.Log
import java.lang.reflect.Method

/**
 * Impressora térmica integrada do Elgin M10, pelo SDK E1 da Elgin.
 *
 * ## Fonte das constantes
 *
 * Tudo em [Sdk] foi conferido contra a documentação oficial da Elgin —
 * `elgindevelopercommunity.github.io`, módulo "Térmica" (`group___m1.html`) e
 * "Impressora do Mini PDV M10 e Linha PosGo" (`group__m80.html`) — e contra o
 * exemplo Flutter oficial do repositório `PDV_Android_M8_M10`.
 *
 * Duas coisas continuam **PENDENTES DE VALIDAÇÃO** e estão marcadas no código:
 *
 *  1. o método de inicialização (`setContext` no exemplo oficial, `setActivity`
 *     na lista de funções do módulo M10) — os dois são tentados, nessa ordem;
 *  2. o significado dos valores devolvidos por `StatusImpressora`, que a
 *     documentação não publica. Por isso **nada é deduzido** deles: o valor cru
 *     é repassado à tela do POC para ser mapeado no aparelho físico.
 *
 * ## Por que reflexão
 *
 * O `.aar` do E1 é distribuído pelo fabricante, não está em repositório público
 * e não é versionado aqui. Ligar as chamadas por reflexão faz o aplicativo
 * compilar e rodar em qualquer máquina sem o `.aar` e encontrar o SDK no
 * terminal, onde ele existe. Sem SDK, cada chamada responde
 * `PRINTER_UNAVAILABLE` — o caso previsto no §11 da especificação de integração.
 *
 * Quando o `.aar` estiver em `android/app/libs/`, trocar por chamadas diretas a
 * `com.elgin.e1.Impressora.Termica` é substituir o corpo de [invoke] e os
 * `invoke(...)` por chamadas estáticas; nada fora deste arquivo muda.
 */
class ElginThermalPrinter(
    private val activityProvider: () -> Activity? = { null },
) : ThermalPrinter {

    /**
     * Espelho das chamadas do SDK E1, conforme a documentação oficial.
     *
     * Os nomes e os códigos ficam aqui, e não espalhados pelo código, porque é
     * este o ponto que muda quando a Elgin publica uma versão nova do SDK.
     */
    private object Sdk {
        const val CLASS_NAME = "com.elgin.e1.Impressora.Termica"

        // Nomes conferidos em group___m1.html.
        const val OPEN = "AbreConexaoImpressora"
        const val CLOSE = "FechaConexaoImpressora"
        const val INIT = "InicializaImpressora"
        const val PRINT_TEXT = "ImpressaoTexto"
        const val PRINT_BARCODE = "ImpressaoCodigoBarras"
        const val PRINT_QRCODE = "ImpressaoQRCode"
        const val PRINT_IMAGE = "ImprimeImagem"
        const val FEED = "AvancaPapel"
        const val CUT = "Corte"
        const val STATUS = "StatusImpressora"

        // Inicialização — ver PENDENTE (1) no comentário da classe.
        const val SET_CONTEXT = "setContext"
        const val SET_ACTIVITY = "setActivity"

        /**
         * `tipo` de `AbreConexaoImpressora`: 1=USB, 2=RS232, 3=TCP/IP,
         * 4=Bluetooth, **5=impressoras embarcadas (Android)**.
         *
         * O exemplo oficial do M10 usa `AbreConexaoImpressora(5, "", "", 0)` —
         * modelo e conexão vazios, parâmetro zero.
         */
        const val CONNECTION_EMBEDDED = 5

        /** `param` de `StatusImpressora`: 1=gaveta, 2=tampa, 3=papel, 4=ejetor, 5=geral. */
        const val STATUS_DRAWER = 1
        const val STATUS_COVER = 2
        const val STATUS_PAPER = 3
        const val STATUS_GENERAL = 5

        /** Retorno das funções: 0 é sucesso; negativo é erro (`group__g1.html`). */
        const val SUCCESS = 0
    }

    /** Mensagens dos códigos de erro publicados em "Códigos de erro". */
    private object SdkErrors {
        val MESSAGES = mapOf(
            -2 to "Tipo de conexão inválido.",
            -3 to "Modelo de impressora não suportado.",
            -4 to "Porta de comunicação fechada.",
            -5 to "Dispositivo recusado: não é uma impressora Elgin.",
            -6 to "Conexão já ativa.",
            -41 to "Posição de impressão inválida.",
            -42 to "Estilo de texto inválido.",
            -43 to "Tamanho de texto inválido.",
            -44 to "Falha na escrita para a impressora.",
            -150 to "Falha ao iniciar o serviço da impressora.",
            -151 to "Falha ao carregar a biblioteca da impressora.",
            -9999 to "Erro desconhecido do SDK.",
        )

        fun describe(code: Int): String =
            MESSAGES[code] ?: "Erro $code retornado pelo SDK da impressora."
    }

    private val sdkClass: Class<*>? by lazy {
        runCatching { Class.forName(Sdk.CLASS_NAME) }
            .onFailure { Log.i(TAG, "SDK da impressora Elgin ausente neste aparelho.") }
            .getOrNull()
    }

    private var contextBound = false

    val isSdkPresent: Boolean get() = sdkClass != null

    // -----------------------------------------------------------------------
    // ThermalPrinter
    // -----------------------------------------------------------------------

    override fun status(): PrinterState {
        val sdk = sdkClass ?: return unavailableState()

        return try {
            connect(sdk)

            // A documentação publica o significado do **parâmetro**, não o dos
            // valores devolvidos. Então nada é deduzido aqui: os números vão
            // crus para a tela do POC, e o mapeamento sai do aparelho físico.
            val raw = mapOf(
                "paper" to querySafely(sdk, Sdk.STATUS_PAPER),
                "cover" to querySafely(sdk, Sdk.STATUS_COVER),
                "drawer" to querySafely(sdk, Sdk.STATUS_DRAWER),
                "general" to querySafely(sdk, Sdk.STATUS_GENERAL),
            )

            PrinterState(
                available = true,
                // PENDENTE DE VALIDAÇÃO: sem a tabela de retorno do
                // `StatusImpressora`, marcar "sem papel" seria adivinhação. O
                // POC existe justamente para levantar esses valores no M10.
                outOfPaper = false,
                coverOpen = false,
                detail = "Status bruto (a interpretar no M10): $raw",
                rawStatus = raw,
            )
        } catch (error: PrinterException) {
            PrinterState(available = false, outOfPaper = false, detail = error.message)
        } catch (error: Throwable) {
            PrinterState(
                available = false,
                outOfPaper = false,
                detail = error.message ?: "Falha ao consultar a impressora.",
            )
        }
    }

    override fun print(commands: List<PrintCommand>) {
        val sdk = requireSdk()

        try {
            connect(sdk)
            commands.forEach { execute(sdk, it) }
        } catch (error: PrinterException) {
            throw error
        } catch (error: Throwable) {
            throw PrinterException(
                PrinterException.PRINT_FAILED,
                error.message ?: "Falha ao imprimir no terminal.",
                error,
            )
        }
    }

    override fun feed(lines: Int) = single { sdk ->
        checked(Sdk.FEED, invoke(sdk, Sdk.FEED, arrayOf(INT), lines))
    }

    override fun cut(advance: Int) = single { sdk ->
        checked(Sdk.CUT, invoke(sdk, Sdk.CUT, arrayOf(INT), advance))
    }

    override fun reset() = single { sdk ->
        checked(Sdk.INIT, invoke(sdk, Sdk.INIT, emptyArray()))
    }

    /**
     * Fecha a conexão e esquece o vínculo de contexto.
     *
     * O POC precisa disto para provar a reabertura depois de um erro: a próxima
     * operação refaz `setContext` e `AbreConexaoImpressora` do zero.
     */
    override fun disconnect() {
        val sdk = sdkClass ?: return
        runCatching { invoke(sdk, Sdk.CLOSE, emptyArray()) }
        contextBound = false
    }

    // -----------------------------------------------------------------------
    // Tradução dos comandos
    // -----------------------------------------------------------------------

    private fun execute(sdk: Class<*>, command: PrintCommand) {
        when (command) {
            is PrintCommand.Text -> checked(
                Sdk.PRINT_TEXT,
                invoke(
                    sdk,
                    Sdk.PRINT_TEXT,
                    arrayOf(String::class.java, INT, INT, INT),
                    command.value + "\n",
                    command.align.sdkValue,
                    styleOf(command),
                    sizeOf(command),
                ),
            )

            is PrintCommand.Barcode -> checked(
                Sdk.PRINT_BARCODE,
                invoke(
                    sdk,
                    Sdk.PRINT_BARCODE,
                    arrayOf(INT, String::class.java, INT, INT, INT),
                    command.symbology.sdkValue,
                    command.data,
                    command.height,
                    command.width,
                    command.hri.sdkValue,
                ),
            )

            is PrintCommand.QrCode -> checked(
                Sdk.PRINT_QRCODE,
                invoke(
                    sdk,
                    Sdk.PRINT_QRCODE,
                    arrayOf(String::class.java, INT, INT),
                    command.data,
                    command.size,
                    command.correctionLevel,
                ),
            )

            is PrintCommand.Image -> checked(
                Sdk.PRINT_IMAGE,
                invoke(sdk, Sdk.PRINT_IMAGE, arrayOf(String::class.java), command.path),
            )

            is PrintCommand.Feed -> checked(
                Sdk.FEED,
                invoke(sdk, Sdk.FEED, arrayOf(INT), command.lines),
            )

            is PrintCommand.Cut -> checked(
                Sdk.CUT,
                invoke(sdk, Sdk.CUT, arrayOf(INT), command.advance),
            )
        }
    }

    /**
     * `stilo` de `ImpressaoTexto` é uma **soma de bits**, não um valor único:
     * 0=Fonte A, 1=Fonte B, 2=Sublinhado, 4=Reverso, 8=Negrito.
     */
    private fun styleOf(command: PrintCommand.Text): Int {
        var style = 0
        if (command.underline) style += STYLE_UNDERLINE
        if (command.bold) style += STYLE_BOLD
        return style
    }

    /**
     * `tamanho` combina altura e largura: altura de 0 a 8 (1x a 8x) somada à
     * largura, onde 16=2x, 32=3x, e assim por diante.
     */
    private fun sizeOf(command: PrintCommand.Text): Int {
        val height = if (command.doubleHeight) HEIGHT_2X else HEIGHT_1X
        val width = if (command.doubleWidth) WIDTH_2X else WIDTH_1X
        return height + width
    }

    // -----------------------------------------------------------------------
    // Conexão
    // -----------------------------------------------------------------------

    /**
     * Vincula o contexto e abre a conexão com a impressora embarcada.
     *
     * O vínculo de contexto é feito uma vez por conexão; a abertura é
     * idempotente do lado do SDK (`-6` significa "conexão já ativa" e é tratado
     * como sucesso).
     */
    private fun connect(sdk: Class<*>) {
        bindContext(sdk)

        val result = invoke(
            sdk,
            Sdk.OPEN,
            arrayOf(INT, String::class.java, String::class.java, INT),
            Sdk.CONNECTION_EMBEDDED,
            "",
            "",
            0,
        ) as? Int ?: Sdk.SUCCESS

        if (result != Sdk.SUCCESS && result != ALREADY_CONNECTED) {
            throw PrinterException(
                PrinterException.UNAVAILABLE,
                "Não foi possível abrir a impressora: ${SdkErrors.describe(result)}",
            )
        }
    }

    /**
     * Entrega a Activity ao SDK.
     *
     * PENDENTE DE VALIDAÇÃO: o exemplo Flutter oficial do M10 chama
     * `Termica.setContext(activity)`; a lista de funções do módulo M10 cita
     * `setActivity`. Os dois são tentados, nessa ordem, e a ausência de ambos
     * **não** interrompe — há versões do SDK que dispensam o vínculo, e falhar
     * aqui esconderia o erro real da abertura da conexão.
     */
    private fun bindContext(sdk: Class<*>) {
        if (contextBound) return

        val activity = activityProvider()
        if (activity == null) {
            Log.w(TAG, "Sem Activity para vincular ao SDK da impressora.")
            return
        }

        val bound = tryBind(sdk, Sdk.SET_CONTEXT, activity) ||
            tryBind(sdk, Sdk.SET_ACTIVITY, activity)

        if (!bound) {
            Log.w(
                TAG,
                "Nem ${Sdk.SET_CONTEXT} nem ${Sdk.SET_ACTIVITY} encontrados no SDK — " +
                    "confirmar o método de inicialização da versão instalada.",
            )
        }
        contextBound = bound
    }

    /**
     * Tenta o vínculo aceitando as assinaturas plausíveis.
     *
     * `Activity` é `Context`, e o SDK pode declarar o parâmetro de qualquer uma
     * das duas formas; procurar pelo nome do método e conferir o parâmetro
     * evita depender de qual delas a versão instalada usa.
     */
    private fun tryBind(sdk: Class<*>, methodName: String, activity: Activity): Boolean {
        val method = sdk.methods.firstOrNull { candidate ->
            candidate.name == methodName &&
                candidate.parameterTypes.size == 1 &&
                candidate.parameterTypes[0].isInstance(activity)
        } ?: return false

        return runCatching { method.invoke(null, activity) }
            .onFailure { Log.w(TAG, "Falha ao chamar $methodName no SDK.", it) }
            .isSuccess
    }

    private fun requireSdk(): Class<*> = sdkClass ?: throw PrinterException(
        PrinterException.UNAVAILABLE,
        "Impressora indisponível: SDK da Elgin não instalado neste terminal.",
    )

    private fun unavailableState() = PrinterState(
        available = false,
        outOfPaper = false,
        detail = "SDK da impressora não instalado neste terminal.",
    )

    /** Uma operação isolada: conecta, executa e deixa a conexão aberta. */
    private inline fun single(block: (Class<*>) -> Unit) {
        val sdk = requireSdk()
        try {
            connect(sdk)
            block(sdk)
        } catch (error: PrinterException) {
            throw error
        } catch (error: Throwable) {
            throw PrinterException(
                PrinterException.PRINT_FAILED,
                error.message ?: "Falha na operação da impressora.",
                error,
            )
        }
    }

    private fun querySafely(sdk: Class<*>, param: Int): Int =
        runCatching {
            invoke(sdk, Sdk.STATUS, arrayOf(INT), param) as? Int ?: Int.MIN_VALUE
        }.getOrDefault(Int.MIN_VALUE)

    /** Converte o retorno negativo do SDK na falha que a tela sabe explicar. */
    private fun checked(operation: String, result: Any?) {
        val code = result as? Int ?: return
        if (code >= Sdk.SUCCESS) return

        throw PrinterException(
            PrinterException.PRINT_FAILED,
            "$operation: ${SdkErrors.describe(code)}",
        )
    }

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
        val method = methods.getOrPut(name) { sdk.getMethod(name, *parameterTypes) }
        return method.invoke(null, *arguments)
    }

    private companion object {
        const val TAG = "ElginThermalPrinter"

        val INT: Class<*> = Int::class.javaPrimitiveType!!

        /** `-6` = "conexão já ativa": não é erro para quem só quer imprimir. */
        const val ALREADY_CONNECTED = -6

        // `stilo` de ImpressaoTexto (soma de bits).
        const val STYLE_UNDERLINE = 2
        const val STYLE_BOLD = 8

        // `tamanho` de ImpressaoTexto: altura 0..8, largura 16=2x.
        const val HEIGHT_1X = 0
        const val HEIGHT_2X = 1
        const val WIDTH_1X = 0
        const val WIDTH_2X = 16
    }
}
