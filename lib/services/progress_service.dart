import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// État d'avancement stratégique et de suivi scolaire d'un élève (Firestore `user_progress/{uid}`).
/// Remplace l'ancien système de gamification (streaks, XP, niveaux RPG).
class UserProgress {
  final int metiersExplores;
  final int? matchScore; // Probabilité / indice d'alignement global (0-100)
  final List<String> metiersList;
  final Map<String, dynamic>? gapAnalysisResult; // Skill 1 : Écarts chiffrés par matière
  final Map<String, dynamic>? doubleTrajectoire; // Skill 4 : Parcours Ambition vs Plan B Réaliste
  final List<Map<String, dynamic>> weeklyExecutionPlan; // Skill 7 : Routine hebdomadaire de remédiation
  final List<Map<String, dynamic>> bulletinsHistory; // Skill 10 : Historique des checkpoints mensuels

  const UserProgress({
    required this.metiersExplores,
    this.matchScore,
    this.metiersList = const [],
    this.gapAnalysisResult,
    this.doubleTrajectoire,
    this.weeklyExecutionPlan = const [],
    this.bulletinsHistory = const [],
  });

  static const empty = UserProgress(
    metiersExplores: 0,
    metiersList: [],
    weeklyExecutionPlan: [],
    bulletinsHistory: [],
  );
}

/// Service de suivi stratégique et d'exécution quotidienne connecté à Firestore.
///
/// Document : `user_progress/{uid}`
class ProgressService {
  static DocumentReference<Map<String, dynamic>>? get _doc {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      return FirebaseFirestore.instance.collection('user_progress').doc(uid);
    } catch (_) {
      return null;
    }
  }

  static UserProgress _fromMap(Map<String, dynamic> data) {
    final rawPlan = (data['weeklyExecutionPlan'] as List<dynamic>?) ?? [];
    final rawHistory = (data['bulletinsHistory'] as List<dynamic>?) ?? [];

    return UserProgress(
      metiersExplores: (data['metiersExplores'] as num?)?.toInt() ?? 0,
      matchScore: (data['matchScore'] as num?)?.toInt(),
      metiersList: List<String>.from(data['metiersList'] ?? []),
      gapAnalysisResult: data['gapAnalysisResult'] as Map<String, dynamic>?,
      doubleTrajectoire: data['doubleTrajectoire'] as Map<String, dynamic>?,
      weeklyExecutionPlan: rawPlan
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      bulletinsHistory: rawHistory
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  /// Écoute en temps réel du dossier stratégique de l'élève
  static Stream<UserProgress> streamProgress() {
    final doc = _doc;
    if (doc == null) return Stream.value(UserProgress.empty);
    return doc.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return UserProgress.empty;
      return _fromMap(snap.data()!);
    });
  }

  /// Charge les données de suivi stratégique sans mécanique de streak ni XP
  static Future<UserProgress> loadProgress() async {
    final doc = _doc;
    if (doc == null) return UserProgress.empty;

    final snap = await doc.get();
    if (!snap.exists || snap.data() == null) {
      await doc.set({
        'metiersExplores': 0,
        'matchScore': null,
        'metiersList': <String>[],
        'gapAnalysisResult': null,
        'doubleTrajectoire': null,
        'weeklyExecutionPlan': <Map<String, dynamic>>[],
        'bulletinsHistory': <Map<String, dynamic>>[],
        'lastActiveDate': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return UserProgress.empty;
    }

    await doc.update({
      'lastActiveDate': FieldValue.serverTimestamp(),
    });

    return _fromMap(snap.data()!);
  }

  /// Enregistre le résultat d'une analyse d'orientation
  static Future<void> recordAnalysis({
    required int metiersCount,
    int? bestScore,
    List<String>? metiersNames,
  }) async {
    final doc = _doc;
    if (doc == null) return;

    final update = <String, dynamic>{
      'metiersExplores': FieldValue.increment(metiersCount),
      'lastActiveDate': FieldValue.serverTimestamp(),
    };

    if (metiersNames != null && metiersNames.isNotEmpty) {
      update['metiersList'] = FieldValue.arrayUnion(metiersNames);
    }

    if (bestScore != null) {
      update['matchScore'] = bestScore;
    }

    await doc.set(update, SetOptions(merge: true));
  }

  /// Sauvegarde le diagnostic d'écart académique (Skill 1 : Gap Analyzer)
  static Future<void> saveGapAnalysis(Map<String, dynamic> gapAnalysis) async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'gapAnalysisResult': gapAnalysis,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sauvegarde la double trajectoire Ambition vs Réaliste (Skill 4)
  static Future<void> saveDoubleTrajectoire(Map<String, dynamic> trajectoires) async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'doubleTrajectoire': trajectoires,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sauvegarde le planning hebdomadaire d'exécution (Skill 7)
  static Future<void> saveWeeklyPlan(List<Map<String, dynamic>> weeklyPlan) async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'weeklyExecutionPlan': weeklyPlan,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Ajoute un checkpoint mensuel de progression des notes et probabilités (Skill 10)
  static Future<void> recordMonthlyCheckpoint({
    required double moyenneGenerale,
    required Map<String, double> matieres,
    required int admissionProbability,
    String? filiereCible,
  }) async {
    final doc = _doc;
    if (doc == null) return;

    final entry = <String, dynamic>{
      'date': DateTime.now().toIso8601String(),
      'moyenneGenerale': moyenneGenerale,
      'matieres': matieres,
      'admissionProbability': admissionProbability,
      'filiereCible': ?filiereCible,
    };

    await doc.set({
      'bulletinsHistory': FieldValue.arrayUnion([entry]),
      'matchScore': admissionProbability,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
