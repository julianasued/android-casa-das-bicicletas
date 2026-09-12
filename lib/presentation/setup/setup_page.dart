/// Configuração do terminal — feita uma vez, na instalação do aparelho.
///
/// Três informações que o backend precisa reconhecer: para onde falar, qual é a
/// loja e qual é este dispositivo. O `X-Device-Id` (§1.2) tem de ser exatamente
/// o `device_identifier` cadastrado no terminal (§3.1); o `ANDROID_ID` aparece
/// como sugestão porque é estável no aparelho, mas quem manda é o cadastro.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../platform/device/device_channel.dart';
import '../shared/feedback.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _storeIdController = TextEditingController();
  final _baseUrlController = TextEditingController();

  DeviceInfo _device = const DeviceInfo.unknown();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _storeIdController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final deps = context.deps;
    final device = await deps.device.read();
    if (!mounted) return;

    final session = deps.session;
    setState(() {
      _device = device;
      _deviceIdController.text = session.deviceId ?? device.androidId;
      _storeIdController.text = session.storeId?.toString() ?? '';
      _baseUrlController.text = session.baseUrlOverride ?? deps.environment.apiBaseUrl;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final deps = context.deps;
    final navigator = Navigator.of(context);

    await deps.session.saveConfiguration(
      deviceId: _deviceIdController.text.trim(),
      storeId: int.parse(_storeIdController.text.trim()),
      baseUrl: _baseUrlController.text.trim(),
    );

    await navigator.pushNamedAndRemoveUntil(AppRoutes.welcome, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuração do terminal')),
      body: _loading
          ? const LoadingView()
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_device.displayName.isNotEmpty)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          _device.looksLikeM10 ? Icons.point_of_sale : Icons.tablet_android,
                        ),
                        title: Text(_device.displayName),
                        subtitle: Text('Android ${_device.androidVersion}'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _baseUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Endereço da API',
                      helperText: 'HTTPS obrigatório (RNF01).',
                    ),
                    validator: _validateUrl,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _storeIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Loja (id)',
                      helperText: 'Id da loja cadastrada no sistema.',
                    ),
                    validator: _validateStoreId,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _deviceIdController,
                    decoration: InputDecoration(
                      labelText: 'Identificador do terminal (X-Device-Id)',
                      helperText: _device.androidId.isEmpty
                          ? 'Deve ser igual ao cadastrado no terminal.'
                          : 'Sugestão do aparelho: ${_device.androidId}',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Informe o identificador cadastrado.'
                        : null,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar e abrir terminal'),
                  ),
                ],
              ),
            ),
    );
  }

  String? _validateUrl(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Informe o endereço da API.';

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority) return 'Endereço inválido.';
    if (context.deps.environment.violatesTransportSecurity(text)) {
      return 'A comunicação exige HTTPS (RNF01).';
    }
    return null;
  }

  String? _validateStoreId(String? value) {
    final id = int.tryParse((value ?? '').trim());
    if (id == null || id <= 0) return 'Informe o id numérico da loja.';
    return null;
  }
}
