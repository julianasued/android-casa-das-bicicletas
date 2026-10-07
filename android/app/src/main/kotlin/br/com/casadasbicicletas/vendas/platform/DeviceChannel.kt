package br.com.casadasbicicletas.vendas.platform

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Identificação do aparelho, para a tela de configuração do terminal.
 *
 * O `ANDROID_ID` entra apenas como **sugestão** de `X-Device-Id` (§1.2): ele é
 * estável enquanto o aparelho não for formatado, o que serve para preencher o
 * campo, mas quem vale é o `device_identifier` cadastrado no backend. Por isso
 * o valor não é usado automaticamente em lugar nenhum.
 */
class DeviceChannel(private val context: Context) {

    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    @SuppressLint("HardwareIds")
    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(
                mapOf(
                    "android_id" to Settings.Secure.getString(
                        context.contentResolver,
                        Settings.Secure.ANDROID_ID,
                    ).orEmpty(),
                    "model" to Build.MODEL.orEmpty(),
                    "manufacturer" to Build.MANUFACTURER.orEmpty(),
                    "android_version" to Build.VERSION.RELEASE.orEmpty(),
                ),
            )

            else -> result.notImplemented()
        }
    }

    private companion object {
        const val CHANNEL_NAME = "br.com.casadasbicicletas.vendas/device"
    }
}
