package br.com.casadasbicicletas.vendas.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Leitor de código de barras integrado do M10.
 *
 * ## Situação: API oficial do M10 NÃO identificada
 *
 * A documentação da Elgin (`elgindevelopercommunity.github.io`) publica um
 * módulo "Scanner", mas ele está sob **Android › SmartPOS**, e descreve a API
 * `com.elgin.e1.Scanner.Scanner.getScanner(Context)`, que devolve um `Intent`
 * consumido por `startActivityForResult` e lido em `onActivityResult` pelo
 * extra `result`. Sob "Linha PosGo e M10" o único submódulo publicado é o da
 * impressora. **Não existe API de scanner documentada para o M10**, e supor que
 * a do SmartPOS vale aqui seria exatamente o tipo de suposição que este projeto
 * não pode fazer.
 *
 * Enquanto isso não for resolvido no aparelho físico, o canal escuta broadcasts
 * por um conjunto de ações **candidatas, não oficiais** — declaradas como tal em
 * [UNVERIFIED_ACTIONS] — e permite trocá-las em tempo de execução por
 * `configure`, sem nova versão do aplicativo. O método `probe` reúne o que o
 * aparelho responde, para que a resposta venha de teste e não de chute.
 *
 * O leitor também pode estar configurado em **modo teclado (HID)**: aí o código
 * chega como digitação, sem `Intent` nenhum, e quem trata é o lado Flutter
 * (`keyboard_wedge.dart`).
 */
