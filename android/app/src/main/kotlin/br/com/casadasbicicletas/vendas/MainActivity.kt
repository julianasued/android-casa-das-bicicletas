package br.com.casadasbicicletas.vendas

import br.com.casadasbicicletas.vendas.platform.ConnectivityChannel
import br.com.casadasbicicletas.vendas.platform.DeviceChannel
import br.com.casadasbicicletas.vendas.platform.PrinterChannel
import br.com.casadasbicicletas.vendas.platform.ScannerChannel
import br.com.casadasbicicletas.vendas.platform.SecureStoreChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Activity host do Flutter e ponto de registro dos canais nativos do M10 Pro.
 *
 * Cada canal é um recurso do aparelho que o Flutter não alcança sozinho:
 * impressora térmica integrada, leitor de código de barras, armazenamento
 * seguro do token do terminal, estado da rede e identificação do dispositivo.
 *
 * O ciclo de vida importa: o leitor registra um `BroadcastReceiver` e a rede um
 * `NetworkCallback`. Os dois são desfeitos em [cleanUpFlutterEngine], porque
 * receptor pendurado depois da tela fechar é vazamento — e, no caso do leitor,
 * leitura chegando para uma tela que não existe mais.
 */
class MainActivity : FlutterActivity() {

    private var printerChannel: PrinterChannel? = null
    private var scannerChannel: ScannerChannel? = null
    private var secureStoreChannel: SecureStoreChannel? = null
    private var connectivityChannel: ConnectivityChannel? = null
    private var deviceChannel: DeviceChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        printerChannel = PrinterChannel().also { it.attach(messenger) }
        scannerChannel = ScannerChannel(applicationContext).also { it.attach(messenger) }
        secureStoreChannel = SecureStoreChannel(applicationContext).also { it.attach(messenger) }
        connectivityChannel = ConnectivityChannel(applicationContext).also { it.attach(messenger) }
        deviceChannel = DeviceChannel(applicationContext).also { it.attach(messenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        printerChannel?.detach()
        scannerChannel?.detach()
        secureStoreChannel?.detach()
        connectivityChannel?.detach()
        deviceChannel?.detach()

        printerChannel = null
        scannerChannel = null
        secureStoreChannel = null
        connectivityChannel = null
        deviceChannel = null

        super.cleanUpFlutterEngine(flutterEngine)
    }
}
