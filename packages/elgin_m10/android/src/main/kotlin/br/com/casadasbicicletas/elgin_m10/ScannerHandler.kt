package br.com.casadasbicicletas.elgin_m10

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.elgin.e1.Scanner.Scanner
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Leitor 1D/2D integrado (`com.elgin.e1.Scanner.Scanner`).
 *
 * O leitor não é chamado, ele dispara: o operador aperta o gatilho e a E1
 * entrega o código no `OnScanListener`. Daí o `EventChannel` — um `Future` não
 * representaria isso.
 *
 * Internamente a E1 registra um `BroadcastReceiver` na action
 * `com.android.NYX_QSC_DATA` e aciona a leitura pelo serviço NYX. Nada disso
 * aparece aqui de propósito: quem conhece o mecanismo é o SDK.
 *
 * A sobrecarga `iniciaScanner(boolean)` — leitura contínua — só existe a partir
 * da 02.34.04.
 */
class ScannerHandler(private val executor: ElginExecutor) : EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var activityProvider: () -> Activity? = { null }
    private var listening = false

    fun attachActivityProvider(provider: () -> Activity?) {
        activityProvider = provider
    }

    // -----------------------------------------------------------------------
    // EventChannel
    // -----------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val activity = activityProvider()
        if (activity == null) {
            events?.error(
                ElginError.NO_ACTIVITY,
                "Nenhuma Activity anexada: o leitor da E1 exige uma para iniciar.",
                null,
            )
            return
        }

        sink = events
        try {
            // O callback vem de uma thread do serviço do aparelho; o sink só
            // pode ser alimentado na main thread.
            Scanner.init(activity) { codigo ->
                mainHandler.post { sink?.success(codigo) }
            }
            listening = true
        } catch (error: Throwable) {
            events?.error(
                ElginError.SDK_MISSING,
                error.message ?: "Falha ao inicializar o leitor da E1.",
                null,
            )
        }
    }

    override fun onCancel(arguments: Any?) {
        stopScanner()
        sink = null
    }

    // -----------------------------------------------------------------------
    // MethodChannel
    // -----------------------------------------------------------------------

    fun handle(call: MethodCall, result: MethodChannel.Result, activity: Activity?) {
        when (call.method) {
            "start" -> executor.run(result, activity) {
                if (!listening) {
                    throw ElginException(
                        -1,
                        "scanner",
                        "Nenhum ouvinte no stream de leituras: assine onScan antes " +
                            "de chamar start().",
                    )
                }
                // `true` mantém o leitor ativo entre disparos; `false` é leitura
                // única, e exige nova chamada a cada bipe.
                Scanner.iniciaScanner(call.argument<Boolean>("continuous") ?: true)
                null
            }

            "stop" -> executor.run(result, activity) {
                Scanner.desativaScanner()
                null
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Desliga o leitor quando a Activity vai embora.
     *
     * Sem isto o receptor da E1 continua registrado contra uma Activity morta —
     * e, na volta do background, as leituras não chegam mais.
     */
    fun onActivityDetached() {
        stopScanner()
        listening = false
    }

    private fun stopScanner() {
        runCatching { Scanner.desativaScanner() }
    }
}
