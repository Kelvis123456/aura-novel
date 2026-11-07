import 'dart:ui';

import 'package:flutter/material.dart';

import 'api_settings_controller.dart';
import '../../core/theme/aura_theme.dart';

/// Connection settings screen for "AURA NOVEL" — dark glassmorphism styled
/// form to configure a custom OpenAI-compatible endpoint, test it, and
/// persist it via [ApiSettingsController].
class ApiSettingsScreen extends StatefulWidget {
  final Color? accentColor;

  const ApiSettingsScreen({
    super.key,
    this.accentColor,
  });

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  late final ApiSettingsController _controller;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _baseUrlField;
  late final TextEditingController _apiKeyField;
  late final TextEditingController _modelIdField;
  late final TextEditingController _researchField;

  @override
  void initState() {
    super.initState();
    _controller = ApiSettingsController()..addListener(_onControllerChanged);
    _baseUrlField = TextEditingController();
    _apiKeyField = TextEditingController();
    _modelIdField = TextEditingController();
    _researchField = TextEditingController();
    _controller.load().then((_) => _syncFieldsFromController());
  }

  void _onControllerChanged() => setState(() {});

  void _syncFieldsFromController() {
    _baseUrlField.text = _controller.baseUrl;
    _apiKeyField.text = _controller.apiKey;
    _modelIdField.text = _controller.modelId;
    _researchField.text = _controller.researchModelId;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _baseUrlField.dispose();
    _apiKeyField.dispose();
    _modelIdField.dispose();
    _researchField.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final ok = await _controller.save();
    if (!mounted) return;
    _showSnack(
      ok ? 'Configuración guardada de forma cifrada.' : 'Revisa los campos marcados en rojo.',
      isError: !ok,
    );
  }

