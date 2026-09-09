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
 * Leitor de código de barras integrado do M10 Pro.
 *
 * O leitor do terminal opera em um de dois modos, definidos na configuração do
 * próprio aparelho:
 *
 *  - **broadcast** — o serviço de scanner publica um `Intent` com o código
 *    lido. É o modo que este canal escuta.
 *  - **teclado (HID)** — o código chega como digitação, sem passar por
 *    `Intent` nenhum. Esse caso é tratado no lado Flutter
 *    (`keyboard_wedge.dart`), porque ali é onde os eventos de tecla chegam.
 *
 * As ações e as chaves de `extra` variam conforme o firmware e a configuração
 * do serviço de scanner. Em vez de fixar uma, o canal escuta um conjunto de
 * candidatas e aceita a primeira chave de `extra` que trouxer texto — e o Dart
 * pode substituir a lista em tempo de execução por `configure`, sem nova versão
 * do aplicativo.
 */
class ScannerChannel(private val context: Context) : EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var actions: List<String> = DEFAULT_ACTIONS
    private var extraKeys: List<String> = DEFAULT_EXTRA_KEYS

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

    private fun nowIso(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private companion object {
        const val METHOD_CHANNEL = "br.com.casadasbicicletas.vendas/scanner"
        const val EVENT_CHANNEL = "br.com.casadasbicicletas.vendas/scanner/reads"

        /**
         * Ações candidatas do broadcast de leitura.
         *
         * Confirme a do terminal em campo (Configurações → Scanner) e, se for
         * outra, mande-a pelo `configure` em vez de alterar esta lista.
         */
        val DEFAULT_ACTIONS = listOf(
            "com.elgin.scanner.ACTION_BARCODE",
            "com.elgin.e1.scanner.SCAN_RESULT",
            "android.intent.ACTION_DECODE_DATA",
            "scan.rcv.message",
        )

        /** Chaves de `extra` usadas pelos firmwares mais comuns. */
        val DEFAULT_EXTRA_KEYS = listOf(
            "barcode",
            "barcode_string",
            "data",
            "scannerdata",
            "SCAN_BARCODE1",
            "value",
        )

        val SYMBOLOGY_KEYS = listOf("symbology", "barcode_type", "SCAN_BARCODE_TYPE")

        /** Pacotes de serviço de scanner conhecidos nos terminais Elgin. */
        val SCANNER_PACKAGES = listOf(
            "com.elgin.scanner",
            "com.elgin.e1.scanner",
        )
    }
}
