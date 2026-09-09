package br.com.casadasbicicletas.elgin_m10

import android.app.Activity
import android.graphics.BitmapFactory
import com.elgin.e1.Impressora.Termica
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Impressora térmica interna do M10 Pro (`com.elgin.e1.Impressora.Termica`).
 *
 * ## Abertura da conexão
 *
 * Os quatro parâmetros de `AbreConexaoImpressora` vêm do Dart, com padrão
 * `(6, "M8", "", 0)`. O padrão é configurável de propósito: a documentação
 * pública da Elgin descreve `tipo` de 1 a 5 — com 5 para impressoras embarcadas
 * — e o exemplo oficial em Flutter do M8/M10 usa `(5, "", "", 0)`. O valor 6 não
 * aparece na documentação pública, mas é o indicado para o pacote 02.34.04.
 *
 * Como o bytecode do AAR dá a assinatura mas não os valores aceitos, quem
 * decide é o aparelho — e em 09/2026 o M10 Pro decidiu: `(6, "M8")` conecta. Deixar os quatro parâmetros abertos permite tentar a
 * outra combinação sem recompilar — e evita fixar no código um número que
 * ninguém conseguiu confirmar.
 *
 * O literal `"M8"` como modelo está correto para a família Mini PDV, M10
 * incluído.
 */
class PrinterHandler(private val executor: ElginExecutor) {

    /**
     * Vínculo com a Activity feito uma vez por sessão.
     *
     * `setContext` e `setActivity` existem os dois no SDK 02.34.04 (conferido no
     * bytecode). Os dois são chamados: o segundo é o que as APIs exigem, e o
     * primeiro é usado internamente pela E1 em alguns caminhos.
     */
    private var boundActivity: Activity? = null

