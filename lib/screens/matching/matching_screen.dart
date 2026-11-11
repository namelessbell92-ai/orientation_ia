import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/progress_service.dart';
import '../../services/voice_service.dart';
import '../../theme/app_theme.dart';
import '../nova/nova_chat_screen.dart';

enum VoiceSessionState { idle, listening, thinking, speaking }

class MatchingScreen extends StatefulWidget {
  final Map<String, dynamic>? profileData;

  const MatchingScreen({super.key, this.profileData});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasError = false;
  Map<String, dynamic>? _doubleTrajectoire;
  int _selectedStrategyTab = 0; // 0: Double Voie, 1: Spécialités
  int? _selectedImpactCategory; // null: aucun, 0: Ouvertes, 1: En vigilance, 2: Bloquées
  int _selectedPole = 1; // 0: Sécurité, 1: Cible, 2: Ambition
  bool _isRegional = false; // false: National, true: Régional
  int _slidingWindowStart = 0; // 0 -> 1-3, 1 -> 2-4, 2 -> 3-5, etc.
  Map<String, dynamic>? _selectedLycee;

  Map<String, dynamic>? _activeProfile;

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.profileData;

    if (_activeProfile != null) {
      _fetchAnalysis();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchAnalysis() async {
    final data = _activeProfile ?? widget.profileData;
    if (data == null) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    final stopwatch = Stopwatch()..start();

    final result = await ApiService.getOrientationAnalysis(
      creativite: (data["creativite"] as num?)?.toInt() ?? 0,
      empathie: (data["empathie"] as num?)?.toInt() ?? 0,
      communication: (data["communication"] as num?)?.toInt() ?? 0,
      organisation: (data["organisation"] as num?)?.toInt() ?? 0,
      logique: (data["logique"] as num?)?.toInt() ?? 0,
      classeActuelle: data["classe_actuelle"] as String?,
      specialitesChoisies: (data["specialites_choisies"] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      filiereAmbitionId: data["filiere_ambition_id"] as String?,
      riasecScores: (data["riasec_scores"] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      passionsBrutes: (data["passions_brutes"] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      preferencesSociales: data["preferences_sociales"] as String?,
      environnementPrefere: data["environnement_prefere"] as String?,
      secteursSouhaits: (data["secteurs_souhaits"] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      roleVise: data["role_vise"] as String?,
      styleVie: data["style_vie"] as String?,
      mbtiArchetype: data["mbti_archetype"] as String?,
      bulletin: data["bulletin"] as Map<String, dynamic>?,
      lyceeNom: (_selectedLycee?["nom"] ?? data["lycee_nom"]) as String?,
      lyceeVille: (_selectedLycee?["ville"] ?? data["lycee_ville"]) as String?,
      lyceeRegion: (_selectedLycee?["region"] ?? data["lycee_region"]) as String?,
      lyceeBonusSelectivite: ((_selectedLycee?["bonus_selectivite"] ?? data["lycee_bonus_selectivite"]) as num?)?.toDouble(),
    );

    // Permettre à l'animation cinématographique de réflexion IA de s'exécuter avec fluidité (~2,6 secondes)
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 2600) {
      await Future.delayed(Duration(milliseconds: 2600 - elapsed));
    }

    if (result.containsKey("error")) {
      if (mounted) {
        setState(() {
          _errorMessage = result["error"];
          _hasError = true;
          _isLoading = false;
        });
      }
      return;
    }

    final topMetiers = (result["top_metiers"] as List?) ?? [];
    final gapAnalysis = result["gap_analysis"] as Map<String, dynamic>?;
    final doubleTrajectoire = result["double_trajectoire"] as Map<String, dynamic>?;
    final executionPlan = result["execution_plan"] as Map<String, dynamic>?;

    // Affichage du résultat avec transition fluide
    if (mounted) {
      setState(() {
        _doubleTrajectoire = doubleTrajectoire;
        if (_selectedLycee == null && doubleTrajectoire?["lycee_analyse"] != null) {
          _selectedLycee = Map<String, dynamic>.from(doubleTrajectoire!["lycee_analyse"] as Map);
        }
        _isLoading = false;
        _hasError = false;
      });
    }

    // Sauvegarde du suivi stratégique en tâche de fond (Modules 1, 2, 3, 4)
    try {
      final admissionProb = (gapAnalysis?["probabilite_admission"] as num?)?.toInt() ??
          (topMetiers.isNotEmpty
              ? (topMetiers.first["compatibilite"] as num?)?.toInt()
              : null);
      final metiersNames = topMetiers
          .map((m) => (m["nom"] as String?) ?? "")
          .where((n) => n.isNotEmpty)
          .toList();

      await ProgressService.recordAnalysis(
        metiersCount: topMetiers.length,
        bestScore: admissionProb,
        metiersNames: metiersNames,
      );

      if (gapAnalysis != null) {
        await ProgressService.saveGapAnalysis(gapAnalysis);
      }
      if (doubleTrajectoire != null) {
        await ProgressService.saveDoubleTrajectoire(doubleTrajectoire);
      }
      if (executionPlan != null && executionPlan["weekly_plan"] is List) {
        final rawPlan = (executionPlan["weekly_plan"] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        await ProgressService.saveWeeklyPlan(rawPlan);
      }
    } catch (e) {
      debugPrint("Erreur sauvegarde progression : $e");
    }
  }

  void _showMetierDetailModal(BuildContext context, Map<String, dynamic> metier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MetierDetailModalSheet(
        metier: metier,
        activeProfile: _activeProfile ?? widget.profileData,
        onOpenDebate: () {
          Navigator.pop(ctx);
          _openDebateModal(context, metier);
        },
      ),
    );
  }

  void _openDebateModal(BuildContext context, Map<String, dynamic> metier, {String? initialObjection}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DebateModalSheet(
        metier: metier,
        initialObjection: initialObjection,
        activeProfile: _activeProfile ?? widget.profileData,
        onOpenMetierDetail: (altMap) => _showMetierDetailModal(context, altMap),
      ),
    );
  }

  String _shortFiliereTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'\s*\(Plan B[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(Grandes Prépas[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(INSA, UT[^)]*\)', caseSensitive: false), '')
        .trim();
  }

  String _shortBullet(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    if (cleaned.length <= 68) return cleaned;
    return "${cleaned.substring(0, 65).trim()}…";
  }

  Widget _buildSelectivityTierBadge(int group, String label) {
    late final Color bgColor;
    late final Color borderColor;
    late final Color textColor;
    late final Color iconColor;
    late final IconData iconData;

    if (group == 1) {
      bgColor = const Color(0xFF3B0764);
      borderColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFFEF3C7);
      iconColor = const Color(0xFFFBBF24);
      iconData = Icons.workspace_premium_outlined;
    } else if (group == 2) {
      bgColor = const Color(0xFF1E3A8A);
      borderColor = const Color(0xFF3B82F6);
      textColor = Colors.white;
      iconColor = const Color(0xFF93C5FD);
      iconData = Icons.school_outlined;
    } else {
      bgColor = const Color(0xFF047857);
      borderColor = const Color(0xFF10B981);
      textColor = Colors.white;
      iconColor = const Color(0xFFA7F3D0);
      iconData = Icons.verified_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrajectoryCard(Map<String, dynamic> traj, {required bool isAmbition}) {
    final titre = _shortFiliereTitle(traj["titre"]?.toString() ?? "Filière");
    final ville = (traj["ville"] ?? "").toString().trim();
    final tauxAcces = (traj["taux_acces_parcoursup"] as num?)?.toInt() ?? 25;
    final probEleve = (traj["probabilite_eleve"] as num?)?.toInt() ?? 55;
    final moyAttendue = traj["moyenne_attendue"] ?? 14.0;
    final selectivityGroup = (traj["selectivity_group"] as num?)?.toInt() ?? (isAmbition ? 2 : 3);
    final rankingLabel = (traj["ranking_label"] ??
            (selectivityGroup == 1
                ? "Groupe 1 : Cibles Top Concours (X, ENS, HEC)"
                : (selectivityGroup == 2
                    ? "Groupe 2 : Cibles Grandes Écoles Nationales"
                    : "Groupe 3 : Accès Régional & Tremplin Sécurisé")))
        .toString();
    final conditions = (traj["conditions_acces"] as List?)?.map((e) => e.toString()).toList() ?? [];
    final mythes = (traj["casseur_de_mythes"] as Map<String, dynamic>?) ?? {};

    final Color accent = isAmbition ? AppTheme.primary : AppTheme.accentEmerald;
    final Color softBg = isAmbition ? AppTheme.primarySoft : AppTheme.accentEmeraldSoft;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.4),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Badge Voie + Score visuel
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: softBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAmbition ? "VOIE AMBITION (EXCELLENCE)" : "VOIE SÉCURITÉ (PLAN B)",
                  style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Chances estimées : $probEleve%",
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1b. Badge Groupe de Sélectivité (Or/Violet, Bleu Marine, Vert Émeraude)
          _buildSelectivityTierBadge(selectivityGroup, rankingLabel),
          const SizedBox(height: 10),

          // 2. Titre court et percutant + Ville
          Text(
            titre,
            style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 16.5, height: 1.25),
          ),
          if (ville.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  ville,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // 3. Barre de progression visuelle des chances d'admission
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (probEleve / 100.0).clamp(0.08, 1.0),
              minHeight: 7,
              backgroundColor: AppTheme.background,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 12),

