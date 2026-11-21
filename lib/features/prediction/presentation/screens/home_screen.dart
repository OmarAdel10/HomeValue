import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants.dart';
import '../../domain/entities/house_features.dart';
import '../../domain/entities/prediction_result.dart' show PredictionResult;
import '../bloc/prediction_bloc.dart';
import '../bloc/prediction_state.dart';
import '../bloc/prediction_event.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  OceanProximity _selectedOceanProximity = OceanProximity.inland;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _addListenerForValidation();
  }

  void _initControllers() {
    for (final feature in AppConstants.featureNames) {
      _controllers[feature] = TextEditingController();
      _focusNodes[feature] = FocusNode();
    }
    // Also add ocean proximity controller
    _controllers[AppConstants.oceanProximityField] = TextEditingController();
    _focusNodes[AppConstants.oceanProximityField] = FocusNode();
  }

  void _addListenerForValidation() {
    for (final controller in _controllers.values) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    // Trigger validation on change
    if (_formKey.currentState != null) {
      _formKey.currentState!.validate();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PredictionBloc, PredictionState>(
      listener: (context, state) {
        if (state is PredictionSuccess) {
          _showPredictionDialog(context, state.result);
        } else if (state is PredictionFailure) {
          _showErrorSnackBar(context, state.message);
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('HomeValue'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => context.push('/settings'),
                tooltip: 'Settings',
              ),
              IconButton(
                icon: const Icon(Icons.compare_arrows),
                onPressed: () => context.push('/comparison'),
                tooltip: 'Model Comparison',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildFeatureInputs(),
                  const SizedBox(height: 24),
                  _buildPredictButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Predict House Price',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter property features to get a price prediction',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildFeatureInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Core Property Features
        _buildSectionHeader(
            'Property Details', 'Basic characteristics of the house'),
        _buildFeatureFieldWithDefault('MedInc', 8.3252,
            'Median income in \$100k (e.g., 8.3252 = \$832k)'),
        _buildFeatureFieldWithDefault(
            'HouseAge', 41, 'Median house age in years (e.g., 41)'),
        _buildFeatureFieldWithDefault(
            'AveRooms', 6.98, 'Avg total rooms per household (e.g., 6.98)'),
        _buildFeatureFieldWithDefault(
            'AveBedrms', 1.02, 'Avg bedrooms per household (e.g., 1.02)'),
        const SizedBox(height: 24),
        // Location & Demographics (with smart defaults)
        _buildSectionHeader('Location & Area',
            'Neighborhood context — auto-filled for California'),
        _buildFeatureFieldWithDefault('Latitude', 37.88,
            'Approximate latitude in California (e.g., 37.88 for Bay Area)'),
        _buildFeatureFieldWithDefault('Longitude', -122.23,
            'Approximate longitude in California (e.g., -122.23 for Bay Area)'),
        _buildFeatureFieldWithDefault(
            'Population', 322, 'Block group population (typical: 300–3000)'),
        _buildFeatureFieldWithDefault(
            'AveOccup', 2.55, 'Average people per household'),
        const SizedBox(height: 24),
        // Ocean Proximity
        _buildSectionHeader('Environment', 'Proximity to water'),
        _buildOceanProximitySelector(),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFeatureFieldWithDefault(
      String feature, double defaultValue, String helpText) {
    final controller = _controllers[feature]!;
    final focusNode = _focusNodes[feature]!;
    final label = AppConstants.featureLabels[feature] ?? feature;
    final hint = AppConstants.featureHints[feature] ?? '';

    // Set default if empty
    if (controller.text.isEmpty) {
      controller.text = defaultValue.toString();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: Key('field_$feature'),
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helpText,
          prefixIcon: Icon(_getFieldIcon(feature)),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter $label';
          }
          final numValue = num.tryParse(value);
          if (numValue == null) {
            return 'Please enter a valid number';
          }
          return null;
        },
      ),
    );
  }

  IconData _getFieldIcon(String feature) {
    switch (feature) {
      case 'MedInc':
        return Icons.attach_money;
      case 'HouseAge':
        return Icons.calendar_today;
      case 'AveRooms':
      case 'AveBedrms':
        return Icons.king_bed;
      case 'Population':
        return Icons.people;
      case 'AveOccup':
        return Icons.group;
      case 'Latitude':
      case 'Longitude':
        return Icons.location_on;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildOceanProximitySelector() {
    return DropdownButtonFormField<OceanProximity>(
      key: const Key('ocean_proximity_dropdown'),
      initialValue: _selectedOceanProximity,
      decoration: const InputDecoration(
        // Label intentionally omitted — section header 'Environment' /
        // 'Proximity to water' already explains this field.
        prefixIcon: Icon(Icons.waves),
      ),
      items: OceanProximity.values.map((proximity) {
        return DropdownMenuItem(
          value: proximity,
          child: Text(proximity.value),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedOceanProximity = value;
          });
        }
      },
      validator: (value) {
        if (value == null) {
          return 'Please select ocean proximity';
        }
        return null;
      },
    );
  }

  Widget _buildPredictButton() {
    return BlocBuilder<PredictionBloc, PredictionState>(
      builder: (context, state) {
        final isLoading = state is PredictionLoading;

        return FilledButton(
          key: const Key('predict_button'),
          onPressed: isLoading ? null : _onPredictPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Predict Price'),
        );
      },
    );
  }

  void _onPredictPressed() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final features = HouseFeatures(
      medInc: double.parse(_controllers['MedInc']!.text),
      houseAge: double.parse(_controllers['HouseAge']!.text),
      aveRooms: double.parse(_controllers['AveRooms']!.text),
      aveBedrms: double.parse(_controllers['AveBedrms']!.text),
      population: double.parse(_controllers['Population']!.text),
      aveOccup: double.parse(_controllers['AveOccup']!.text),
      latitude: double.parse(_controllers['Latitude']!.text),
      longitude: double.parse(_controllers['Longitude']!.text),
      oceanProximity: _selectedOceanProximity,
    );

    context.read<PredictionBloc>().add(
          PredictRequested(features),
        );
  }

  void _showPredictionDialog(BuildContext context, PredictionResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Prediction Result'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Predicted Price:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '\$${(result.prediction * 100000).toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Text('Model: ${result.model}'),
            Text('Version: ${result.modelVersion}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
