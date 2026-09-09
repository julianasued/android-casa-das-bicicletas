package br.com.casadasbicicletas.elgin_m10

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Executa chamadas da E1 fora da thread principal, em fila.
 *
 * Duas razões para existir, e as duas são do SDK, não do Flutter.
 *
 * A primeira é bloqueio: imprimir uma via ou desenhar no display leva
 * dezenas ou centenas de milissegundos falando com o serviço do aparelho. Na
 * main thread isso trava a interface no exato momento em que o cliente está no
 * balcão. E o `MethodChannel.Result` só pode ser respondido na main thread —
 * daí o caminho de ida e volta.
 *
 * A segunda é o estado global: **todas** as classes da E1 são de métodos
 * estáticos. Não há instância, logo não há isolamento — duas chamadas
 * simultâneas mexem na mesma conexão. Uma fila de thread única resolve isso
 * pela ordem, sem lock espalhado por três handlers.
 */
class ElginExecutor {

    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Roda [block] na fila e responde o [result] na main thread.
     *
     * A Activity é conferida **antes** de entrar na fila: as três APIs da E1 a
     * exigem, e chamar sem ela é o erro mais comum desta integração. Devolver
     * `NO_ACTIVITY` para o Dart é infinitamente melhor que um NPE dentro do SDK.
     */
    fun run(
        result: MethodChannel.Result,
        activity: Activity?,
        block: (Activity) -> Any?,
    ) {
        if (activity == null) {
            result.error(
                ElginError.NO_ACTIVITY,
                "Nenhuma Activity anexada ao plugin. As APIs da E1 exigem uma " +
                    "Activity — a chamada não foi executada.",
                null,
            )
            return
        }

        worker.execute {
            val outcome = runCatching { block(activity) }
            mainHandler.post { outcome.deliver(result) }
        }
    }

    /** Converte o desfecho da chamada na resposta do canal. */
    private fun Result<Any?>.deliver(result: MethodChannel.Result) {
        onSuccess { value -> result.success(value) }
        onFailure { error -> result.error(error) }
    }

    private fun MethodChannel.Result.error(error: Throwable) {
        when (error) {
            is ElginException -> error(
                ElginError.SDK_ERROR,
                error.message,
                mapOf("code" to error.code, "operation" to error.operation),
            )

            is IllegalArgumentException -> error(
                ElginError.INVALID_ARGUMENT,
                error.message ?: "Argumento inválido.",
                null,
            )

            // O SDK não está no APK: acontece em emulador e em build sem os
            // AARs. É diferente de "o aparelho recusou" e a tela precisa saber.
            is NoClassDefFoundError, is ClassNotFoundException -> error(
                ElginError.SDK_MISSING,
                "SDK da Elgin ausente neste build. Confira os AARs em " +
                    "android/app/libs/.",
                null,
            )

            else -> error(
                ElginError.UNEXPECTED,
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    fun shutdown() {
        worker.shutdown()
    }
}

/** Códigos que o lado Dart traduz em exceção tipada. */
object ElginError {
    const val NO_ACTIVITY = "NO_ACTIVITY"
    const val SDK_ERROR = "ELGIN_SDK_ERROR"
    const val SDK_MISSING = "SDK_MISSING"
    const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
    const val UNEXPECTED = "UNEXPECTED"
}

/**
 * Retorno diferente de zero da E1.
 *
 * A convenção do SDK é `0` para sucesso e negativo para erro. O inteiro cru não
 * sobe para a interface: sobe esta exceção, que o Dart reconstrói como
 * `ElginException` com código e mensagem.
 */
class ElginException(
    val code: Int,
    val operation: String,
    override val message: String,
) : Exception(message)

/**
 * Confere o retorno de uma função da E1.
 *
 * Toda chamada passa por aqui. É a diferença entre "o comando foi enviado" e "o
 * comando funcionou" — sem isto, uma impressora sem papel devolveria sucesso
 * para o Dart e o defeito só apareceria no papel que não saiu.
 *
 * **Só valor negativo é erro.** A tabela `CodigoErro` do próprio AAR e a
 * documentação da Elgin listam `SUCESSO = 0` e todo o resto em faixas
 * negativas (-2 a -6 conexão, -41 a -44 escrita, -51 a -53 QRCode...); não
 * existe erro positivo. Algumas funções devolvem um positivo com significado
 * próprio — `ImpressaoTexto` devolve quantos bytes escreveu —, e tratar isso
 * como falha reprovava impressão que tinha dado certo.
 *
 * Conferido no M10 Pro em 09/2026: imprimir "CASA DAS BICICLETAS" devolve 20,
 * que são os 19 caracteres mais a quebra de linha. O texto fica no buffer da
 * impressora e sai no primeiro avanço de papel — tinha funcionado o tempo
 * todo. Como a POC abortava na primeira linha, o `feed`/`cut` do fim da
 * sequência nunca rodava e o papel parecia em branco.
 */
fun checkElgin(operation: String, code: Int): Int {
    if (code >= 0) return code
    throw ElginException(code, operation, "$operation falhou (código $code).")
}
