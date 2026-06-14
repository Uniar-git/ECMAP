import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/score_service.dart';
import '../theme.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _Level {
  final int time;       // seconds per answer round
  final int introTime;  // seconds for first N rounds
  final int rounds;     // number of answer rounds
  final int choices;    // number of choice buttons
  final int colors;     // number of distinct colors to use
  const _Level({
    required this.time,
    required this.introTime,
    required this.rounds,
    required this.choices,
    required this.colors,
  });
}

const _kN = 2;

const _levels = <int, _Level>{
  1: _Level(time: 15, introTime: 8, rounds: 10, choices: 4, colors: 3),
  2: _Level(time: 15, introTime: 8, rounds: 10, choices: 4, colors: 4),
  3: _Level(time: 12, introTime: 6, rounds: 15, choices: 5, colors: 5),
  4: _Level(time: 10, introTime: 6, rounds: 18, choices: 6, colors: 6),
  5: _Level(time: 8,  introTime: 5, rounds: 20, choices: 6, colors: 8),
};

const _kLevelNames = {
  1: 'EASY', 2: 'NORMAL', 3: 'HARD', 4: 'EXPERT', 5: 'MASTER',
};

const _kLevelDesc = {
  1: '色は3種類、時間は15秒。まずは感覚をつかもう。',
  2: '色が4種類に増加。組み合わせが複雑になります。',
  3: '制限時間12秒・15ラウンド。本格的なトレーニング。',
  4: '色6種類・制限時間10秒。高い集中力が必要。',
  5: '全8色・制限時間8秒。最高難度のマスターコース。',
};

class _NColor {
  final String name;
  final Color color;
  const _NColor(this.name, this.color);
}

const _kColors = [
  _NColor('赤', Color(0xFFEF4444)),
  _NColor('青', Color(0xFF3B82F6)),
  _NColor('緑', Color(0xFF22C55E)),
  _NColor('黄', Color(0xFFEAB308)),
  _NColor('紫', Color(0xFFA855F7)),
  _NColor('橙', Color(0xFFF97316)),
  _NColor('水', Color(0xFF06B6D4)),
  _NColor('桃', Color(0xFFEC4899)),
];

class _Item {
  final int number;
  final int colorIndex;
  const _Item(this.number, this.colorIndex);
}

class _Choice {
  final _Item item;
  final bool isCorrect;
  const _Choice(this.item, this.isCorrect);
}

enum _Phase { menu, countdown, playing, result }

// ── Screen ────────────────────────────────────────────────────────────────────

class NBackScreen extends StatefulWidget {
  const NBackScreen({super.key});

  @override
  State<NBackScreen> createState() => _NBackScreenState();
}