  Future<void> _handleTest() async {
    await _controller.testConnection();
    if (!mounted) return;
    if (_controller.status == ConnectionStatus.connected) {
      _showSnack('Conexión exitosa.');
    } else if (_controller.status != ConnectionStatus.invalidForm) {
      _showSnack(_controller.statusDetail ?? _controller.status.label, isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? context.aura.danger : context.aura.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = (widget.accentColor ?? context.aura.accent);

    return Scaffold(
      backgroundColor: context.aura.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Conexión de API'),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: context.aura.bg,
        ),
        child: _controller.isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StatusBadge(status: _controller.status, accent: accent),
                        if (_controller.statusDetail != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _controller.statusDetail!,
                            style: TextStyle(color: context.aura.textDim, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Endpoint'),
                              const SizedBox(height: 4),
                              Text(
                                'La app no filtra nada: lo que se puede escribir lo decide el modelo que conectes. Los modelos locales o de proveedores sin censura escriben con más libertad que los comerciales.',
                                style: TextStyle(color: context.aura.textFaint, fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  for (final (label, url, model) in const [
                                    ('Gemini gratis', 'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.0-flash'),
                                    ('OpenRouter', 'https://openrouter.ai/api/v1', 'nousresearch/hermes-3-llama-3.1-70b'),
                                    ('Ollama (tu PC)', 'http://IP-DE-TU-PC:11434/v1', 'llama3.1'),
                                    ('LM Studio (tu PC)', 'http://IP-DE-TU-PC:1234/v1', 'local-model'),
                                  ])
                                    ActionChip(
                                      label: Text(label, style: TextStyle(color: context.aura.text, fontSize: 12)),
                                      backgroundColor: context.aura.surface,
                                      side: BorderSide(color: context.aura.line),
                                      onPressed: () {
                                        _controller.applyPreset(url, model);
                                        _baseUrlField.text = url;
                                        _modelIdField.text = model;
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _baseUrlField,
                                label: 'Base URL',
                                hint: 'https://openrouter.ai/api/v1',
                                errorText: _controller.formErrors['baseUrl'],
                                onChanged: _controller.updateBaseUrl,
                                keyboardType: TextInputType.url,
                                accent: accent,
                              ),
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _apiKeyField,
                                label: 'API Key',
                                hint: 'sk-...',
                                errorText: _controller.formErrors['apiKey'],
                                onChanged: _controller.updateApiKey,
                                obscureText: _controller.obscureApiKey,
                                accent: accent,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _controller.obscureApiKey
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: context.aura.textDim,
                                  ),
                                  onPressed: _controller.toggleApiKeyVisibility,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _modelIdField,
                                label: 'Model ID',
                                hint: 'nousresearch/hermes-3-llama-3.1-70b',
                                errorText: _controller.formErrors['modelId'],
                                onChanged: _controller.updateModelId,
                                accent: accent,
                              ),
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _researchField,
                                label: 'Modelo de investigación (opcional)',
                                hint: 'perplexity/sonar o un modelo ":online"',
                                onChanged: _controller.updateResearchModelId,
                                accent: accent,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Para investigar con datos de la web, usa un modelo con búsqueda. Si lo dejas vacío, investiga el mismo modelo que escribe.',
                                style: TextStyle(color: context.aura.textFaint, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Parámetros por defecto'),
                              const SizedBox(height: 8),
                              _buildSlider(
                                label: 'Temperature',
                                value: _controller.temperature,
                                min: 0.0,
                                max: 2.0,
                                divisions: 40,
                                displayValue: _controller.temperature.toStringAsFixed(2),
                                onChanged: (v) => _controller.updateTemperature(v),
                                accent: accent,
                              ),
                              _buildSlider(
                                label: 'Max Tokens',
                                value: _controller.maxTokens.toDouble(),
                                min: 256,
                                max: 16000,
                                divisions: 157,
                                displayValue: _controller.maxTokens.toString(),
                                onChanged: (v) => _controller.updateMaxTokens(v.round()),
                                accent: accent,
                              ),
                              _buildSlider(
                                label: 'Frequency Penalty',
                                value: _controller.frequencyPenalty,
                                min: -2.0,
                                max: 2.0,
                                divisions: 40,
                                displayValue: _controller.frequencyPenalty.toStringAsFixed(2),
                                onChanged: (v) => _controller.updateFrequencyPenalty(v),
                                accent: accent,
                              ),
                              _buildSlider(
                                label: 'Presence Penalty',
                                value: _controller.presencePenalty,
                                min: -2.0,
                                max: 2.0,
                                divisions: 40,
                                displayValue: _controller.presencePenalty.toStringAsFixed(2),
                                onChanged: (v) => _controller.updatePresencePenalty(v),
                                accent: accent,
                              ),
                              _buildSlider(
                                label: 'Contexto de lore y resúmenes',
                                value: _controller.contextChars.toDouble(),
                                min: 500,
                                max: 20000,
                                divisions: 39,
                                displayValue: '${_controller.contextChars} car. (~${_controller.contextChars ~/ 4} tokens)',
                                onChanged: (v) => _controller.updateContextChars(v.round()),
                                accent: accent,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Tope para cada uno. Bájalo con modelos de ventana corta, súbelo con los grandes.',
                                  style: TextStyle(color: context.aura.textFaint, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _controller.status == ConnectionStatus.testing
                                    ? null
                                    : _handleTest,
                                icon: _controller.status == ConnectionStatus.testing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.wifi_tethering),
                                label: const Text('Probar Conexión'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.aura.text,
                                  side: BorderSide(color: accent.withValues(alpha: 0.6)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _controller.isSaving ? null : _handleSave,
                                icon: _controller.isSaving
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: context.aura.text,
                                        ),
                                      )
                                    : const Icon(Icons.lock_outline),
                                label: const Text('Guardar'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'La API Key se cifra en el Keychain/Keystore del dispositivo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.aura.textFaint, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.aura.textDim,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
    required Color accent,
    String? errorText,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: context.aura.text, fontFamily: 'monospace', fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        labelStyle: TextStyle(color: context.aura.textDim),
        hintStyle: TextStyle(color: context.aura.textFaint),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: context.aura.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.aura.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.aura.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.aura.danger),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: context.aura.textDim, fontSize: 13)),
            Text(displayValue, style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: context.aura.line,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.2),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Frosted glass container used for every card on this screen.
class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.aura.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.aura.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Color-coded connection status chip.
class _StatusBadge extends StatelessWidget {
  final ConnectionStatus status;
  final Color accent;
  const _StatusBadge({required this.status, required this.accent});

  Color _color(AuraColors c) => switch (status) {
        ConnectionStatus.connected => c.success,
        ConnectionStatus.unconfigured => c.textFaint,
        ConnectionStatus.savedUntested => c.warning,
        ConnectionStatus.testing => accent,
        ConnectionStatus.unauthorized => c.warning,
        ConnectionStatus.timeout => c.warning,
        ConnectionStatus.networkError => c.danger,
        ConnectionStatus.serverError => c.danger,
        ConnectionStatus.invalidForm => c.danger,
      };

  IconData get _icon => switch (status) {
        ConnectionStatus.connected => Icons.check_circle,
        ConnectionStatus.unconfigured => Icons.settings_outlined,
        ConnectionStatus.savedUntested => Icons.save_outlined,
        ConnectionStatus.testing => Icons.sync,
        ConnectionStatus.unauthorized => Icons.lock_outline,
        ConnectionStatus.timeout => Icons.timer_off_outlined,
        ConnectionStatus.networkError => Icons.wifi_off,
        ConnectionStatus.serverError => Icons.error_outline,
        ConnectionStatus.invalidForm => Icons.warning_amber_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color(context.aura);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(status.label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
