import 'package:cloud_firestore/cloud_firestore.dart';

class ScoreResult {
  final String id;
  final String gameName;
  final int score;
  final String userId;
  final DateTime playedAt;

  const ScoreResult({
    required this.id,
    required this.gameName,
    required this.score,
    required this.userId,
    required this.playedAt,
  });

  factory ScoreResult.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['playedAt'];
    return ScoreResult(
      id: doc.id,
      gameName: d['gameName'] as String? ?? '',
      score: ((d['score'] ?? 0) as num).toInt(),
      userId: d['userId'] as String? ?? '',
      playedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