class _NBackScreenState extends State<NBackScreen>
    with TickerProviderStateMixin {
  // Navigation phase
  _Phase _phase = _Phase.menu;

  // Menu
  int _selectedLevel = 1;
  final Map<int, int> _bestScores = {};

  // Countdown
  int _countdown = 3;
  Timer? _countdownTimer;

  // Game
  late _Level _cfg;
  late List<_Item> _seq;
  int _step = 0;      // current position in _seq (0-indexed)
  int _correct = 0;
  int _wrong = 0;
  final List<bool?> _results = [];  // true/false/null per answer round

  List<_Choice> _choices = [];
  bool _answered = false;

  // Timer animation (0→1 over `duration` seconds)
  late AnimationController _timerCtrl;
  Timer? _roundTimer;

  // Feedback flash color
  Color? _flash;
  Timer? _flashTimer;

  // Key to trigger AnimatedSwitcher on new stimulus
  int _stimKey = 0;

  @override
  void initState() {
    super.initState();
    _timerCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _roundTimer?.cancel();
    _flashTimer?.cancel();
    _timerCtrl.dispose();
    super.dispose();
  }

  // ── Sequence generation ────────────────────────────────────────────────────

  List<_Item> _genSeq(_Level cfg) {
    final rng = Random();
    return List.generate(cfg.rounds + _kN, (_) {
      return _Item(
        rng.nextInt(9) + 1,          // 1–9
        rng.nextInt(cfg.colors),     // color index within used range
      );
    });
  }

  List<_Choice> _genChoices(_Item target, _Level cfg) {
    final rng = Random();
    final list = [_Choice(target, true)];
    while (list.length < cfg.choices) {
      final n = rng.nextInt(9) + 1;
      final c = rng.nextInt(cfg.colors);
      if (!list.any((ch) => ch.item.number == n && ch.item.colorIndex == c)) {
        list.add(_Choice(_Item(n, c), false));
      }
    }
    list.shuffle(rng);
    return list;
  }

  // ── Game flow ──────────────────────────────────────────────────────────────

  void _startGame() {
    _cfg = _levels[_selectedLevel]!;
    _seq = _genSeq(_cfg);
    _step = 0;
    _correct = 0;
    _wrong = 0;
    _results.clear();
    _flash = null;
    _startCountdown();
  }

  void _startCountdown() {
    setState(() { _phase = _Phase.countdown; _countdown = 3; });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _phase = _Phase.playing);
        _nextRound();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _nextRound() {
    if (_step >= _seq.length) {
      _endGame();
      return;
    }

    final isIntro = _step < _kN;
    final duration = isIntro ? _cfg.introTime : _cfg.time;

    _choices = isIntro ? [] : _genChoices(_seq[_step - _kN], _cfg);
    _answered = false;
    _flash = null;

    _timerCtrl.duration = Duration(seconds: duration);
    _timerCtrl.forward(from: 0);

    setState(() => _stimKey++);

    _roundTimer?.cancel();
    _roundTimer = Timer(Duration(seconds: duration), () {
      if (!mounted) return;
      if (isIntro) {
        _step++;
        _nextRound();
      } else if (!_answered) {
        _onTimeout();
      }
    });
  }

  void _onAnswer(bool isCorrect) {
    if (_answered) return;
    _answered = true;
    _roundTimer?.cancel();
    _timerCtrl.stop();

    if (isCorrect) {
      _correct++;
      _results.add(true);
    } else {
      _wrong++;
      _results.add(false);
    }

    _flashColor(isCorrect ? AppColors.accentGreen : AppColors.accentRed);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) { _step++; _nextRound(); }
    });
  }

  void _onTimeout() {
    _answered = true;
    _wrong++;
    _results.add(null);
    _flashColor(AppColors.accentRed);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) { _step++; _nextRound(); }
    });
  }

  void _flashColor(Color c) {
    setState(() => _flash = c);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _endGame() {
    final score = _calcScore();
    if (score > 0) {
      final prev = _bestScores[_selectedLevel];
      if (prev == null || score > prev) {
        _bestScores[_selectedLevel] = score;
      }
    }
    ScoreService.saveScore('N-Back', score);
    setState(() => _phase = _Phase.result);
  }

  int _calcScore() {
    final total = _correct + _wrong;
    return total > 0 ? (_correct * 100 ~/ total) : 0;
  }

  String _grade(int score) {
    if (score >= 95) return 'S+';
    if (score >= 85) return 'S';
    if (score >= 75) return 'A';
    if (score >= 60) return 'B';
    if (score >= 45) return 'C';
    return 'D';
  }

  Color _gradeColor(String g) {
    switch (g) {
      case 'S+': return const Color(0xFFFFD700);
      case 'S':  return const Color(0xFFC0C0C0);
      case 'A':  return AppColors.accentGreen;
      case 'B':  return AppColors.accentBlue;
      case 'C':  return AppColors.accentOrange;
      default:   return AppColors.accentRed;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.menu      => _buildMenu(),
      _Phase.countdown => _buildCountdown(),
      _Phase.playing   => _buildPlaying(),
      _Phase.result    => _buildResult(),
    };
  }

  // ── Menu ──────────────────────────────────────────────────────────────────

  Widget _buildMenu() {
    final cfg = _levels[_selectedLevel]!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('N-Back トレーニング'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('レベルを選択',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (i) => _LevelBtn(
                  level: i + 1,
                  selected: _selectedLevel == i + 1,
                  bestScore: _bestScores[i + 1],
                  onTap: () => setState(() => _selectedLevel = i + 1),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.accentPurple.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(_kLevelDesc[_selectedLevel]!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13,
                          height: 1.5)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _InfoChip(label: 'ラウンド', value: '${cfg.rounds}'),
                      _InfoChip(
                          label: '制限時間', value: '${cfg.time}秒'),
                      _InfoChip(label: '使用色', value: '${cfg.colors}色'),
                      _InfoChip(
                          label: '選択肢', value: '${cfg.choices}個'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('スタート',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  Widget _buildCountdown() {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween(begin: 0.6, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Text(
            '$_countdown',
            key: ValueKey(_countdown),
            style: GoogleFonts.spaceMono(
              fontSize: 120,
              fontWeight: FontWeight.w700,
              color: AppColors.accentBlue,
            ),
          ),
        ),
      ),
    );
  }

  // ── Playing ───────────────────────────────────────────────────────────────

  Widget _buildPlaying() {
    if (_step >= _seq.length) return const SizedBox.shrink();

    final isIntro = _step < _kN;
    final current = _seq[_step];
    final nc = _kColors[current.colorIndex];
    final total = _cfg.rounds + _kN;

    return Scaffold(
      backgroundColor: _flash != null
          ? Color.alphaBlend(_flash!.withOpacity(0.09), AppColors.bgPrimary)
          : AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Lv.$_selectedLevel  ${_kLevelNames[_selectedLevel]}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                      const Spacer(),
                      Text('$_step / $total',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _step / total,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(
                        AppColors.accentPurple),
                    minHeight: 3,
                  ),
                ],
              ),
            ),

            // ── Timer bar ───────────────────────────────────────────────────
            if (!isIntro)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AnimatedBuilder(
                  animation: _timerCtrl,
                  builder: (_, __) {
                    final v = _timerCtrl.value;
                    final barColor = v > 0.7
                        ? AppColors.accentRed
                        : v > 0.4
                            ? AppColors.accentOrange
                            : AppColors.accentBlue;
                    return LinearProgressIndicator(
                      value: 1 - v,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(barColor),
                      minHeight: 4,
                    );
                  },
                ),
              ),

            // ── Stimulus ────────────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: Tween(begin: 0.7, end: 1.0).animate(
                        CurvedAnimation(
                            parent: anim, curve: Curves.easeOutBack)),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Container(
                    key: ValueKey(_stimKey),
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: nc.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: nc.color.withOpacity(0.5), width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${current.number}',
                          style: GoogleFonts.spaceMono(
                            fontSize: 72,
                            fontWeight: FontWeight.w700,
                            color: nc.color,
                          ),
                        ),
                        Text(nc.name,
                            style:
                                TextStyle(color: nc.color, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Instruction ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                isIntro
                    ? '${_kN}回前の数字と色を覚えてください'
                    : '${_kN}回前はどれ？',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),

            // ── Choices ─────────────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: isIntro
                    ? const SizedBox.expand()
                    : GridView.count(
                        crossAxisCount: _choices.length <= 4 ? 2 : 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.6,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _choices
                            .map((ch) => _ChoiceBtn(
                                  choice: ch,
                                  onTap: () => _onAnswer(ch.isCorrect),
                                ))
                            .toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Result ────────────────────────────────────────────────────────────────

  Widget _buildResult() {
    final score = _calcScore();
    final g = _grade(score);
    final gc = _gradeColor(g);
    final total = _correct + _wrong;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Grade
              Text(g,
                  style: GoogleFonts.spaceMono(
                      fontSize: 88,
                      fontWeight: FontWeight.w700,
                      color: gc)),
              Text('$score%',
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w600)),
              const SizedBox(height: 28),

              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ResultStat(
                      label: '正解',
                      value: '$_correct',
                      color: AppColors.accentGreen),
                  const SizedBox(width: 32),
                  _ResultStat(
                      label: '不正解',
                      value: '$_wrong',
                      color: AppColors.accentRed),
                  const SizedBox(width: 32),
                  _ResultStat(
                      label: '合計',
                      value: '$total',
                      color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 28),

              // Round dots
              Wrap(
                spacing: 7,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: _results
                    .map((r) => Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: r == null
                                ? AppColors.accentOrange
                                : r
                                    ? AppColors.accentGreen
                                    : AppColors.accentRed,
                          ),
                        ))
                    .toList(),
              ),

              const Spacer(),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('ホーム'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          setState(() => _phase = _Phase.menu),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentPurple,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('メニューへ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _LevelBtn extends StatelessWidget {
  final int level;
  final bool selected;
  final int? bestScore;
  final VoidCallback onTap;

  const _LevelBtn({
    required this.level,
    required this.selected,
    required this.bestScore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentPurple.withOpacity(0.18)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected ? AppColors.accentPurple : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$level',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.accentPurple
                    : AppColors.textPrimary,
              ),
            ),
            Text(_kLevelNames[level]!,
                style: const TextStyle(
                    fontSize: 7, color: AppColors.textSecondary)),
            if (bestScore != null)
              Text('$bestScore%',
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.accentGreen)),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: AppColors.accentPurple)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}

class _ChoiceBtn extends StatelessWidget {
  final _Choice choice;
  final VoidCallback onTap;
  const _ChoiceBtn({required this.choice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nc = _kColors[choice.item.colorIndex];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: nc.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: nc.color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${choice.item.number}',
              style: GoogleFonts.spaceMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: nc.color),
            ),
            const SizedBox(width: 6),
            Text(nc.name,
                style: TextStyle(fontSize: 12, color: nc.color)),
          ],
        ),
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ResultStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
