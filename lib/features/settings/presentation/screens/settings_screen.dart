import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import '../../domain/entities/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    context.read<SettingsBloc>().add(const LoadSettings());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listener: (context, state) {
        if (state is SettingsLoaded) {
          _urlController.text = state.settings.serverUrl;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
        ),
        body: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, state) {
            if (state is SettingsLoaded) {
              return _buildSettingsForm(context, state.settings);
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Widget _buildSettingsForm(BuildContext context, AppSettings settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('API Server'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'http://localhost:8000',
                        prefixIcon: Icon(Icons.cloud),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a server URL';
                        }
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null ||
                            !uri.hasScheme ||
                            (uri.scheme != 'http' && uri.scheme != 'https') ||
                            uri.host.isEmpty) {
                          return 'Please enter a valid URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          context.read<SettingsBloc>().add(
                                UpdateServerUrl(_urlController.text.trim()),
                              );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Server URL updated')),
                          );
                        }
                      },
                      child: const Text('Save Server URL'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Appearance'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildThemeSelector(settings.themeMode),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Behavior'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Auto Retrain'),
                      subtitle: const Text(
                          'Automatically retrain models when new data is available'),
                      value: settings.autoRetrain,
                      onChanged: (value) {
                        context
                            .read<SettingsBloc>()
                            .add(ToggleAutoRetrain(value));
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('About'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HomeValue',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text('Version 1.0.0'),
                    const SizedBox(height: 4),
                    Text(
                      'House price prediction using machine learning',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Data: California Housing Dataset',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  Widget _buildThemeSelector(ThemeMode currentTheme) {
    return DropdownButtonFormField<ThemeMode>(
      initialValue: currentTheme,
      decoration: const InputDecoration(
        labelText: 'Theme',
        prefixIcon: Icon(Icons.palette),
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
        DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
      ],
      onChanged: (value) {
        if (value != null) {
          context.read<SettingsBloc>().add(ToggleTheme(value));
        }
      },
    );
  }
}
