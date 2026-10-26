import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/model_comparison.dart';
import '../bloc/comparison_bloc.dart';
import '../widgets/metric_chart.dart';
import '../widgets/model_metric_tile.dart';

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  String _selectedMetric = 'rmse';

  @override
  void initState() {
    super.initState();
    context.read<ComparisonBloc>().add(const LoadComparison());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Comparison'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<ComparisonBloc>().add(const RefreshComparison()),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<ComparisonBloc, ComparisonState>(
        builder: (context, state) {
          if (state is ComparisonLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ComparisonFailure) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Failed to load comparison: ${state.message}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context
                        .read<ComparisonBloc>()
                        .add(const LoadComparison()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (state is ComparisonLoaded) {
            return _buildComparisonView(context, state.comparison);
          }
          return const Center(child: Text('No comparison data'));
        },
      ),
    );
  }

  Widget _buildComparisonView(
      BuildContext context, ModelComparison comparison) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Model Performance Metrics',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Compare model performance across different metrics. Best model highlighted in green.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),

          // Metric selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Metric to Visualize',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'rmse', label: Text('RMSE')),
                      ButtonSegment(value: 'mae', label: Text('MAE')),
                      ButtonSegment(value: 'r2', label: Text('R²')),
                      ButtonSegment(value: 'cv_std', label: Text('CV Std')),
                    ],
                    selected: {_selectedMetric},
                    onSelectionChanged: (Set<String> selection) {
                      setState(() {
                        _selectedMetric = selection.first;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Bar chart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedMetric.toUpperCase()} Comparison',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  MetricChart(
                    comparison: comparison,
                    metricName: _selectedMetric,
                    height: 300,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Data table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detailed Metrics',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Model')),
                        DataColumn(label: Text('RMSE'), numeric: true),
                        DataColumn(label: Text('MAE'), numeric: true),
                        DataColumn(label: Text('R²'), numeric: true),
                        DataColumn(label: Text('CV Std'), numeric: true),
                        DataColumn(label: Text('Best')),
                      ],
                      rows: comparison.metrics.map((metric) {
                        return DataRow(
                          color: WidgetStateProperty.resolveWith<Color?>(
                            (states) => metric.isBest
                                ? Colors.green.withValues(alpha: 0.1)
                                : null,
                          ),
                          cells: [
                            DataCell(Text(metric.name)),
                            DataCell(Text(metric.rmse.toStringAsFixed(4))),
                            DataCell(Text(metric.mae.toStringAsFixed(4))),
                            DataCell(Text(metric.r2.toStringAsFixed(4))),
                            DataCell(Text(metric.cvStd.toStringAsFixed(4))),
                            DataCell(
                              metric.isBest
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : const SizedBox(),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Model detail cards
          Text(
            'Model Details',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...comparison.metrics.map((metric) => ModelMetricTile(
                metric: metric,
                isExpanded: true,
              )),
        ],
      ),
    );
  }
}
