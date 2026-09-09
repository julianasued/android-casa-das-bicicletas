package br.com.casadasbicicletas.vendas

import br.com.casadasbicicletas.vendas.platform.ConnectivityChannel
import br.com.casadasbicicletas.vendas.platform.CustomerDisplayChannel
import br.com.casadasbicicletas.vendas.platform.DeviceChannel
import br.com.casadasbicicletas.vendas.platform.PrinterChannel
import br.com.casadasbicicletas.vendas.platform.ScannerChannel
import br.com.casadasbicicletas.vendas.platform.SecureStoreChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Activity host do Flutter e ponto de registro dos canais nativos do M10.
 *
 * Cada canal é um recurso do aparelho que o Flutter não alcança sozinho:
 * impressora térmica integrada, leitor de código de barras, display do cliente,
 * armazenamento seguro do token do terminal, estado da rede e identificação do
 * dispositivo.
 *
 * A Activity é entregue à impressora como **função**, não como referência
 * guardada: o SDK da Elgin precisa dela para inicializar, mas o canal vive
 * enquanto o `FlutterEngine` viver, e guardar a Activity aqui a manteria viva
 * depois de destruída. A cadeia é
 * `MainActivity → PrinterChannel → ElginThermalPrinter → Termica`; nenhuma
 * lógica de hardware mora nesta classe.
 *
 * O ciclo de vida importa: o leitor registra um `BroadcastReceiver` e a rede um
 * `NetworkCallback`. Os dois são desfeitos em [cleanUpFlutterEngine], porque
 * receptor pendurado depois da tela fechar é vazamento — e, no caso do leitor,
 * leitura chegando para uma tela que não existe mais.
 */
class MainActivity : FlutterActivity() {

    private var printerChannel: PrinterChannel? = null
    private var scannerChannel: ScannerChannel? = null
    private var customerDisplayChannel: CustomerDisplayChannel? = null
    private var secureStoreChannel: SecureStoreChannel? = null
    private var connectivityChannel: ConnectivityChannel? = null
    private var deviceChannel: DeviceChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        printerChannel = PrinterChannel(
            // Resolvida a cada chamada: se a Activity foi destruída, o SDK
            // recebe `null` e a falha aparece como impressora indisponível, em
            // vez de estourar sobre uma referência morta.
            activityProvider = { if (isDestroyed) null else this },
        ).also { it.attach(messenger) }

        scannerChannel = ScannerChannel(applicationContext).also { it.attach(messenger) }
        customerDisplayChannel =
            CustomerDisplayChannel(applicationContext).also { it.attach(messenger) }
        secureStoreChannel = SecureStoreChannel(applicationContext).also { it.attach(messenger) }
        connectivityChannel = ConnectivityChannel(applicationContext).also { it.attach(messenger) }
        deviceChannel = DeviceChannel(applicationContext).also { it.attach(messenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        printerChannel?.detach()
        scannerChannel?.detach()
        customerDisplayChannel?.detach()
        secureStoreChannel?.detach()
        connectivityChannel?.detach()
        deviceChannel?.detach()

        printerChannel = null
        scannerChannel = null
        customerDisplayChannel = null
        secureStoreChannel = null
        connectivityChannel = null
        deviceChannel = null

        super.cleanUpFlutterEngine(flutterEngine)
    }
}
