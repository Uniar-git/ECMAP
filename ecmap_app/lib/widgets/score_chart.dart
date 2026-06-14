import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/score_result.dart';
import '../theme.dart';

class ScoreChart extends StatelessWidget {
  final List<ScoreResult> data;
  const ScoreChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.score.toDouble()))
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: 25,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}%',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                ),
              ),
            ),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.accentBlue,
              barWidth: 2,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.accentBlue,
                  strokeWidth: 2,
                  strokeColor: AppColors.bgPrimary,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accentBlue.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
