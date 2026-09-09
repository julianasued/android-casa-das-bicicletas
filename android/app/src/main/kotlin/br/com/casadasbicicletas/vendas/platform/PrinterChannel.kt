package br.com.casadasbicicletas.vendas.platform

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Canal da impressora térmica.
 *
 * Impressão é I/O de hardware e demora: numa bobina de 2" um documento de venda
 * leva bem mais que um quadro de animação. Rodar isso na thread principal
 * travaria a interface no exato momento em que o vendedor está com o cliente na
 * frente — daí o executor próprio, com a resposta devolvida na thread principal,
 * que é a única onde o `MethodChannel` pode responder.
 */
class PrinterChannel(
    private val printer: ThermalPrinter = ElginThermalPrinter(),
) {

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> runOnWorker(result) {
                val state = printer.status()
                mapOf(
                    "available" to state.available,
                    "out_of_paper" to state.outOfPaper,
                    "detail" to state.detail,
                )
            }

            "print" -> runOnWorker(result) {
                val raw = call.argument<List<*>>("commands").orEmpty()
                val commands = raw.mapNotNull { item ->
                    (item as? Map<*, *>)?.let(PrintCommand::fromMap)
                }
                printer.print(commands)
                null
            }

            "feed" -> runOnWorker(result) {
                printer.feed(call.argument<Int>("lines") ?: DEFAULT_FEED_LINES)
                null
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Executa fora da thread principal e devolve o resultado nela.
     *
     * A falha vira `PlatformException` com o código do [PrinterException], que é
     * o que o lado Dart usa para separar "sem papel" de "impressora ausente".
     */
    private fun runOnWorker(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: PrinterException) {
                mainHandler.post { result.error(error.errorCode, error.message, null) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error(
                        PrinterException.PRINT_FAILED,
                        error.message ?: "Falha na impressora.",
                        null,
                    )
                }
            }
        }
    }

    private companion object {
        const val CHANNEL_NAME = "br.com.casadasbicicletas.vendas/printer"
        const val DEFAULT_FEED_LINES = 3
    }
}
