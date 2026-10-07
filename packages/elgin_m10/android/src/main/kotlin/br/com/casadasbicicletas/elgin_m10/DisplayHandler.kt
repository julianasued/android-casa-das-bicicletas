package br.com.casadasbicicletas.elgin_m10

import android.app.Activity
import android.graphics.BitmapFactory
import com.elgin.e1.Display.E1_Display
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Display do cliente de 2,4" (`com.elgin.e1.Display.E1_Display`).
 *
 * A sequência é `init` → `AbreConexaoDisplay` → `InicializaDisplay` → comandos,
 * e `DesconectarDisplay` ao encerrar. Internamente a E1 resolve para a
 * implementação M11, que faz bind no mesmo serviço AIDL da impressora
 * (`net.nyx.printerservice`) — é por isso que a falha típica de abertura é
 * "Serviço M11 indisponível", e é por isso que ela não acontece em emulador.
 *
 * O dispositivo é declarado como `M10_PRO` em vez de `AUTO`: o `AUTO` funciona
 * lendo propriedades de build, e depender disso é depender de um detalhe que
 * pode mudar entre firmwares.
 */
class DisplayHandler(private val executor: ElginExecutor) {

    private var initialized = false

    fun handle(call: MethodCall, result: MethodChannel.Result, activity: Activity?) {
        when (call.method) {
            "open" -> executor.run(result, activity) { act ->
                val device = deviceOf(call.argument<String>("device"))

                E1_Display.init(act, device)
                initialized = true

                checkElgin("AbreConexaoDisplay", E1_Display.AbreConexaoDisplay())
                checkElgin("InicializaDisplay", E1_Display.InicializaDisplay())
                null
            }

            "close" -> executor.run(result, activity) {
                checkElgin("DesconectarDisplay", E1_Display.DesconectarDisplay())
                initialized = false
                null
            }

            "reinitialize" -> executor.run(result, activity) {
                checkElgin("ReinicializaDisplay", E1_Display.ReinicializaDisplay())
                null
            }

            "showText" -> executor.run(result, activity) {
                requireOpen()
                val text = call.argument<String>("text").orEmpty()
                val color = call.argument<String>("color")

                if (color == null) {
                    checkElgin(
                        "ApresentaTexto",
                        E1_Display.ApresentaTexto(
                            text,
                            call.argument<Int>("a") ?: 0,
                            call.argument<Int>("b") ?: 0,
                            call.argument<Int>("c") ?: 0,
                        ),
                    )
                } else {
                    checkElgin(
                        "ApresentaTextoColorido",
                        E1_Display.ApresentaTextoColorido(
                            text,
                            call.argument<Int>("a") ?: 0,
                            call.argument<Int>("b") ?: 0,
                            call.argument<Int>("c") ?: 0,
                            call.argument<Int>("d") ?: 0,
                            color,
                        ),
                    )
                }
                null
            }

            "showQrCode" -> executor.run(result, activity) {
                requireOpen()
                checkElgin(
                    "ApresentaQrCode",
                    E1_Display.ApresentaQrCode(
                        call.argument<String>("data").orEmpty(),
                        call.argument<Int>("a") ?: 0,
                        call.argument<Int>("b") ?: 0,
                        call.argument<Int>("c") ?: 0,
                    ),
                )
                null
            }

            "showImage" -> executor.run(result, activity) {
                requireOpen()
                val bytes = call.argument<ByteArray>("bytes")
                    ?: throw IllegalArgumentException("bytes é obrigatório em showImage().")
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw IllegalArgumentException("Imagem inválida ou não decodificável.")

                checkElgin("ApresentaImagemDisplay", E1_Display.ApresentaImagemDisplay(bitmap))
                null
            }

            "setInverted" -> executor.run(result, activity) {
                checkElgin(
                    "SetModoInvertido",
                    E1_Display.SetModoInvertido(call.argument<Int>("mode") ?: 0),
                )
                null
            }

            "firmwareVersion" -> executor.run(result, activity) {
                E1_Display.ObtemVersaoFirmware()
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Mensagem melhor do que a do SDK quando se escreve antes de abrir.
     *
     * `ApresentaTexto` sem conexão devolve um código genérico; dizer o que
     * faltou poupa a investigação.
     */
    private fun requireOpen() {
        if (!initialized) {
            throw ElginException(
                -1,
                "display",
                "Display não inicializado: chame open() antes de apresentar conteúdo.",
            )
        }
    }

    private fun deviceOf(name: String?): E1_Display.DisplayDevices = when (name) {
        "AUTO" -> E1_Display.DisplayDevices.AUTO
        "PIX4" -> E1_Display.DisplayDevices.PIX4
        "TPRO" -> E1_Display.DisplayDevices.TPRO
        "M11" -> E1_Display.DisplayDevices.M11
        else -> E1_Display.DisplayDevices.M10_PRO
    }

    fun onActivityDetached() {
        initialized = false
    }
}
