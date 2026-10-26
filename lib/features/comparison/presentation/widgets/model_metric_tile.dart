import 'package:flutter/material.dart';
import '../../domain/entities/model_comparison.dart';

class ModelMetricTile extends StatelessWidget {
  const ModelMetricTile({
    super.key,
    required this.metric,
    this.isExpanded = false,
  });

  final ModelMetric metric;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    metric.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (metric.isBest)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'BEST',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (isExpanded)
              _buildExpandedMetrics(theme)
            else
              _buildSummaryMetrics(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _MetricItem(label: 'RMSE', value: metric.rmse.toStringAsFixed(4)),
        _MetricItem(label: 'MAE', value: metric.mae.toStringAsFixed(4)),
        _MetricItem(label: 'R²', value: metric.r2.toStringAsFixed(4)),
        _MetricItem(label: 'CV Std', value: metric.cvStd.toStringAsFixed(4)),
      ],
    );
  }

  Widget _buildExpandedMetrics(ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MetricItem(label: 'RMSE', value: metric.rmse.toStringAsFixed(4)),
            _MetricItem(label: 'MAE', value: metric.mae.toStringAsFixed(4)),
            _MetricItem(label: 'R²', value: metric.r2.toStringAsFixed(4)),
            _MetricItem(
                label: 'CV Std', value: metric.cvStd.toStringAsFixed(4)),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        Text(
          metric.isBest
              ? 'This model achieved the best cross-validation score.'
              : 'This model was not the top performer in cross-validation.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
