import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/score_result.dart';
import '../services/auth_service.dart';
import '../services/score_service.dart';
import '../theme.dart';
import '../widgets/score_chart.dart';
import 'nback_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScoreResult> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final h = await ScoreService.fetchHistory();
      if (mounted) setState(() { _history = h; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('履歴を削除'),
        content: const Text('すべての記録を削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除',
                style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ScoreService.deleteAllHistory();
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final nback = _history.where((h) => h.gameName == 'N-Back').toList();
    final total = nback.length;
    final best = total > 0
        ? nback.map((h) => h.score).reduce((a, b) => a > b ? a : b)
        : null;
    final avg = total > 0
        ? (nback.map((h) => h.score).reduce((a, b) => a + b) / total).round()
        : null;
    final chartData = nback.take(10).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ECMAP',
          style: GoogleFonts.spaceMono(
              color: AppColors.accentBlue, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (user?.email != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(user!.email!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'ログアウト',
            onPressed: AuthService.signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Game card
                    _GameCard(onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NBackScreen()),
                      );
                      _loadHistory();
                    }),
                    const SizedBox(height: 20),

                    // Stats row
                    Row(
                      children: [
                        Expanded(
                            child: _StatTile(
                                label: 'プレイ回数', value: '$total 回')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _StatTile(
                                label: 'ベスト',
                                value: best != null ? '$best%' : '—')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _StatTile(
                                label: '平均',
                                value: avg != null ? '$avg%' : '—')),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Chart
                    if (chartData.isNotEmpty) ...[
                      const Text('スコア推移（直近10回）',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 8),
                      SizedBox(
                          height: 160, child: ScoreChart(data: chartData)),
                      const SizedBox(height: 20),
                    ],

                    // History header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('プレイ履歴',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        if (nback.isNotEmpty)
                          TextButton(
                            onPressed: _clearHistory,
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.accentRed,
                                textStyle:
                                    const TextStyle(fontSize: 12)),
                            child: const Text('履歴を削除'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (nback.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text('まだ記録がありません',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        ),
                      )
                    else
                      ...nback
                          .take(30)
                          .map((r) => _HistoryTile(result: r)),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _GameCard extends StatelessWidget {
  final VoidCallback onTap;
  const _GameCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: const Border(
              top: BorderSide(color: AppColors.accentPurple, width: 3)),
          boxShadow: [
            BoxShadow(
                color: AppColors.accentPurple.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accentPurple.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.psychology_rounded,
                  color: AppColors.accentPurple, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('N-Back トレーニング',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    '記憶力・集中力・反応速度を同時に鍛えるデュアルタスク',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentBlue)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ScoreResult result;
  const _HistoryTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final score = result.score;
    final color = score >= 85
        ? AppColors.accentGreen
        : score >= 60
            ? AppColors.accentBlue
            : AppColors.accentOrange;
    final fmt = DateFormat('MM/dd HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(result.gameName,
                  style: const TextStyle(fontSize: 13))),
          Text('$score%',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 14)),
          const SizedBox(width: 12),
          Text(fmt.format(result.playedAt),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
