package br.com.casadasbicicletas.vendas.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Estado da rede do terminal.
 *
 * O que interessa não é "existe Wi-Fi", e sim "dá para falar com a API": um M10
 * conectado a um roteador sem internet está tão offline quanto um desligado.
 * Por isso a checagem exige [NetworkCapabilities.NET_CAPABILITY_VALIDATED], que
 * é o Android dizendo que a rede tem saída de verdade.
 */
class ConnectivityChannel(private val context: Context) : EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private val manager: ConnectivityManager?
        get() = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    fun detach() {
        unregister()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        events = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isOnline" -> result.success(isOnline())
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        mainHandler.post { sink?.success(isOnline()) }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = emit()
            override fun onLost(network: Network) = emit()

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) = emit()

            private fun emit() {
                val online = isOnline()
                mainHandler.post { events?.success(online) }
            }
        }

        runCatching { manager?.registerNetworkCallback(request, networkCallback) }
        callback = networkCallback
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        events = null
    }

    private fun unregister() {
        callback?.let { registered ->
            runCatching { manager?.unregisterNetworkCallback(registered) }
        }
        callback = null
    }

    private fun isOnline(): Boolean {
        val connectivity = manager ?: return false
        val network = connectivity.activeNetwork ?: return false
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return false

        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private companion object {
        const val METHOD_CHANNEL = "br.com.casadasbicicletas.vendas/connectivity"
        const val EVENT_CHANNEL = "br.com.casadasbicicletas.vendas/connectivity/status"
    }
}
