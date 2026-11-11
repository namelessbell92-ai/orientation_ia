import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle de profil stratégique de l'élève (stocké dans Firestore `users/{uid}`).
/// Expurgé de toute mécanique RPG (streaks, XP, niveaux, ligues).
class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? classeActuelle;
  final List<String> specialitesChoisies;
  final String? filiereAmbition;
  final String? filiereRealiste;
  final Map<String, double> riasecProfile; // R, I, A, S, E, C
  final List<String> passionsDecoded;
  final List<String> unlockedJobs;
  final int lastMatchingScore;
  final DateTime lastLoginDate;
  final DateTime createdAt;

  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.classeActuelle,
    this.specialitesChoisies = const [],
    this.filiereAmbition,
    this.filiereRealiste,
    this.riasecProfile = const {},
    this.passionsDecoded = const [],
    required this.unlockedJobs,
    required this.lastMatchingScore,
    required this.lastLoginDate,
    required this.createdAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final rawRiasec = data['riasecProfile'] as Map<String, dynamic>? ?? {};
    final parsedRiasec = <String, double>{};
    rawRiasec.forEach((key, value) {
      if (value is num) {
        parsedRiasec[key] = value.toDouble();
      }
    });

    return UserProfile(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'Élève',
      classeActuelle: data['classeActuelle'] as String?,
      specialitesChoisies: List<String>.from(data['specialitesChoisies'] ?? []),
      filiereAmbition: data['filiereAmbition'] as String?,
      filiereRealiste: data['filiereRealiste'] as String?,
      riasecProfile: parsedRiasec,
      passionsDecoded: List<String>.from(data['passionsDecoded'] ?? []),
      unlockedJobs: List<String>.from(data['unlockedJobs'] ?? []),
      lastMatchingScore: (data['lastMatchingScore'] as num?)?.toInt() ?? 0,
      lastLoginDate: parseDate(data['lastLoginDate']),
      createdAt: parseDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'classeActuelle': classeActuelle,
      'specialitesChoisies': specialitesChoisies,
      'filiereAmbition': filiereAmbition,
      'filiereRealiste': filiereRealiste,
      'riasecProfile': riasecProfile,
      'passionsDecoded': passionsDecoded,
      'unlockedJobs': unlockedJobs,
      'lastMatchingScore': lastMatchingScore,
      'lastLoginDate': Timestamp.fromDate(lastLoginDate),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
