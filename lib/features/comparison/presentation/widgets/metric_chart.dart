import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/model_comparison.dart';

class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.comparison,
    this.metricName = 'rmse',
    this.height = 300,
  });

  final ModelComparison comparison;
  final String metricName;
  final double height;

  double _getMetricValue(ModelMetric m) {
    switch (metricName.toLowerCase()) {
      case 'rmse':
        return m.rmse;
      case 'mae':
        return m.mae;
      case 'r2':
        return m.r2;
      case 'cv_std':
        return m.cvStd;
      default:
        return m.rmse;
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = comparison.metrics;

    // Handle empty metrics
    if (metrics.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No comparison data available')),
      );
    }

    final values = metrics.map(_getMetricValue).toList();
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);

    // Handle single metric (minValue == maxValue)
    final interval = maxValue == minValue
        ? (maxValue > 0 ? maxValue / 5 : 1.0)
        : (maxValue - minValue) / 5;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          minY: minValue > 0 ? minValue * 0.8 : 0,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < metrics.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        metrics[value.toInt()].name,
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 60,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: metrics.asMap().entries.map((entry) {
            final index = entry.key;
            final metric = entry.value;
            final value = _getMetricValue(metric);
            final isBest = metric.isBest;

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: value,
                  color: isBest ? Colors.green : Colors.blue,
                  width: 20,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxValue * 1.2,
                    color: Colors.grey.withValues(alpha: 0.1),
                  ),
                ),
              ],
              showingTooltipIndicators: [0],
            );
          }).toList(),
        ),
      ),
    );
  }
}