          // 4. 2 Chiffres clés visuels côte à côte
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Objectif moyenne", style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                            Text("~$moyAttendue / 20", style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people_alt_outlined, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Sélectivité", style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                            Text("$tauxAcces% d'admis", style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 5. 2 points clés ultra-courts (lecture en 3 secondes)
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...conditions.take(2).map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 15, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _shortBullet(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMain, fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          // 6. Accordéon optionnel (fermé par défaut) pour ne pas noyer l'élève sous le texte
          if (mythes.isNotEmpty || conditions.length > 2) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                visualDensity: VisualDensity.compact,
                collapsedBackgroundColor: AppTheme.accentAmberSoft.withValues(alpha: 0.6),
                backgroundColor: AppTheme.accentAmberSoft.withValues(alpha: 0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.bolt_rounded, color: AppTheme.accentAmber, size: 18),
                title: const Text(
                  "En savoir plus (exigences & rythme réel)",
                  style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                children: [
                  if (mythes['realite_terrain'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        "${mythes['realite_terrain']}",
                        style: const TextStyle(color: AppTheme.textMain, fontSize: 12, height: 1.35),
                      ),
                    ),
                  if (mythes['rythme_hebdo'] != null)
                    Text(
                      "Rythme hebdomadaire : ${mythes['rythme_hebdo']}",
                      style: const TextStyle(color: AppTheme.primary, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ],

          // 7. Mention discrète de source certifiée en bas de carte
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_outlined, size: 13, color: AppTheme.textMuted),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    "Source : Données certifiées MESR / Classements de référence",
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialitesSimulatorView() {
    final impact = (_doubleTrajectoire?["impact_specialites"] as Map<String, dynamic>?) ?? {};
    final specsActuelles = (impact["specialites_actuelles"] as List?)?.map((e) => e.toString()).toList() ?? [];
    final ouvertes = (impact["filieres_ouvertes"] as List?) ?? [];
    final vigilance = (impact["filieres_vigilance"] as List?) ?? [];
    final fermees = (impact["filieres_fermees"] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Vos spécialités en badges visuels
          if (specsActuelles.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: specsActuelles
                  .map(
                    (sp) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        sp,
                        style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            const Text(
              "Aucune spécialité sélectionnée",
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          const SizedBox(height: 14),

          // 2. 3 Compteurs cliquables côte à côte (affiche uniquement la catégorie cliquée)
          Row(
            children: [
              Expanded(
                child: _buildMiniImpactCounter(
                  categoryIndex: 0,
                  count: ouvertes.length,
                  label: "Ouvertes",
                  color: AppTheme.accentEmerald,
                  bgColor: AppTheme.accentEmeraldSoft,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniImpactCounter(
                  categoryIndex: 1,
                  count: vigilance.length,
                  label: "En vigilance",
                  color: AppTheme.accentAmber,
                  bgColor: AppTheme.accentAmberSoft,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniImpactCounter(
                  categoryIndex: 2,
                  count: fermees.length,
                  label: "Bloquées",
                  color: AppTheme.accentCoral,
                  bgColor: AppTheme.accentCoral.withValues(alpha: 0.12),
                  icon: Icons.lock_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Affichage uniquement de la catégorie sélectionnée au clic
          if (_selectedImpactCategory == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_outlined, size: 18, color: AppTheme.textMuted),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "Cliquez sur « Ouvertes », « En vigilance » ou « Bloquées » pour voir le détail",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else if (_selectedImpactCategory == 0)
            ouvertes.isEmpty
                ? _buildEmptyCategoryBanner("Aucune filière ouverte à 100% avec cette combinaison.")
                : _buildCompactImpactGroup(
                    title: "Portes Ouvertes (${ouvertes.length})",
                    color: AppTheme.accentEmerald,
                    bgColor: AppTheme.accentEmeraldSoft,
                    entries: ouvertes
                        .map((f) => {
                              "nom": _shortFiliereTitle(f["nom"]?.toString() ?? ""),
                              "tag": "",
                            })
                        .toList(),
                    isChipGrid: true,
                  )
          else if (_selectedImpactCategory == 1)
            vigilance.isEmpty
                ? _buildEmptyCategoryBanner("Aucune filière en vigilance.")
                : _buildCompactImpactGroup(
                    title: "En Vigilance (${vigilance.length})",
                    color: AppTheme.accentAmber,
                    bgColor: AppTheme.accentAmberSoft,
                    entries: vigilance
                        .map((f) => {
                              "nom": _shortFiliereTitle(f["nom"]?.toString() ?? ""),
                              "tag": (f["alerte"]?.toString() ?? "").replaceFirst("Spécialité manquante : ", "Manque : "),
                            })
                        .toList(),
                    isChipGrid: false,
                  )
          else if (_selectedImpactCategory == 2)
            fermees.isEmpty
                ? _buildEmptyCategoryBanner("Aucune filière bloquée.")
                : _buildCompactImpactGroup(
                    title: "Portes Fermées (${fermees.length})",
                    color: AppTheme.accentCoral,
                    bgColor: AppTheme.accentCoral.withValues(alpha: 0.1),
                    entries: fermees
                        .map((f) => {
                              "nom": _shortFiliereTitle(f["nom"]?.toString() ?? ""),
                              "tag": f["raison"]?.toString() ?? "",
                            })
                        .toList(),
                    isChipGrid: false,
                  ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEmptyCategoryBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _buildMiniImpactCounter({
    required int categoryIndex,
    required int count,
    required String label,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    final bool isSelected = _selectedImpactCategory == categoryIndex;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedImpactCategory = isSelected ? null : categoryIndex;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.35),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected ? AppTheme.softShadow : null,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 5),
                Text(
                  "$count",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? color : AppTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isSelected ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: isSelected ? color : AppTheme.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactImpactGroup({
    required String title,
    required Color color,
    required Color bgColor,
    required List<Map<String, String>> entries,
    required bool isChipGrid,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (isChipGrid)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entries
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: bgColor.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: color),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              e["nom"] ?? "",
                              style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e["nom"] ?? "",
                        style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                    if ((e["tag"] ?? "").isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            e["tag"]!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          "Stratégie GPS",
          style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, letterSpacing: -0.3, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textMain),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: (_activeProfile == null && widget.profileData == null) && _doubleTrajectoire == null && !_isLoading
            ? Center(
                key: const ValueKey('empty_state'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.alt_route_rounded, size: 48, color: AppTheme.primaryLight),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Aucune Stratégie GPS Générée",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textMain, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Renseigne ta classe, tes spécialités et ton bulletin dans « Profil & Notes » pour afficher ta Double Voie et l'impact de tes spécialités.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppTheme.textMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              )
            : _isLoading
                ? _AiThinkingWidget(
                    key: const ValueKey('ai_thinking'),
                    profileData: _activeProfile ?? widget.profileData,
                  )
                : _hasError
                    ? Center(
                        key: const ValueKey('error_state'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage ?? "Impossible de joindre le serveur.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Réessayer"),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                                  onPressed: _fetchAnalysis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Column(
                        key: const ValueKey('results_content'),
                        children: [
                          // Sélecteur des 2 vues : Double Voie | Spécialités (sans la rubrique Métiers)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBgElevated,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.borderColor),
                              ),
                              child: Row(
                                children: [
                                  _buildStrategySegmentButton(0, "1. Double Voie"),
                                  _buildStrategySegmentButton(1, "2. Spécialités"),
                                ],
                              ),
                            ),
                          ),

                          Expanded(
                            child: _selectedStrategyTab == 1 && _doubleTrajectoire != null
                                ? _buildSpecialitesSimulatorView()
                                : _buildTripleTrajectoryView(),
                          ),
                        ],
                      ),
      ),
    );
  }


  // ==========================================
  //  NOUVELLE ARCHITECTURE STRATÉGIE GPS :
  //  3 PÔLES, TOP 10 PAR BRIQUES DE 3 & LYCÉE IVAL
  // ==========================================

  Widget _buildTripleTrajectoryView() {
    if (_doubleTrajectoire == null) {
      return const Center(child: Text("Aucune trajectoire disponible pour le moment."));
    }

    final poles = (_doubleTrajectoire?["poles_trajectoire"] as Map<String, dynamic>?) ?? {};
    final lyceeData = _selectedLycee ?? (_doubleTrajectoire?["lycee_analyse"] as Map<String, dynamic>?);
    final regionEleve = (lyceeData?["region"] ?? "Ile-de-France").toString();

    // Détermination du pôle sélectionné
        // Détermination du pôle sélectionné (4 pôles : Sécurité, Cible, Ambition, Voie Royale)
    final poleKeys = ["securite", "cible", "ambition", "voie_royale"];
    final currentKey = poleKeys[_selectedPole.clamp(0, 3)];
    final currentPole = (poles[currentKey] as Map<String, dynamic>?) ?? {};

    // Liste des formations (National, Régional ou Top 10 Voie Royale)
    final List formationsListRaw;
    if (_selectedPole == 3) {
      formationsListRaw = ((poles["voie_royale_elite"] as List?) ??
          (_doubleTrajectoire?["voie_royale_elite"] as List?) ??
          []);
    } else {
      formationsListRaw = _isRegional
          ? ((currentPole["regional"] as List?) ?? [])
          : ((currentPole["national"] as List?) ?? []);
    }
final formations = formationsListRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Fenêtre glissante par brique de 3
    final total = formations.length;
    final start = _slidingWindowStart.clamp(0, total > 0 ? total - 1 : 0);
    final end = (start + 3).clamp(0, total);
    final currentBrique = total > 0 ? formations.sublist(start, end) : <Map<String, dynamic>>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. CARTE LYCÉE D'ORIGINE & ÉTALONNAGE IVAL
          _buildLyceeCalibrationCard(lyceeData),
          const SizedBox(height: 14),

          // 2. SÉLECTEUR DES 3 PÔLES DE TRAJECTOIRE
          _buildPolesSelector(poles),
          const SizedBox(height: 14),

          // 3. BASCULE GÉOGRAPHIQUE (NATIONAL VS RÉGIONAL)
          // 3. BASCULE GÉOGRAPHIQUE (OU BANDEAU VOIE ROYALE)
          if (_selectedPole == 3)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF7EE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.stars_rounded, color: Color(0xFFB8860B), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Voie d'Élite : Le Top 10 National d'excellence dans ta filière.",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4305)),
                    ),
                  ),
                ],
              ),
            )
          else
            _buildGeoSelector(regionEleve),
          const SizedBox(height: 12),

          // 4. CONTRÔLEUR DE PROGRESSION (BRIQUES DE 3 SUR TOP 10)
          if (total > 0)
            _buildSlidingWindowControls(start: start, end: end, total: total),
          const SizedBox(height: 12),

          // 5. LISTE DES FORMATIONS (BRIQUE DE 3)
          if (currentBrique.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedPole == 0 ? Icons.shield_outlined : Icons.info_outline_rounded,
                    size: 28,
                    color: _selectedPole == 0 ? AppTheme.accentCoral : AppTheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    currentPole["note"]?.toString() ??
                        (_isRegional
                            ? "Aucune formation trouvée dans ton bassin géographique pour ce pôle. Bascule sur 'Toute la France (National)' pour voir les opportunités nationales."
                            : "Aucune formation trouvée pour ce pôle."),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                  ),
                  if (_isRegional && _selectedPole == 2) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.public, size: 16),
                      label: const Text("Voir le Top National (Toute la France)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () => setState(() {
                        _isRegional = false;
                        _slidingWindowStart = 0;
                      }),
                    ),
                  ],
                ],
              ),
            )
          else
            ...currentBrique.asMap().entries.map((entry) {
              final idx = entry.key;
              final f = entry.value;
              final globalRank = start + idx + 1;
              return _buildFormationItemCard(f, globalRank);
            }),

          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 1. Carte Lycée d'Origine & Étalonnage de la sélectivité IVAL
  Widget _buildLyceeCalibrationCard(Map<String, dynamic>? lycee) {
    final hasLycee = lycee != null && (lycee["nom"]?.toString().trim().isNotEmpty ?? false);
    final nom = hasLycee ? lycee!["nom"].toString() : "Lycée non renseigné";
    final ville = hasLycee ? (lycee!["ville"] ?? "").toString() : "";
    final region = hasLycee ? (lycee!["region"] ?? "").toString() : "Région inconnue";
    final bonus = hasLycee ? ((lycee!["bonus_selectivite"] as num?)?.toDouble() ?? 0.0) : 0.0;
    final tauxMentions = hasLycee ? ((lycee!["taux_mentions"] as num?)?.toDouble() ?? 0.0) : 0.0;
    final moyBrute = (lycee?["moyenne_brute"] as num?)?.toDouble() ?? 13.5;
    final moyPonderee = (lycee?["moyenne_ponderee"] as num?)?.toDouble() ?? (moyBrute + bonus);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 1.2),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.school_outlined, size: 18, color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Lycée d'origine & Étalonnage Parcoursup",
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      nom,
                      style: const TextStyle(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 13),
                label: Text(hasLycee ? "Modifier" : "Renseigner", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  side: const BorderSide(color: AppTheme.primary, width: 1),
                  foregroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showLyceeSelectionDialog,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bonus > 0 ? AppTheme.accentEmeraldSoft : AppTheme.cardBgElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  bonus > 0 ? Icons.verified_outlined : Icons.info_outline_rounded,
                  size: 15,
                  color: bonus > 0 ? AppTheme.accentEmerald : AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasLycee
                        ? (bonus > 0
                            ? "Lycée de référence (${tauxMentions.toStringAsFixed(0)}% mentions) : +${bonus.toStringAsFixed(1)} pt de pondération estimée en commission."
                            : "$ville ($region) · Évaluation sur moyenne brute.")
                        : "Renseigne ton lycée pour étalonner la sélectivité réelle de tes notes selon le classement officiel IVAL.",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: bonus > 0 ? AppTheme.accentEmerald : AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (bonus > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  "Moyenne brute : ${moyBrute.toStringAsFixed(2)} / 20",
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                ),
                Text(
                  "Pondérée commission : ${moyPonderee.toStringAsFixed(2)} / 20",
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 2. Sélecteur des 3 Pôles : Sécurité, Cible, Ambition
    Widget _buildPolesSelector(Map<String, dynamic> poles) {
    final items = [
      {
        "title": "1. Sécurité",
        "sub": "Socle Garanti",
        "color": AppTheme.accentEmerald,
        "bg": AppTheme.accentEmeraldSoft,
        "key": "securite",
      },
      {
        "title": "2. Cible",
        "sub": "Niveau Réel",
        "color": AppTheme.primary,
        "bg": AppTheme.primarySoft,
        "key": "cible",
      },
      {
        "title": "3. Ambition",
        "sub": "Défi Sélectif",
        "color": const Color(0xFF4A3E8A),
        "bg": const Color(0xFF4A3E8A).withValues(alpha: 0.1),
        "key": "ambition",
      },
      {
        "title": "4. Élite",
        "sub": "Top National",
        "color": const Color(0xFFB8860B),
        "bg": const Color(0xFFD4AF37).withValues(alpha: 0.15),
        "key": "voie_royale",
      },
    ];

    return Row(
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final it = entry.value;
        final isSel = _selectedPole == idx;
        final c = it["color"] as Color;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedPole = idx;
                _slidingWindowStart = 0; // Réinitialise la fenêtre au départ du pôle
              });
            },
            child: Container(
              margin: EdgeInsets.only(right: idx < 3 ? 5 : 0),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: isSel ? c : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSel ? c : AppTheme.borderColor,
                  width: isSel ? 1.5 : 1.0,
                ),
                boxShadow: isSel ? AppTheme.softShadow : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    it["title"] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSel ? Colors.white : AppTheme.textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    it["sub"] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSel ? Colors.white.withValues(alpha: 0.85) : AppTheme.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

Widget _buildGeoSelector(String regionName) {
    final cleanRegion = regionName.isEmpty ? "Ma Région" : regionName;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardBgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _isRegional = false;
                _slidingWindowStart = 0;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: !_isRegional ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !_isRegional ? AppTheme.softShadow : null,
                ),
                child: Text(
                  "Toute la France (National)",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: !_isRegional ? FontWeight.bold : FontWeight.w600,
                    color: !_isRegional ? AppTheme.primary : AppTheme.textMuted,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _isRegional = true;
                _slidingWindowStart = 0;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _isRegional ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _isRegional ? AppTheme.softShadow : null,
                ),
                child: Text(
                  "Bassin : $cleanRegion",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _isRegional ? FontWeight.bold : FontWeight.w600,
                    color: _isRegional ? AppTheme.primary : AppTheme.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. Contrôleur de fenêtre glissante (Brique de 3 sur Top 10)
  Widget _buildSlidingWindowControls({required int start, required int end, required int total}) {
    final canPrev = start > 0;
    final canNext = end < total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: canPrev
                ? () => setState(() => _slidingWindowStart = (_slidingWindowStart - 1).clamp(0, total - 1))
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.chevron_left_rounded, size: 18, color: canPrev ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(width: 2),
                  Text(
                    "Précédent",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: canPrev ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Rangs ${start + 1} à $end sur $total",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
          ),
          InkWell(
            onTap: canNext
                ? () => setState(() => _slidingWindowStart = (_slidingWindowStart + 1).clamp(0, total - 1))
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Text(
                    "Suivant",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: canNext ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: canNext ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 5. Carte détaillée pour chaque formation de la brique de 3
  Widget _buildFormationItemCard(Map<String, dynamic> f, int rank) {
    final nom = _shortFiliereTitle(f["nom"]?.toString() ?? "Formation");
    final etablissement = (f["etablissement"] ?? "").toString();
    final ville = (f["ville"] ?? "").toString();
    final region = (f["region"] ?? "").toString();
    final tauxAcces = (f["taux_acces"] as num?)?.toDouble() ?? 35.0;
    final seuil = (f["seuil_moyenne_estime"] as num?)?.toDouble() ?? 14.0;
    final gap = (f["estimated_gap"] as num?)?.toDouble() ?? 0.0;
    final prob = (f["probabilite_admission"] as num?)?.toInt() ?? 60;
    final grp = (f["selectivity_group"] as num?)?.toInt() ?? 2;
    final rankingLabel = (f["ranking_label"] ?? "").toString();

    final isPositive = gap >= 0;
    final gapColor = isPositive ? AppTheme.accentEmerald : AppTheme.accentCoral;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 1.1),
        boxShadow: AppTheme.softShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openNovaForFormation(f),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "#$rank",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nom,
                      style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 14.5, height: 1.2),
                    ),
                    if (etablissement.isNotEmpty && etablissement != nom) ...[
                      const SizedBox(height: 3),
                      Text(
                        etablissement,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: gapColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "$prob% admis",
                  style: TextStyle(color: gapColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Ville & Région
          if (ville.isNotEmpty || region.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [ville, region].where((s) => s.isNotEmpty).join(" · "),
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Métriques Parcoursup
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.cardBgElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Taux d'accès", style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                    Text(
                      "${tauxAcces.toStringAsFixed(0)}%",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Seuil attendu", style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                    Text(
                      "${seuil.toStringAsFixed(1)} / 20",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Différentiel", style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                    Text(
                      "${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(1)} pt",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: gapColor),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (rankingLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildSelectivityTierBadge(grp, rankingLabel),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppTheme.primary),
                SizedBox(width: 6),
                Text(
                  "Échanger avec Nova sur cette formation",
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }

  /// Dialogue de recherche et sélection du Lycée d'Origine & Région

  
  void _openNovaForFormation(Map<String, dynamic> f) {
    final nom = f["nom"]?.toString() ?? "Formation";
    final etablissement = f["etablissement"]?.toString() ?? "";
    final ville = f["ville"]?.toString() ?? "";
    final placeStr = [etablissement, ville].where((s) => s.isNotEmpty).join(" - ");
    final prompt = "Bonjour Nova, peux-tu me présenter la formation $nom à $placeStr ? Quels sont les attendus réels sur Parcoursup, les débouchés professionnels et mes chances d'admission ?";
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovaChatScreen(initialPrompt: prompt),
      ),
    );
  }

  Widget _buildVoieRoyaleEliteSection(List items) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars_rounded, color: Color(0xFFB8860B), size: 20),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Voie Royale & Élite d'Inspiration",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF5A4305)),
                    ),
                    Text(
                      "Les formations d'excellence pour fixer ton cap de travail et tes ambitions.",
                      style: TextStyle(fontSize: 11, color: Color(0xFF8B6914)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((it) {
            final f = Map<String, dynamic>.from(it as Map);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8D799)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school, size: 16, color: Color(0xFFB8860B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f["nom"]?.toString() ?? "", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text("${f['etablissement'] ?? ''} • ${f['ville'] ?? ''}", style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBF7EE),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD4AF37)),
                    ),
                    child: Text(
                      "${(f['seuil_moyenne_estime'] as num?)?.toStringAsFixed(1) ?? '17.5'} / 20",
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB8860B)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showLyceeSelectionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String searchQuery = "";
        String? selectedReg;
        String? selectedDept;
        List<String> regions = [];
        Map<String, dynamic> deptsByReg = {};
        List<Map<String, dynamic>> searchResults = [];
        bool isSearching = false;
        bool isLoadedHierarchy = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!isLoadedHierarchy) {
              isLoadedHierarchy = true;
              ApiService.getLyceesHierarchy().then((h) {
                setModalState(() {
                  regions = List<String>.from(h["regions"] ?? []);
                  deptsByReg = Map<String, dynamic>.from(h["departements_par_region"] ?? {});
                });
              });
            }

            Future<void> executeSearch() async {
              setModalState(() => isSearching = true);
              final res = await ApiService.searchLycees(
                searchQuery,
                region: selectedReg,
                departement: selectedDept,
                limit: 30,
              );
              setModalState(() {
                searchResults = res;
                isSearching = false;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Annuaire Officiel des Lycées (4 783)",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Text(
                      "Sélectionne ta région / département ou tape le nom de ton lycée pour étalonner tes notes selon les statistiques officielles IVAL.",
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 10),

                    if (regions.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBgElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.borderColor),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: selectedReg,
                                  hint: const Text("Toute région", style: TextStyle(fontSize: 11.5)),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text("Toutes les régions", style: TextStyle(fontSize: 11.5)),
                                    ),
                                    ...regions.map((r) => DropdownMenuItem<String>(
                                          value: r,
                                          child: Text(r, style: const TextStyle(fontSize: 11.5)),
                                        )),
                                  ],
                                  onChanged: (val) {
                                    setModalState(() {
                                      selectedReg = val;
                                      selectedDept = null;
                                    });
                                    executeSearch();
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (selectedReg != null && deptsByReg.containsKey(selectedReg)) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardBgElevated,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.borderColor),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: selectedDept,
                                    hint: const Text("Tous départements", style: TextStyle(fontSize: 11.5)),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text("Tous départements", style: TextStyle(fontSize: 11.5)),
                                      ),
                                      ...List<String>.from(deptsByReg[selectedReg] ?? []).map((d) => DropdownMenuItem<String>(
                                            value: d,
                                            child: Text(d, style: const TextStyle(fontSize: 11.5)),
                                          )),
                                    ],
                                    onChanged: (val) {
                                      setModalState(() => selectedDept = val);
                                      executeSearch();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 8),

                    TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: "Nom du lycée, ville ou code postal (ex: Malgrange, Henri IV...)",
                        prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.borderColor)),
                        filled: true,
                        fillColor: AppTheme.cardBgElevated,
                      ),
                      onChanged: (val) {
                        searchQuery = val;
                        if (val.trim().length >= 2 || selectedReg != null) {
                          executeSearch();
                        } else {
                          setModalState(() => searchResults = []);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    if (isSearching)
                      const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)))
                    else
                      Expanded(
                        child: searchResults.isEmpty
                            ? Center(
                                child: Text(
                                  searchQuery.trim().isEmpty && selectedReg == null
                                      ? "Tape le nom de ton lycée ou choisis une région pour afficher les établissements."
                                      : "Aucun lycée trouvé avec ces critères.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: searchResults.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final item = searchResults[i];
                                  final nom = item["nom"]?.toString() ?? "";
                                  final ville = item["ville"]?.toString() ?? "";
                                  final reg = item["region"]?.toString() ?? "";
                                  final dept = item["departement"]?.toString() ?? "";
                                  final taux = (item["taux_mentions"] as num?)?.toDouble() ?? 0.0;
                                  final bonus = (item["bonus_selectivite"] as num?)?.toDouble() ?? 0.0;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    title: Text(nom, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      "$ville ($dept - $reg) • ${taux > 0 ? '${taux.toStringAsFixed(0)}% mentions' : 'Lycée conventionné'}",
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                    trailing: bonus > 0
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: AppTheme.accentEmeraldSoft, borderRadius: BorderRadius.circular(6)),
                                            child: Text("+${bonus.toStringAsFixed(1)} pt", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentEmerald)),
                                          )
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _selectedLycee = item;
                                      });
                                      Navigator.pop(ctx);
                                      _fetchAnalysis();
                                    },
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildStrategySegmentButton(int idx, String label) {
    final isSelected = _selectedStrategyTab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedStrategyTab = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textMuted,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
//  WIDGET D'ANIMATION DE RÉFLEXION IA
// ==========================================

class _AiThinkingWidget extends StatefulWidget {
  final Map<String, dynamic>? profileData;

  const _AiThinkingWidget({super.key, this.profileData});

  @override
  State<_AiThinkingWidget> createState() => _AiThinkingWidgetState();
}

class _AiThinkingWidgetState extends State<_AiThinkingWidget> with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOutCubic,
    );

    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  String _getStepTitle(double progress) {
    if (progress < 0.28) {
      return "Analyse de tes compétences & centres d'intérêt...";
    } else if (progress < 0.60) {
      return "Recherche parmi le référentiel France Travail...";
    } else if (progress < 0.88) {
      return "Calcul des correspondances et opportunités...";
    } else {
      return "Sélection de tes 3 pistes de formation...";
    }
  }

  String _getStepSubtitle(double progress) {
    if (progress < 0.28) {
      return "Évaluation des dimensions clés de ton profil";
    } else if (progress < 0.60) {
      return "Exploration des fiches métiers officielles et débouchés";
    } else if (progress < 0.88) {
      return "Pondération selon tes préférences et tes points forts";
    } else {
      return "Finalisation de ta sélection personnalisée";
    }
  }

  @override
  Widget build(BuildContext context) {


    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, _) {
              final progress = _progressAnimation.value;
              final percent = (progress * 100).toInt().clamp(0, 100);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Badge haut
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.insights_rounded, size: 14, color: AppTheme.primaryLight),
                        SizedBox(width: 8),
                        Text(
                          "ANALYSE DE PROFIL & ORIENTATION",
                          style: TextStyle(
                            color: AppTheme.primaryLight,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Indicateur circulaire central
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBgElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.borderColor, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 4,
                            backgroundColor: AppTheme.borderColor,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.explore_rounded,
                              size: 34,
                              color: AppTheme.primaryLight,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$percent%",
                              style: const TextStyle(
                                color: AppTheme.textMain,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Message d'étape dynamique
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Text(
                      _getStepTitle(progress),
                      key: ValueKey<String>(_getStepTitle(progress)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Text(
                      _getStepSubtitle(progress),
                      key: ValueKey<String>(_getStepSubtitle(progress)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Barre de progression
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Container(
                                width: constraints.maxWidth * progress,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),


                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Feuille modale d'affichage de la Fiche Métier et du Conseiller Nova
/// Encapsulée dans un StatefulWidget pour préserver l'état lors de l'ouverture du clavier
class _MetierDetailModalSheet extends StatefulWidget {
  final Map<String, dynamic> metier;
  final Map<String, dynamic>? activeProfile;
  final VoidCallback onOpenDebate;

  const _MetierDetailModalSheet({
    required this.metier,
    this.activeProfile,
    required this.onOpenDebate,
  });

  @override
  State<_MetierDetailModalSheet> createState() => _MetierDetailModalSheetState();
}

class _MetierDetailModalSheetState extends State<_MetierDetailModalSheet> {
  int _selectedSegment = 0; // 0: Fiche détaillée, 1: Conversation IA Conseiller Nova
  late final TextEditingController _chatController;
  late final ScrollController _chatScrollController;
  bool _isChatLoading = false;
  bool _isListening = false;
  String? _speakingMessageId;
  bool _isStreaming = false;

  late final List<Map<String, dynamic>> _chatMessages;

  final List<String> _defaultSuggestions = [
    " Quelles études pour y arriver ?",
    " Quel salaire espérer au début et après 5 ans ?",
    " À quoi ressemble une journée type ?",
    " Quels sont les vrais inconvénients ?",
    " Ce métier recrute-t-il bien aujourd'hui ?",
  ];

  @override
  void initState() {
    super.initState();
    _chatController = TextEditingController();
    _chatScrollController = ScrollController();
    final nomMetier = (widget.metier["nom"] as String?) ?? "Fiche Métier";
    _chatMessages = [
      {
        "id": "intro",
        "role": "assistant",
        "text": "Bonjour ! Je suis Nova, votre conseiller d'orientation pour le métier de **$nomMetier**.\n\nPosez-moi vos questions sur les formations requises, les salaires, le quotidien ou les débouchés. Je suis à votre écoute pour vous aider à y voir plus clair !",
        "isStreaming": false,
      }
    ];
  }

  @override
  void dispose() {
    VoiceService.stopSpeaking();
    VoiceService.stopListening();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  /// Écrit la réponse au fur et à mesure (effet streaming progressif / machine à écrire)
  Future<void> _streamTextIntoMessage(Map<String, dynamic> message, String fullText) async {
    _isStreaming = true;
    message["text"] = "";
    message["isStreaming"] = true;
    if (mounted) setState(() {});

    final words = fullText.split(' ');
    for (int i = 0; i < words.length; i++) {
      if (!mounted) return;
      if (i > 0) message["text"] += " ";
      message["text"] += words[i];
      if (mounted) setState(() {});

      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 40),
          curve: Curves.easeOut,
        );
      }

      int delay = 20;
      final word = words[i];
      if (word.endsWith('.') || word.endsWith('!') || word.endsWith('?') || word.endsWith(':')) {
        delay = 80;
      } else if (word.endsWith(',')) {
        delay = 45;
      }
      await Future.delayed(Duration(milliseconds: delay));
    }

    if (mounted) {
      message["isStreaming"] = false;
      _isStreaming = false;
      setState(() {});
    }
  }

  Future<void> _sendChatMessage(String questionText) async {
    final q = questionText.trim();
    if (q.isEmpty || _isStreaming) return;
    _chatController.clear();
    VoiceService.stopSpeaking();
    VoiceService.stopListening();

    setState(() {
      _isListening = false;
      _isChatLoading = true;
      _chatMessages.add({
        "id": "user_${DateTime.now().millisecondsSinceEpoch}",
        "role": "user",
        "text": q,
        "isStreaming": false,
      });
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    final historyPayload = _chatMessages
        .map((m) => {
              "role": (m["role"] ?? "user").toString(),
              "text": (m["text"] ?? "").toString(),
            })
        .toList();

    final nomMetier = (widget.metier["nom"] as String?) ?? "Fiche Métier";
    final missions = (widget.metier["missions"] as List?) ?? [];
    final etudes = (widget.metier["etudes"] as List?) ?? [];
    final salaire = widget.metier["salaire"] as Map<String, dynamic>?;

    final res = await ApiService.sendMetierChat(
      metierNom: nomMetier,
      metierCodeRome: widget.metier["code_rome"]?.toString(),
      metierDescription: widget.metier["description"]?.toString(),
      metierMissions: missions,
      metierEtudes: etudes,
      metierSalaire: salaire,
      question: q,
      history: historyPayload,
      profile: widget.activeProfile,
    );

    if (!mounted) return;

    final reply = (res["reponse_ia"] as String?) ??
        (res["error"] != null ? "Oups, une erreur est survenue : ${res['error']}" : "Je n'ai pas pu obtenir de réponse pour le moment.");

    final newAiMsg = {
      "id": "ai_${DateTime.now().millisecondsSinceEpoch}",
      "role": "assistant",
      "text": "",
      "isStreaming": true,
    };

    setState(() {
      _isChatLoading = false;
      _chatMessages.add(newAiMsg);
    });

    await _streamTextIntoMessage(newAiMsg, reply);
  }

  void _toggleMic() {
    if (_isListening) {
      VoiceService.stopListening();
      setState(() => _isListening = false);
    } else {
      VoiceService.stopSpeaking();
      setState(() => _isListening = true);
      VoiceService.startListening(
        onResult: (text) {
          if (mounted) {
            setState(() {
              _chatController.text = text;
            });
          }
        },
        onEnd: () {
          if (mounted) {
            setState(() => _isListening = false);
          }
        },
      );
    }
  }

  void _toggleSpeak(String msgId, String text) {
    if (_speakingMessageId == msgId) {
      VoiceService.stopSpeaking();
      setState(() => _speakingMessageId = null);
    } else {
      VoiceService.stopSpeaking();
      setState(() => _speakingMessageId = msgId);
      VoiceService.speak(
        text,
        onStart: () {
          if (mounted) setState(() => _speakingMessageId = msgId);
        },
        onEnd: () {
          if (mounted) setState(() => _speakingMessageId = null);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nomMetier = (widget.metier["nom"] as String?) ?? "Fiche Métier";
    final missions = (widget.metier["missions"] as List?) ?? [];
    final hardSkills = (widget.metier["hard_skills"] as List?) ?? [];
    final etudes = (widget.metier["etudes"] as List?) ?? [];
    final salaire = widget.metier["salaire"] as Map<String, dynamic>?;
    final journeeType = widget.metier["journee_type"] as Map<String, dynamic>?;

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, controller) {
        return Column(
          children: [
            // Barre de poignée
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Sélecteur d'onglets moderne : [ Fiche Métier ] | [ Conseiller Nova ]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.cardBgElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSegment = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _selectedSegment == 0 ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 16,
                                color: _selectedSegment == 0 ? Colors.white : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Fiche Métier",
                                style: TextStyle(
                                  fontWeight: _selectedSegment == 0 ? FontWeight.bold : FontWeight.w500,
                                  color: _selectedSegment == 0 ? Colors.white : AppTheme.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSegment = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _selectedSegment == 1 ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.support_agent_rounded,
                                size: 16,
                                color: _selectedSegment == 1 ? Colors.white : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Conseiller Nova",
                                style: TextStyle(
                                  fontWeight: _selectedSegment == 1 ? FontWeight.bold : FontWeight.w500,
                                  color: _selectedSegment == 1 ? Colors.white : AppTheme.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Corps de l'onglet sélectionné
            Expanded(
              child: _selectedSegment == 0
                  ? _buildFicheDetailleeTab(
                      controller: controller,
                      nomMetier: nomMetier,
                      missions: missions,
                      hardSkills: hardSkills,
                      etudes: etudes,
                      salaire: salaire,
                      journeeType: journeeType,
                      onSwitchToChat: () => setState(() => _selectedSegment = 1),
                    )
                  : _buildChatMetierTab(nomMetier: nomMetier),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFicheDetailleeTab({
    required ScrollController controller,
    required String nomMetier,
    required List missions,
    required List hardSkills,
    required List etudes,
    required Map<String, dynamic>? salaire,
    required Map<String, dynamic>? journeeType,
    required VoidCallback onSwitchToChat,
  }) {
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre + Code ROME
          Text(
            nomMetier,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          if (widget.metier["code_rome"] != null) ...[
            const SizedBox(height: 4),
            Text(
              "Code Officiel France Travail : ${widget.metier["code_rome"]}",
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),

          // Encart d'échange avec le conseiller Nova
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBgElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Une question sur ce métier ?",
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain, fontSize: 13),
                      ),
                      Text(
                        "Échange directement avec ton conseiller.",
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: onSwitchToChat,
                  child: const Text("Échanger ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Description complète
          const Text(
            "Description du métier",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            widget.metier["description"] ?? "Aucune description fournie.",
            style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textMain),
          ),
          const SizedBox(height: 18),

          // Missions détaillées
          if (missions.isNotEmpty) ...[
            const Text(
              "Missions principales",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 8),
            ...missions.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 15, color: AppTheme.accentEmerald),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.toString(),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Journée type
          if (journeeType != null) ...[
            const Text(
              "Simulation d'une journée type",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.accentAmber),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                children: [
                  if (journeeType["matin"] != null)
                    _buildDayStep("Matin", journeeType["matin"]),
                  if (journeeType["midi"] != null)
                    _buildDayStep("Midi", journeeType["midi"]),
                  if (journeeType["apres_midi"] != null)
                    _buildDayStep("Après-midi", journeeType["apres_midi"]),
                  if (journeeType["fin_journee"] != null)
                    _buildDayStep("Fin de journée", journeeType["fin_journee"]),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Salaires
          if (salaire != null) ...[
            const Text(
              "Rémunération indicative",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSalaryItem("Junior", "${salaire["junior"] ?? "28k"} €"),
                _buildSalaryItem("Confirmé", "${salaire["medior"] ?? "35k"} €"),
                _buildSalaryItem("Senior", "${salaire["senior"] ?? "45k+"} €"),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Formations
          if (etudes.isNotEmpty) ...[
            const Text(
              "Formations & Accès",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 6),
            Text(
              etudes.join("\n"),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
          ],

          // Compétences clés
          if (hardSkills.isNotEmpty) ...[
            const Text(
              "Compétences clés",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hardSkills
                  .map((s) => Chip(
                        label: Text(s.toString(), style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                        backgroundColor: AppTheme.primarySoft,
                        side: const BorderSide(color: Colors.transparent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildChatMetierTab({required String nomMetier}) {
    return Column(
      children: [
        // Liste des messages
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0) + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        " Suggestions de questions :",
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _defaultSuggestions.map((s) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                backgroundColor: AppTheme.cardBgElevated,
                                side: const BorderSide(color: AppTheme.borderColor),
                                label: Text(
                                  s,
                                  style: const TextStyle(color: AppTheme.textMain, fontSize: 12),
                                ),
                                onPressed: () => _sendChatMessage(s),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (_isChatLoading && index == _chatMessages.length + 1) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBgElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Nova prépare sa réponse...",
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final msgIndex = index - 1;
              final msg = _chatMessages[msgIndex];
              final isUser = msg["role"] == "user";
              final text = (msg["text"] ?? "").toString();
              final isStreaming = msg["isStreaming"] == true;
              final msgId = (msg["id"] ?? "msg_$msgIndex").toString();
              final isSpeakingThis = _speakingMessageId == msgId;

              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.82,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isUser ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                      bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                    ),
                    border: Border.all(
                      color: isUser ? Colors.transparent : AppTheme.borderColor,
                    ),
                    boxShadow: isUser ? null : AppTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.support_agent_rounded, size: 16, color: AppTheme.primary),
                                SizedBox(width: 6),
                                Text(
                                  "Nova • Conseiller",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            if (!isStreaming)
                              IconButton(
                                icon: Icon(
                                  isSpeakingThis ? Icons.stop_circle : Icons.volume_up_outlined,
                                  size: 18,
                                  color: isSpeakingThis ? Colors.redAccent : AppTheme.textMuted,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: isSpeakingThis ? "Arrêter la lecture" : "Écouter la réponse",
                                onPressed: () => _toggleSpeak(msgId, text),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      SelectableText.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: text,
                              style: TextStyle(
                                color: isUser ? Colors.white : AppTheme.textMain,
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                            if (isStreaming)
                              const TextSpan(
                                text: " ▋",
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Barre de saisie inférieure (ancrée avec padding clavier)
        Container(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: 10,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppTheme.borderColor)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.redAccent : AppTheme.primary,
                ),
                tooltip: _isListening ? "Arrêter l'enregistrement" : "Parler à l'oral",
                onPressed: _toggleMic,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBgElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Pose ta question sur $nomMetier...",
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (val) => _sendChatMessage(val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  tooltip: "Envoyer",
                  onPressed: () => _sendChatMessage(_chatController.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayStep(String moment, dynamic text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              moment,
              style: const TextStyle(color: AppTheme.accentAmber, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              text.toString(),
              style: const TextStyle(color: AppTheme.textMain, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryItem(String label, String amount) {
    return Column(
      children: [
        Text(amount, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentEmerald)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ],
    );
  }
}

/// Feuille modale de Débat et Retours utilisateur ("Donner mon avis sur cette piste")
/// Totalement thématisée en fond blanc doux, avec champ texte clair et lisible (texte sombre sur fond clair)
/// et streaming progressif mot par mot comme ChatGPT
class _DebateModalSheet extends StatefulWidget {
  final Map<String, dynamic> metier;
  final String? initialObjection;
  final Map<String, dynamic>? activeProfile;
  final void Function(Map<String, dynamic>) onOpenMetierDetail;

  const _DebateModalSheet({
    required this.metier,
    this.initialObjection,
    this.activeProfile,
    required this.onOpenMetierDetail,
  });

  @override
  State<_DebateModalSheet> createState() => _DebateModalSheetState();
}

class _DebateModalSheetState extends State<_DebateModalSheet> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  bool _isVoiceMode = false;
  VoiceSessionState _avatarState = VoiceSessionState.idle;
  bool _isSubmitting = false;
  bool _hasAutoTriggered = false;
  bool _isStreaming = false;

  late final List<Map<String, dynamic>> _debateChat;

  final List<String> _suggestions = [
    " Trop d'heures assis sur écran",
    " Manque de contact humain & d'échange",
    " Études trop longues ou sélectives",
    " Trop de stress et de pression",
    " Besoin d'action concrète et de terrain",
    " Pas assez créatif à mon goût",
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialObjection ?? "");
    _scrollController = ScrollController();
    final nomMetier = widget.metier["nom"] ?? "ce métier";
    _debateChat = [
      {
        "role": "assistant",
        "text": "Tu examines la piste $nomMetier. Quels sont tes doutes, contraintes ou objections face aux exigences de cette voie ? Exprime ton argument à l'écrit ou à l'oral.",
        "isStreaming": false,
      }
    ];

    if (widget.initialObjection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_hasAutoTriggered) {
          _hasAutoTriggered = true;
          _sendObjection(widget.initialObjection!);
        }
      });
    }
  }

  @override
  void dispose() {
    VoiceService.stopSpeaking();
    VoiceService.stopListening();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Streaming progressif du texte dans le message (machine à écrire)
  Future<void> _streamTextIntoMessage(Map<String, dynamic> message, String fullText) async {
    _isStreaming = true;
    message["text"] = "";
    message["isStreaming"] = true;
    if (mounted) setState(() {});

    final words = fullText.split(' ');
    for (int i = 0; i < words.length; i++) {
      if (!mounted) return;
      if (i > 0) message["text"] += " ";
      message["text"] += words[i];
      if (mounted) setState(() {});

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 40),
          curve: Curves.easeOut,
        );
      }

      int delay = 20;
      final word = words[i];
      if (word.endsWith('.') || word.endsWith('!') || word.endsWith('?') || word.endsWith(':')) {
        delay = 80;
      } else if (word.endsWith(',')) {
        delay = 45;
      }
      await Future.delayed(Duration(milliseconds: delay));
    }

    if (mounted) {
      message["isStreaming"] = false;
      _isStreaming = false;
      setState(() {});
    }
  }

  void _speakText(String text) {
    setState(() => _avatarState = VoiceSessionState.speaking);
    VoiceService.speak(
      text,
      onStart: () {
        if (mounted) setState(() => _avatarState = VoiceSessionState.speaking);
      },
      onEnd: () {
        if (mounted) setState(() => _avatarState = VoiceSessionState.idle);
      },
    );
  }

  Future<void> _sendObjection(String objectionText) async {
    final cleaned = VoiceService.cleanForSpeech(objectionText);
    if (cleaned.trim().isEmpty || _isStreaming) return;
    VoiceService.stopSpeaking();
    VoiceService.stopListening();
    _textController.clear();

    setState(() {
      _isSubmitting = true;
      _avatarState = VoiceSessionState.thinking;
      _debateChat.add({
        "role": "user",
        "text": cleaned,
        "isStreaming": false,
      });
    });

    final historyPayload = _debateChat
        .map((m) => {
              "role": (m["role"] ?? "user").toString(),
              "text": (m["text"] ?? "").toString(),
            })
        .toList();

    final nomMetier = widget.metier["nom"] ?? "ce métier";
    final res = await ApiService.sendDebateObjection(
      metierNom: nomMetier,
      metierCodeRome: widget.metier["code_rome"]?.toString(),
      objection: cleaned.trim(),
      history: historyPayload,
      profile: widget.activeProfile,
    );

    if (!mounted) return;

    String? reply;
    List<dynamic> alts = [];

    if (res.containsKey("reponse_ia")) {
      reply = res["reponse_ia"] as String?;
      alts = (res["metiers_alternatifs"] as List?) ?? [];
    } else if (res.containsKey("error")) {
      reply = "Désolé, une erreur est survenue : ${res['error']}";
    } else {
      reply = "Argument bien pris en compte.";
    }

    final newAiMsg = {
      "role": "assistant",
      "text": "",
      "alternatives": alts,
      "isStreaming": true,
    };

    setState(() {
      _isSubmitting = false;
      _avatarState = VoiceSessionState.idle;
      _debateChat.add(newAiMsg);
    });

    if (reply != null) {
      await _streamTextIntoMessage(newAiMsg, reply);
      if (mounted && _isVoiceMode) {
        _speakText(reply);
      }
    }
  }

  void _toggleMic() {
    if (_avatarState == VoiceSessionState.listening) {
      VoiceService.stopListening();
      setState(() => _avatarState = VoiceSessionState.idle);
    } else {
      VoiceService.stopSpeaking();
      setState(() => _avatarState = VoiceSessionState.listening);

      VoiceService.startListening(
        onResult: (text) {
          if (mounted) {
            setState(() {
              _textController.text = text;
            });
          }
        },
        onEnd: () {
          if (mounted && !_isSubmitting) {
            setState(() => _avatarState = VoiceSessionState.idle);
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nomMetier = widget.metier["nom"] ?? "ce métier";

    String avatarSubtitle;
    switch (_avatarState) {
      case VoiceSessionState.speaking:
        avatarSubtitle = " Analyse vocale en cours...";
        break;
      case VoiceSessionState.listening:
        avatarSubtitle = " Écoute active... expose ton argument";
        break;
      case VoiceSessionState.thinking:
        avatarSubtitle = "Évaluation de ton objection...";
        break;
      case VoiceSessionState.idle:
        avatarSubtitle = "Mode Débat & Jury d'orientation";
        break;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // En-tête : Titre & Sélecteur de Mode (Vocal / Texte)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.forum_outlined, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Mode Débat & Objections",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Challenge ton projet autour de $nomMetier",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  // Toggle Vocal / Texte
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBgElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isVoiceMode = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isVoiceMode ? AppTheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.mic_rounded,
                                  size: 14,
                                  color: _isVoiceMode ? Colors.white : AppTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Vocal",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _isVoiceMode ? FontWeight.bold : FontWeight.normal,
                                    color: _isVoiceMode ? Colors.white : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isVoiceMode = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: !_isVoiceMode ? AppTheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.keyboard_outlined,
                                  size: 14,
                                  color: !_isVoiceMode ? Colors.white : AppTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Texte",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: !_isVoiceMode ? FontWeight.bold : FontWeight.normal,
                                    color: !_isVoiceMode ? Colors.white : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Interface vocale sobre (sans avatar 2D cyber-RPG)
              if (_isVoiceMode) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: _avatarState == VoiceSessionState.listening
                                ? AppTheme.accentEmeraldSoft
                                : AppTheme.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _avatarState == VoiceSessionState.speaking
                                ? Icons.graphic_eq_rounded
                                : _avatarState == VoiceSessionState.listening
                                    ? Icons.mic_rounded
                                    : Icons.record_voice_over_rounded,
                            color: _avatarState == VoiceSessionState.listening
                                ? AppTheme.accentEmerald
                                : AppTheme.primary,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          avatarSubtitle,
                          style: const TextStyle(
                            color: AppTheme.textMain,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (_avatarState == VoiceSessionState.listening) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.primarySoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.graphic_eq, color: AppTheme.primary, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _textController.text.isNotEmpty
                                        ? _textController.text
                                        : "Écoute en cours... exprime ton argument.",
                                    style: TextStyle(
                                      color: _textController.text.isNotEmpty ? AppTheme.textMain : AppTheme.textMuted,
                                      fontSize: 13,
                                      fontStyle: _textController.text.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                                label: const Text(
                                  "Valider & Débattre",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.accentEmerald,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: () {
                                  final txt = _textController.text.trim();
                                  if (txt.isNotEmpty) {
                                    _sendObjection(txt);
                                  } else {
                                    VoiceService.stopListening();
                                    setState(() => _avatarState = VoiceSessionState.idle);
                                  }
                                },
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                                label: const Text("Annuler", style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.borderColor),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: () {
                                  VoiceService.stopListening();
                                  setState(() => _avatarState = VoiceSessionState.idle);
                                },
                              ),
                            ],
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.mic_rounded, size: 20, color: Colors.white),
                            label: const Text(
                              " Prendre la parole (Microphone)",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: _isSubmitting ? null : _toggleMic,
                          ),
                        ],

                        if (_avatarState == VoiceSessionState.speaking) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.volume_off, size: 14, color: AppTheme.textMuted),
                            label: const Text("Couper la voix", style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                            onPressed: () {
                              VoiceService.stopSpeaking();
                              setState(() => _avatarState = VoiceSessionState.idle);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Suggestions rapides d'objections
              Text(
                _isVoiceMode ? "Ou choisis ton objection à l'oral :" : "Qu'est-ce qui te déplaît dans ce métier ?",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestions.map((sug) {
                  return ActionChip(
                    label: Text(sug),
                    labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMain),
                    backgroundColor: AppTheme.cardBgElevated,
                    side: const BorderSide(color: AppTheme.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onPressed: () {
                      final cleanSug = VoiceService.cleanForSpeech(sug);
                      _textController.text = cleanSug;
                      _sendObjection(cleanSug);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Champ texte clair et lisible (Texte sombre sur fond blanc/porcelaine doux)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: _isVoiceMode ? "Texte transcrit ou tapé..." : "Écris ton objection au jury...",
                        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        fillColor: AppTheme.cardBgElevated,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                        ),
                      ),
                      onSubmitted: (txt) => _sendObjection(txt),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primary,
                    ),
                    child: IconButton(
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      tooltip: "Envoyer",
                      onPressed: _isSubmitting ? null : () => _sendObjection(_textController.text),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // État de chargement
              if (_isSubmitting) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Nova analyse tes arguments et prépare son rebond...",
                          style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Fil de discussion du Débat
              if (_debateChat.isNotEmpty) ...[
                const Text(
                  " Fil du Débat en Direct :",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 10),
                ..._debateChat.map((msg) {
                  final isUser = msg["role"] == "user";
                  final text = msg["text"] as String? ?? "";
                  final isStreaming = msg["isStreaming"] == true;
                  final alts = (msg["alternatives"] as List?) ?? [];

                  if (isUser) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12, left: 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                text,
                                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.person, color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14, right: 24),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.smart_toy_outlined, color: AppTheme.primary, size: 16),
                              const SizedBox(width: 6),
                              const Text("Nova • Mentor Orientation", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 13)),
                              const Spacer(),
                              if (_isVoiceMode && !isStreaming)
                                IconButton(
                                  icon: const Icon(Icons.volume_up, size: 16, color: AppTheme.textMuted),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: "Réécouter",
                                  onPressed: () => _speakText(text),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SelectableText.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: text,
                                  style: const TextStyle(color: AppTheme.textMain, fontSize: 13, height: 1.45),
                                ),
                                if (isStreaming)
                                  const TextSpan(
                                    text: " ▋",
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Métiers alternatifs
                          if (alts.isNotEmpty && !isStreaming) ...[
                            const SizedBox(height: 12),
                            const Text(" Pistes alternatives suggérées :", style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ...alts.map((alt) {
                              final altMap = alt as Map<String, dynamic>;
                              final aNom = altMap["nom"]?.toString() ?? "";
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardBgElevated,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(aNom, style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                      altMap["bulletin_feedback"] ?? "Alternative adaptée à tes retours",
                                      style: const TextStyle(color: AppTheme.accentEmerald, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.undo, size: 13),
                                          label: const Text("Réfuter à l'oral", style: TextStyle(fontSize: 11)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppTheme.accentCoral,
                                            side: const BorderSide(color: AppTheme.accentCoral),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: () {
                                            _textController.text = "Je n'aime pas $aNom parce que...";
                                            _toggleMic();
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton(
                                          child: const Text("Voir la fiche", style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                                          onPressed: () {
                                            VoiceService.stopSpeaking();
                                            Navigator.pop(context);
                                            widget.onOpenMetierDetail(altMap);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    );
                  }
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}
