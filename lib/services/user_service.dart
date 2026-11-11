import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

class UserService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  /// Synchronise la session de l'élève dans Firestore sans mécanique de streak ni XP
  static Future<void> syncUserSession(User user, {String? defaultName}) async {
    try {
      final docRef = _usersRef.doc(user.uid);
      final snapshot = await docRef.get();
      final now = DateTime.now();

      if (!snapshot.exists) {
        final name = defaultName ??
            user.displayName ??
            (user.email != null && user.email!.contains('@')
                ? user.email!.split('@')[0]
                : 'Élève');

        final initialProfile = UserProfile(
          uid: user.uid,
          email: user.email ?? '',
          displayName: name,
          classeActuelle: null,
          specialitesChoisies: const [],
          unlockedJobs: const [],
          lastMatchingScore: 0,
          lastLoginDate: now,
          createdAt: now,
        );

        await docRef.set(initialProfile.toMap());
      } else {
        await docRef.update({
          'lastLoginDate': Timestamp.fromDate(now),
        });
      }
    } catch (e) {
      debugPrint("Erreur syncUserSession: $e");
    }
  }

  /// Écoute en temps réel du profil stratégique de l'élève
  static Stream<UserProfile?> getUserProfileStream(String uid) {
    return _usersRef.doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists) {
        return UserProfile.fromFirestore(snapshot);
      }
      return null;
    });
  }

  /// Enregistre un métier ou une filière dans le dossier de l'élève
  static Future<void> unlockJob(String uid, String jobId, {int? score}) async {
    try {
      final docRef = _usersRef.doc(uid);
      final snapshot = await docRef.get();

      if (snapshot.exists) {
        final profile = UserProfile.fromFirestore(snapshot);
        final currentJobs = List<String>.from(profile.unlockedJobs);

        final updateData = <String, dynamic>{};
        if (!currentJobs.contains(jobId)) {
          currentJobs.add(jobId);
          updateData['unlockedJobs'] = currentJobs;
        }
        if (score != null) {
          updateData['lastMatchingScore'] = score;
        }
        if (updateData.isNotEmpty) {
          await docRef.update(updateData);
        }
      }
    } catch (e) {
      debugPrint("Erreur unlockJob: $e");
    }
  }

  /// Met à jour les paramètres académiques et stratégiques de l'élève
  static Future<void> updateAcademicStrategy({
    required String uid,
    String? classeActuelle,
    List<String>? specialitesChoisies,
    String? filiereAmbition,
    String? filiereRealiste,
    Map<String, double>? riasecProfile,
    List<String>? passionsDecoded,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (classeActuelle != null) updates['classeActuelle'] = classeActuelle;
      if (specialitesChoisies != null) updates['specialitesChoisies'] = specialitesChoisies;
      if (filiereAmbition != null) updates['filiereAmbition'] = filiereAmbition;
      if (filiereRealiste != null) updates['filiereRealiste'] = filiereRealiste;
      if (riasecProfile != null) updates['riasecProfile'] = riasecProfile;
      if (passionsDecoded != null) updates['passionsDecoded'] = passionsDecoded;

      if (updates.isNotEmpty) {
        await _usersRef.doc(uid).set(updates, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Erreur updateAcademicStrategy: $e");
    }
  }

  /// Mise à jour du nom affiché
  static Future<void> updateDisplayName(String uid, String newName) async {
    try {
      await _usersRef.doc(uid).update({'displayName': newName});
    } catch (e) {
      debugPrint("Erreur updateDisplayName: $e");
    }
  }
}
