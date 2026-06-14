import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/score_result.dart';

class ScoreService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> saveScore(String gameName, int score) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _db.collection('results').add({
      'gameId': 'eSports-Training',
      'gameName': gameName,
      'score': score,
      'userId': user.uid,
      'playedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<ScoreResult>> fetchHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final snap = await _db
        .collection('results')
        .where('userId', isEqualTo: user.uid)
        .orderBy('playedAt', descending: true)
        .get();
    return snap.docs.map(ScoreResult.fromDoc).toList();
  }

  static Future<void> deleteAllHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await _db
        .collection('results')
        .where('userId', isEqualTo: user.uid)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