    fun handle(call: MethodCall, result: MethodChannel.Result, activity: Activity?) {
        when (call.method) {
            "open" -> executor.run(result, activity) { act ->
                bind(act)
                val type = call.argument<Int>("type") ?: DEFAULT_CONNECTION_TYPE
                val model = call.argument<String>("model") ?: DEFAULT_MODEL
                val connection = call.argument<String>("connection").orEmpty()
                val parameter = call.argument<Int>("parameter") ?: 0

                // `CONEXAO_ATIVA` não é falha: já estar aberta é o resultado
                // desejado. As classes da E1 são estáticas, então a conexão
                // pertence ao processo e sobrevive à tela que a abriu — depois
                // de uma troca de tela, reabrir devolvia -6 e a impressora
                // "sumia" no meio do atendimento.
                val code = Termica.AbreConexaoImpressora(type, model, connection, parameter)
                if (code != CONEXAO_ATIVA) {
                    checkElgin("AbreConexaoImpressora($type, \"$model\")", code)
                }
                null
            }

            "close" -> executor.run(result, activity) {
                checkElgin("FechaConexaoImpressora", Termica.FechaConexaoImpressora())
                boundActivity = null
                null
            }

            "initialize" -> executor.run(result, activity) {
                checkElgin("InicializaImpressora", Termica.InicializaImpressora())
                null
            }

            "printText" -> executor.run(result, activity) {
                val data = call.argument<String>("text").orEmpty()
                checkElgin(
                    "ImpressaoTexto",
                    Termica.ImpressaoTexto(
                        data,
                        call.argument<Int>("align") ?: 0,
                        call.argument<Int>("style") ?: 0,
                        call.argument<Int>("size") ?: 0,
                    ),
                )
                null
            }

            "printBarcode" -> executor.run(result, activity) {
                checkElgin(
                    "ImpressaoCodigoBarras",
                    Termica.ImpressaoCodigoBarras(
                        call.argument<Int>("type") ?: 8,
                        call.argument<String>("data").orEmpty(),
                        call.argument<Int>("height") ?: 60,
                        call.argument<Int>("width") ?: 2,
                        call.argument<Int>("hri") ?: 2,
                    ),
                )
                null
            }

            "printQrCode" -> executor.run(result, activity) {
                checkElgin(
                    "ImpressaoQRCode",
                    Termica.ImpressaoQRCode(
                        call.argument<String>("data").orEmpty(),
                        call.argument<Int>("size") ?: 4,
                        call.argument<Int>("correction") ?: 0,
                    ),
                )
                null
            }

            // Bitmap direto, sem arquivo temporário: o SDK aceita `Bitmap`, e
            // escrever no disco para depois ler de volta só acrescentaria uma
            // permissão e um ponto de falha.
            "printImage" -> executor.run(result, activity) {
                checkElgin("ImprimeImagem", Termica.ImprimeImagem(decodeBitmap(call)))
                null
            }

            "feed" -> executor.run(result, activity) {
                checkElgin("AvancaPapel", Termica.AvancaPapel(call.argument<Int>("lines") ?: 1))
                null
            }

            "cut" -> executor.run(result, activity) {
                val advance = call.argument<Int>("feed") ?: 0
                val full = call.argument<Boolean>("full") ?: false
                if (full) {
                    checkElgin("CorteTotal", Termica.CorteTotal(advance))
                } else {
                    checkElgin("Corte", Termica.Corte(advance))
                }
                null
            }

            // `StatusImpressora` é consultado por assunto e a Elgin não publica
            // a tabela de retorno. O valor cru sobe para o Dart em vez de ser
            // interpretado aqui: o mapeamento sai do teste no aparelho.
            "status" -> executor.run(result, activity) {
                mapOf(
                    "drawer" to Termica.StatusImpressora(STATUS_DRAWER),
                    "cover" to Termica.StatusImpressora(STATUS_COVER),
                    "paper" to Termica.StatusImpressora(STATUS_PAPER),
                    "ejector" to Termica.StatusImpressora(STATUS_EJECTOR),
                    "general" to Termica.StatusImpressora(STATUS_GENERAL),
                )
            }

            "raw" -> executor.run(result, activity) {
                val bytes = call.argument<ByteArray>("bytes")
                    ?: throw IllegalArgumentException("bytes é obrigatório em raw().")
                checkElgin("DirectIO", Termica.DirectIO(bytes, bytes.size))
                null
            }

            "beep" -> executor.run(result, activity) {
                checkElgin(
                    "SinalSonoro",
                    Termica.SinalSonoro(
                        call.argument<Int>("times") ?: 1,
                        call.argument<Int>("onMs") ?: 100,
                        call.argument<Int>("offMs") ?: 100,
                    ),
                )
                null
            }

            "info" -> executor.run(result, activity) {
                mapOf(
                    "sdk_version" to Termica.GetVersaoDLL(),
                    "serial" to Termica.GetSerialEquipamento(),
                )
            }

            else -> result.notImplemented()
        }
    }

    private fun bind(activity: Activity) {
        if (boundActivity === activity) return

        Termica.setContext(activity)
        Termica.setActivity(activity)
        boundActivity = activity
    }

    private fun decodeBitmap(call: MethodCall) =
        call.argument<ByteArray>("bytes")?.let { bytes ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } ?: throw IllegalArgumentException("Imagem inválida ou não decodificável.")

    /** A Activity sumiu (rotação, background): o próximo uso refaz o vínculo. */
    fun onActivityDetached() {
        boundActivity = null
    }

    private companion object {
        /** Ver o comentário da classe: padrão do pacote 02.34.04. */
        const val DEFAULT_CONNECTION_TYPE = 6
        const val DEFAULT_MODEL = "M8"

        // `param` de StatusImpressora — significado dos parâmetros publicado
        // pela Elgin; o dos retornos, não.
        /** `CodigoErro.CONEXAO_ATIVA` do AAR: a conexão já estava de pé. */
        const val CONEXAO_ATIVA = -6

        const val STATUS_DRAWER = 1
        const val STATUS_COVER = 2
        const val STATUS_PAPER = 3
        const val STATUS_EJECTOR = 4
        const val STATUS_GENERAL = 5
    }
}
