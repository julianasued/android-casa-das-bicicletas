package br.com.casadasbicicletas.vendas.platform

import android.content.Context
import android.hardware.display.DisplayManager
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Display do cliente (segunda tela de 2,4" do M10).
 *
 * ## Situação: PENDENTE DE VALIDAÇÃO
 *
 * A documentação oficial da Elgin (`elgindevelopercommunity.github.io`) **não
 * publica módulo algum para o display do cliente**: a lista de módulos tem
 * impressora, scanner (só do SmartPOS), SAT, balança, TEF, Pix e etiqueta — não
 * há display. O repositório oficial de exemplos traz um
 * `display-v02.00.00-release.aar` e um `DisplaySDK-2.2.0.jar`, mas nenhum
 * exemplo que os utilize e nenhuma API descrita.
 *
 * Por isso **nenhum comando, intent ou nome de classe é inventado aqui**. O que
 * este canal faz é o que dá para fazer com API padrão do Android e sem chute:
 * detectar se o aparelho expõe uma tela secundária, via [DisplayManager]. É uma
 * informação real e verificável no M10 físico, e é o primeiro dado que falta
 * para decidir o caminho da implementação:
 *
 *  - se o display aparecer como `Display` secundário, o caminho é uma
 *    `Presentation` do próprio Android, sem SDK da Elgin;
 *  - se não aparecer, o controle é proprietário e depende do `.aar` de display
 *    e da documentação correspondente, que precisam ser obtidos com a Elgin.
 *
 * Enviar conteúdo responde `DISPLAY_UNSUPPORTED` até que uma das duas coisas
 * seja confirmada no aparelho.
 */
class CustomerDisplayChannel(private val context: Context) {

    private var channel: MethodChannel? = null

    private val displayManager: DisplayManager?
        get() = context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> result.success(probe())

            "show", "clear" -> result.error(
                DISPLAY_UNSUPPORTED,
                "Controle do display do cliente ainda não implementado: a Elgin não " +
                    "publica API para ele. Pendente de validação no M10 físico.",
                null,
            )

            else -> result.notImplemented()
        }
    }

    /**
     * O que o Android enxerga de telas neste aparelho.
     *
     * A tela `DEFAULT_DISPLAY` é a principal; qualquer outra é candidata a ser o
     * display do cliente. Os nomes e ids vão crus para a tela do POC — é assim
     * que a dúvida vira resposta no aparelho, em vez de suposição no código.
     */
    private fun probe(): Map<String, Any?> {
        val displays = displayManager?.displays.orEmpty()

        val secondary = displays
            .filter { it.displayId != Display.DEFAULT_DISPLAY }
            .map { display ->
                mapOf(
                    "id" to display.displayId,
                    "name" to display.name,
                    "state" to display.state,
                )
            }

        return mapOf(
            "display_count" to displays.size,
            "has_secondary_display" to secondary.isNotEmpty(),
            "secondary_displays" to secondary,
            "sdk_available" to false,
            "detail" to if (secondary.isEmpty()) {
                "Nenhuma tela secundária exposta pelo Android. O controle do display " +
                    "depende do SDK proprietário da Elgin, ainda não documentado."
            } else {
                "Tela secundária detectada pelo Android: a implementação pode usar " +
                    "Presentation, a confirmar no aparelho."
            },
        )
    }

    private companion object {
        const val CHANNEL_NAME = "br.com.casadasbicicletas.vendas/customer_display"
        const val DISPLAY_UNSUPPORTED = "DISPLAY_UNSUPPORTED"
    }
}
