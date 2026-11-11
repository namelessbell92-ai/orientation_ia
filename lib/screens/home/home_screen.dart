import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';

/// Module 3 : Exécution Quotidienne & Remédiation (Skills 7, 8 & Synthèse Stratégique).
/// - Skill 7 : Générateur de Planning hebdomadaire adapté aux lacunes
/// - Skill 8 : Entraîneur Adaptatif (micro-exercices ciblés avec méthode de résolution)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserProgress _progress = UserProgress.empty;
  bool _isLoading = true;
  bool _isGeneratingPlan = false;
  final Set<int> _completedSlots = {};
  final Set<int> _revealedMethods = {};
  List<Map<String, dynamic>> _microExercices = [];

  String get _userName {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
        return user.displayName!.trim();
      }
      final email = user?.email;
      if (email != null && email.contains('@')) {
        final name = email.split('@').first;
        if (name.isNotEmpty) {
          return name[0].toUpperCase() + name.substring(1);
        }
      }
    } catch (_) {}
    return "Élève";
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final progress = await ProgressService.loadProgress();
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _isLoading = false;
      });
      if (_progress.weeklyExecutionPlan.isNotEmpty) {
        await _refreshExercisesOnly();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshExercisesOnly() async {
    try {
      final gap = _progress.gapAnalysisResult;
      if (gap == null) return;
      final ecarts = (gap["ecarts_matieres"] as List?) ?? [];
      final Map<String, double> matieresMap = {};
      for (final item in ecarts) {
        if (item is Map && item["matiere"] != null && item["note_actuelle"] is num) {
          matieresMap[item["matiere"].toString()] =
              (item["note_actuelle"] as num).toDouble();
        }
      }
      if (matieresMap.isEmpty) return;

      final res = await ApiService.generateWeeklyPlan({
        "filiere_ambition_id": gap["filiere_cible_id"],
        "bulletin": {
          "matieres": matieresMap,
        }
      });
      if (!mounted) return;
      final exList = (res["micro_exercices"] as List?) ?? [];
      setState(() {
        _microExercices = exList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _generateDefaultOrUpdatedPlan({bool silent = false}) async {
    final gap = _progress.gapAnalysisResult;
    final ecarts = (gap?["ecarts_matieres"] as List?) ?? [];
    final Map<String, double> matieresMap = {};
    for (final item in ecarts) {
      if (item is Map && item["matiere"] != null && item["note_actuelle"] is num) {
        matieresMap[item["matiere"].toString()] =
            (item["note_actuelle"] as num).toDouble();
      }
    }
    if (matieresMap.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saisis d'abord tes notes et lance l'analyse d'écart dans l'onglet Profil & Notes."),
          ),
        );
      }
      return;
    }

    if (!silent) {
      setState(() => _isGeneratingPlan = true);
    }
    try {
      final res = await ApiService.generateWeeklyPlan({
        "filiere_ambition_id": gap?["filiere_cible_id"],
        "bulletin": {
          "matieres": matieresMap,
        }
      });

      if (res.containsKey("weekly_plan")) {
        final rawPlan = (res["weekly_plan"] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final rawEx = ((res["micro_exercices"] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        await ProgressService.saveWeeklyPlan(rawPlan);
        final updatedProgress = await ProgressService.loadProgress();

        if (mounted) {
          setState(() {
            _progress = updatedProgress;
            _microExercices = rawEx;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted && !silent) {
        setState(() => _isGeneratingPlan = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trajectoire = _progress.doubleTrajectoire;
    final gap = _progress.gapAnalysisResult;
    final ambitionTitle = trajectoire?['parcours_ambition']?['titre'] as String? ??
        gap?['filiere_cible'] as String? ??
        "Aucune filière sélectionnée";
    final realisteTitle = trajectoire?['parcours_realiste']?['titre'] as String? ??
        "Non défini";
    final probAdmission = (gap?['probabilite_admission'] as num?)?.toInt() ??
        _progress.matchScore;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.track_changes_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Exécution & Remédiation',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
                fontSize: 18,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isGeneratingPlan
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, color: AppTheme.primary, size: 22),
            tooltip: "Recalculer le planning hebdomadaire",
            onPressed: _isGeneratingPlan
                ? null
                : () => _generateDefaultOrUpdatedPlan(silent: false),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coach d\'Exécution • $_userName',
                    style: const TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Transforme l\'écart entre tes notes actuelles et ta filière visée en plan d\'action concret.',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Carte Synthèse : Cap Stratégique
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'TRAJECTOIRE CIBLE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10.5,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (probAdmission != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Admissibilité : $probAdmission%',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          ambitionTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Plan B sécurisé : $realisteTitle',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==========================================================
                  // PLANNING HEBDOMADAIRE
                  // ==========================================================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Planning de Remédiation',
                          style: TextStyle(
                            color: AppTheme.textMain,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Text(
                        '${_completedSlots.length}/${_progress.weeklyExecutionPlan.length} faits',
                        style: const TextStyle(
                          color: AppTheme.accentEmerald,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Créneaux calibrés sur les matières où ton écart au seuil d\'admission est négatif.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),

                  if (_progress.weeklyExecutionPlan.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: const Text(
                        "Aucun créneau généré. Saisis tes notes dans l'onglet Profil & Notes puis clique sur le bouton d'actualisation en haut à droite.",
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    )
                  else
                    ...List.generate(_progress.weeklyExecutionPlan.length, (index) {
                      final slot = _progress.weeklyExecutionPlan[index];
                      final isDone = _completedSlots.contains(index);
                      final jour = slot['jour'] ?? 'Jour';
                      final creneau = slot['creneau'] ?? '18h00 - 18h45';
                      final matiere = slot['matiere'] ?? 'Matière';
                      final objectif = slot['objectif'] ?? '';
                      final duree = slot['duree_minutes'] ?? 45;
                      final delta = (slot['delta_cible'] as num?)?.toDouble() ?? 0.0;

                      final Color badgeColor = delta < -2.0
                          ? AppTheme.accentCoral
                          : (delta < 0 ? AppTheme.accentAmber : AppTheme.accentEmerald);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isDone) {
                              _completedSlots.remove(index);
                            } else {
                              _completedSlots.add(index);
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDone
                                ? AppTheme.accentEmeraldSoft.withValues(alpha: 0.45)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDone
                                  ? AppTheme.accentEmerald.withValues(alpha: 0.5)
                                  : AppTheme.borderColor,
                            ),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  isDone
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: isDone
                                      ? AppTheme.accentEmerald
                                      : AppTheme.textMuted,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '$jour • $creneau',
                                          style: const TextStyle(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$duree min',
                                            style: TextStyle(
                                              color: badgeColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      matiere,
                                      style: TextStyle(
                                        color: AppTheme.textMain,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                        decoration: isDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      objectif,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12.5,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  // ==========================================================
                  // ENTRAÎNEUR ADAPTATIF
                  // ==========================================================
                  const Text(
                    'Entraîneur Adaptatif',
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Micro-exercices méthodologiques ciblés sur tes matières prioritaires.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),

                  ...List.generate(_microExercices.length, (i) {
                    final ex = _microExercices[i];
                    final isRevealed = _revealedMethods.contains(i);
                    final mat = ex['matiere'] ?? 'Matière';
                    final delta = ex['delta'] ?? 0.0;
                    final question = ex['question'] ?? '';
                    final methode = ex['methode'] ?? '';
                    final objChiffre = ex['objectif_chiffre'] ?? '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primarySoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  mat,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Écart : ${delta >= 0 ? "+$delta" : "$delta"} pt(s)',
                                style: TextStyle(
                                  color: (delta as num) < 0
                                      ? AppTheme.accentCoral
                                      : AppTheme.accentEmerald,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            question,
                            style: const TextStyle(
                              color: AppTheme.textMain,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.flag_outlined,
                                  color: AppTheme.accentEmerald, size: 15),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  objChiffre,
                                  style: const TextStyle(
                                    color: AppTheme.accentEmerald,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (isRevealed)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Méthode de résolution attendue :',
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    methode,
                                    style: const TextStyle(
                                      color: AppTheme.textMain,
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: Icon(
                                isRevealed
                                    ? Icons.visibility_off_outlined
                                    : Icons.lightbulb_outline_rounded,
                                size: 16,
                              ),
                              label: Text(
                                isRevealed
                                    ? "Masquer le corrigé méthodologique"
                                    : "Voir la méthode de résolution",
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isRevealed) {
                                    _revealedMethods.remove(i);
                                  } else {
                                    _revealedMethods.add(i);
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}