class ScannerChannel(private val context: Context) : EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var actions: List<String> = UNVERIFIED_ACTIONS
    private var extraKeys: List<String> = UNVERIFIED_EXTRA_KEYS

    fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    fun detach() {
        unregisterReceiver()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        events = null
    }

    // -----------------------------------------------------------------------
    // MethodChannel
    // -----------------------------------------------------------------------

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                registerReceiver()
                result.success(null)
            }

            "stop" -> {
                unregisterReceiver()
                result.success(null)
            }

            "isAvailable" -> result.success(isScannerServiceAvailable())

            // Levanta, no aparelho, o que a documentação não responde.
            "probe" -> result.success(probe())

            "configure" -> {
                call.argument<List<String>>("actions")
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { actions = it }
                call.argument<List<String>>("extra_keys")
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { extraKeys = it }

                // Reassinar com a configuração nova: o receptor antigo continua
                // ouvindo ações que talvez não existam mais.
                if (receiver != null) {
                    unregisterReceiver()
                    registerReceiver()
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // -----------------------------------------------------------------------
    // EventChannel
    // -----------------------------------------------------------------------

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        registerReceiver()
    }

    override fun onCancel(arguments: Any?) {
        unregisterReceiver()
        events = null
    }

    // -----------------------------------------------------------------------
    // Broadcast do leitor
    // -----------------------------------------------------------------------

    private fun registerReceiver() {
        if (receiver != null) return

        val broadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val code = intent?.let(::extractCode) ?: return
                if (code.isBlank()) return

                val payload = mapOf(
                    "code" to code.trim(),
                    "symbology" to intent.extractSymbology(),
                    "read_at" to nowIso(),
                    "source" to "scanner",
                )
                mainHandler.post { events?.success(payload) }
            }
        }

        val filter = IntentFilter().apply { actions.forEach(::addAction) }

        // O broadcast do scanner é interno ao aparelho; a partir do Android 13 o
        // registro precisa dizer isso explicitamente.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(broadcastReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(broadcastReceiver, filter)
        }
        receiver = broadcastReceiver
    }

    private fun unregisterReceiver() {
        receiver?.let { runCatching { context.unregisterReceiver(it) } }
        receiver = null
    }

    /** Primeira chave de `extra` que trouxer texto — as demais são de outros firmwares. */
    private fun extractCode(intent: Intent): String? {
        extraKeys.forEach { key ->
            intent.getStringExtra(key)?.takeIf { it.isNotBlank() }?.let { return it }
            intent.getByteArrayExtra(key)
                ?.takeIf { it.isNotEmpty() }
                ?.let { return String(it, Charsets.UTF_8) }
        }
        return null
    }

    private fun Intent.extractSymbology(): String? =
        SYMBOLOGY_KEYS.firstNotNullOfOrNull { getStringExtra(it) }

    /**
     * Há serviço de leitura instalado no aparelho?
     *
     * A resposta é uma **indicação**, não uma garantia: se o leitor estiver em
     * modo teclado, não existe serviço a consultar e a leitura chega assim
     * mesmo. Por isso a tela do leitor continua aceitando digitação quando esta
     * checagem devolve `false`.
     */
    private fun isScannerServiceAvailable(): Boolean {
        val packageManager = context.packageManager
        return SCANNER_PACKAGES.any { name ->
            runCatching { packageManager.getPackageInfo(name, 0) }.isSuccess
        }
    }

    /**
     * Diagnóstico do leitor, para o POC responder com fato o que a documentação
     * deixa em aberto.
     *
     * Informa quais ações estão sendo escutadas, se algum pacote candidato de
     * serviço de scanner existe e se a classe do scanner **do SmartPOS** está
     * presente no aparelho. A última é a pergunta que decide o caminho: se ela
     * existir no M10, vale testar a API documentada; se não, o caminho é
     * broadcast ou modo teclado.
     */
    private fun probe(): Map<String, Any?> {
        val packageManager = context.packageManager

        val installedPackages = SCANNER_PACKAGES.filter { name ->
            runCatching { packageManager.getPackageInfo(name, 0) }.isSuccess
        }
        val smartPosClassPresent =
            runCatching { Class.forName(SMARTPOS_SCANNER_CLASS) }.isSuccess

        return mapOf(
            "listening" to (receiver != null),
            "actions" to actions,
            "extra_keys" to extraKeys,
            "scanner_packages_found" to installedPackages,
            "smartpos_scanner_class_present" to smartPosClassPresent,
            "smartpos_scanner_class" to SMARTPOS_SCANNER_CLASS,
            // A documentação oficial não publica API de scanner para o M10.
            "official_m10_api" to false,
            "detail" to "Ações escutadas são candidatas, não oficiais. " +
                "Confirme a ação real em Configurações → Scanner do M10 e " +
                "aplique-a por configure().",
        )
    }

    private fun nowIso(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private companion object {
        const val METHOD_CHANNEL = "br.com.casadasbicicletas.vendas/scanner"
        const val EVENT_CHANNEL = "br.com.casadasbicicletas.vendas/scanner/reads"

        /**
         * Ações candidatas do broadcast de leitura — **nenhuma confirmada** para
         * o M10 na documentação oficial.
         *
         * Vieram de padrões comuns do mercado, não da Elgin. Confirme a do
         * terminal em campo (Configurações → Scanner) e mande-a por `configure`
         * em vez de alterar esta lista.
         */
        val UNVERIFIED_ACTIONS = listOf(
            "com.elgin.scanner.ACTION_BARCODE",
            "com.elgin.e1.scanner.SCAN_RESULT",
            "android.intent.ACTION_DECODE_DATA",
            "scan.rcv.message",
        )

        /**
         * Chaves de `extra` candidatas — também **não confirmadas** para o M10.
         *
         * `result` é a única documentada pela Elgin, e para o SmartPOS.
         */
        val UNVERIFIED_EXTRA_KEYS = listOf(
            "result",
            "barcode",
            "barcode_string",
            "data",
            "scannerdata",
            "SCAN_BARCODE1",
            "value",
        )

        val SYMBOLOGY_KEYS = listOf("symbology", "barcode_type", "SCAN_BARCODE_TYPE")

        /** Pacotes candidatos de serviço de scanner — não confirmados. */
        val SCANNER_PACKAGES = listOf(
            "com.elgin.scanner",
            "com.elgin.e1.scanner",
        )

        /**
         * Classe do scanner **documentada para o SmartPOS**.
         *
         * Consultada apenas para saber se ela existe neste aparelho; nada é
         * chamado a partir dela enquanto não se confirmar que vale no M10.
         */
        const val SMARTPOS_SCANNER_CLASS = "com.elgin.e1.Scanner.Scanner"
    }
}
