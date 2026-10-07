package br.com.casadasbicicletas.elgin_m10

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Ponte entre o Flutter e os periféricos internos do Elgin Mini PDV M10 Pro.
 *
 * ## Por que `ActivityAware`
 *
 * As três APIs da E1 — impressora, display e leitor — exigem uma `Activity`,
 * não um `Context` de aplicação. Um `FlutterPlugin` comum só recebe o
 * `applicationContext`, e é por isso que este implementa `ActivityAware`: é o
 * único jeito de obter a Activity e, principalmente, de **soltá-la** quando ela
 * é destruída.
 *
 * Chamar a E1 com `activity == null` é o erro mais comum desta integração.
 * Aqui isso nunca vira NPE: o [ElginExecutor] confere antes e devolve
 * `NO_ACTIVITY` ao Dart.
 *
 * ## Estado global
 *
 * Todas as classes da E1 são de métodos estáticos — não há instância, e
 * portanto não há isolamento entre chamadas. Um executor único, compartilhado
 * pelos três handlers, serializa tudo em uma thread só. É o que impede duas
 * operações de mexerem na mesma conexão ao mesmo tempo.
 */
class ElginM10Plugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler {

    private val executor = ElginExecutor()
    private val printer = PrinterHandler(executor)
    private val display = DisplayHandler(executor)
    private val scanner = ScannerHandler(executor)

    private var printerChannel: MethodChannel? = null
    private var displayChannel: MethodChannel? = null
    private var scannerChannel: MethodChannel? = null
    private var scannerEvents: EventChannel? = null

    private var activity: Activity? = null

    // -----------------------------------------------------------------------
    // FlutterPlugin
    // -----------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger

        printerChannel = MethodChannel(messenger, CHANNEL_PRINTER).also {
            it.setMethodCallHandler(this)
        }
        displayChannel = MethodChannel(messenger, CHANNEL_DISPLAY).also {
            it.setMethodCallHandler(this)
        }
        scannerChannel = MethodChannel(messenger, CHANNEL_SCANNER).also {
            it.setMethodCallHandler(this)
        }

        scanner.attachActivityProvider { activity }
        scannerEvents = EventChannel(messenger, CHANNEL_SCANNER_EVENTS).also {
            it.setStreamHandler(scanner)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        printerChannel?.setMethodCallHandler(null)
        displayChannel?.setMethodCallHandler(null)
        scannerChannel?.setMethodCallHandler(null)
        scannerEvents?.setStreamHandler(null)

        printerChannel = null
        displayChannel = null
        scannerChannel = null
        scannerEvents = null

        executor.shutdown()
    }

    // -----------------------------------------------------------------------
    // ActivityAware
    // -----------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    /**
     * A Activity foi embora — rotação, background ou fim da tela.
     *
     * Além de soltar a referência, os handlers precisam saber: o vínculo da
     * impressora com a Activity antiga não vale mais, e o receptor do leitor
     * ficaria registrado contra uma tela que não existe.
     */
    override fun onDetachedFromActivityForConfigChanges() = releaseActivity()

    override fun onDetachedFromActivity() = releaseActivity()

    private fun releaseActivity() {
        scanner.onActivityDetached()
        printer.onActivityDetached()
        display.onActivityDetached()
        activity = null
    }

    // -----------------------------------------------------------------------
    // Roteamento
    // -----------------------------------------------------------------------

    /**
     * Um handler por canal.
     *
     * Os três canais compartilham este `MethodCallHandler` e se distinguem pelo
     * prefixo do método (`printer.`, `display.`, `scanner.`), o que mantém um
     * ponto único de entrada — e um lugar só onde a Activity é lida.
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val separator = call.method.indexOf('.')
        if (separator <= 0) {
            result.notImplemented()
            return
        }

        val target = call.method.substring(0, separator)
        val method = call.method.substring(separator + 1)
        val forwarded = MethodCall(method, call.arguments)

        when (target) {
            "printer" -> printer.handle(forwarded, result, activity)
            "display" -> display.handle(forwarded, result, activity)
            "scanner" -> scanner.handle(forwarded, result, activity)
            else -> result.notImplemented()
        }
    }

    private companion object {
        const val CHANNEL_PRINTER = "elgin_m10/printer"
        const val CHANNEL_DISPLAY = "elgin_m10/display"
        const val CHANNEL_SCANNER = "elgin_m10/scanner"
        const val CHANNEL_SCANNER_EVENTS = "elgin_m10/scanner_events"
    }
}
