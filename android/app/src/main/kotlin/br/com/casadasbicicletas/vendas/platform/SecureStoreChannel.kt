package br.com.casadasbicicletas.vendas.platform

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Armazenamento seguro do terminal.
 *
 * Guarda o `terminal_token` e o `session_token` — quem tiver esses valores
 * vende no nome da loja (§12 da integração com o M10). O arquivo é cifrado com
 * chave do Keystore do Android, que não sai do aparelho e não é legível por
 * outro aplicativo.
 *
 * Se a criptografia não puder ser inicializada — Keystore corrompido depois de
 * uma atualização do sistema, caso conhecido no Android — o arquivo cifrado é
 * descartado e recriado. O custo é o operador digitar a senha do terminal outra
 * vez; a alternativa seria o aplicativo não abrir.
 */
class SecureStoreChannel(private val context: Context) {

    private var channel: MethodChannel? = null

    private val preferences: SharedPreferences by lazy { openEncrypted() }

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
            "read" -> {
                val key = call.argument<String>("key")
                result.success(key?.let { preferences.getString(it, null) })
            }

            "write" -> {
                val key = call.argument<String>("key")
                val value = call.argument<String>("value")
                if (key == null || value == null) {
                    result.error("INVALID_ARGUMENT", "Chave e valor são obrigatórios.", null)
                    return
                }
                preferences.edit().putString(key, value).apply()
                result.success(null)
            }

            "delete" -> {
                call.argument<String>("key")?.let {
                    preferences.edit().remove(it).apply()
                }
                result.success(null)
            }

            "clear" -> {
                preferences.edit().clear().apply()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun openEncrypted(): SharedPreferences =
        runCatching { createEncrypted() }
            .recoverCatching { error ->
                Log.w(TAG, "Armazenamento seguro ilegível; recriando.", error)
                context.deleteSharedPreferences(FILE_NAME)
                createEncrypted()
            }
            .getOrThrow()

    private fun createEncrypted(): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        return EncryptedSharedPreferences.create(
            context,
            FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    private companion object {
        const val CHANNEL_NAME = "br.com.casadasbicicletas.vendas/secure_store"
        const val FILE_NAME = "casa_das_bicicletas_terminal"
        const val TAG = "SecureStoreChannel"
    }
}
