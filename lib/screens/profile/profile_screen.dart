import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_profile.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../services/progress_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Module 4 : Suivi & Livrables Scolaires (Skills 10, 11, 12).
/// - Skill 10 : Checkpoint Mensuel (évolution des moyennes et probabilités d'admission)
/// - Skill 11 : Simulation Jury / Conseil de Classe (défense du projet face aux objections)
/// - Skill 12 : Fiche Synthèse 1 Page standardisée pour le Professeur Principal ou Psy-EN
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  static const Map<String, Map<String, String>> _decodeurTalents = {
    "Gaming compétitif / Esport / Stratégie": {
      "academique": "Analyse systémique, prise de décision rapide & optimisation",
      "pro": "Résolution de problèmes complexes & coordination sous pression",
      "parcoursup": "« La pratique compétitive m'a appris à analyser des métriques de performance et à coordonner une équipe sous contrainte de temps. »",
    },
    "Production musicale / Rap / Beatmaking / Écriture": {
      "academique": "Maîtrise rythmique/stylistique & ingénierie sonore",
      "pro": "Conduite d'un projet créatif complet",
      "parcoursup": "« La composition et la MAO m'ont formé à la rigueur des logiciels techniques et à la précision de l'écriture. »",
    },
    "Sport en club / Arts martiaux / Musculation": {
      "academique": "Discipline quotidienne, résistance à l'effort long & régularité",
      "pro": "Résilience face à l'échec & respect d'un plan d'entraînement",
      "parcoursup": "« Mon engagement sportif m'a inculqué la valeur de l'effort régulier et la capacité à performer lors d'échéances décisives. »",
    },
    "Montage vidéo / Création de contenu": {
      "academique": "Synthèse de l'information, narration & outils numériques",
      "pro": "Communication d'impact, analyse d'audience & production multimédia",
      "parcoursup": "« Concevoir et monter des formats vidéo m'a appris à vulgariser un sujet complexe et à structurer un script clair. »",
    },
    "Programmation / Mods / Serveurs / Cybersécurité": {
      "academique": "Algorithmique, logique formelle & documentation technique en anglais",
      "pro": "Développement logiciel, débogage méthodique & administration système",
      "parcoursup": "« Développer des scripts en autodidacte a forgé ma capacité à résoudre des bugs et à lire de la documentation technique. »",
    },
    "Bricolage / Électronique / Mécanique / Impression 3D": {
      "academique": "Géométrie dans l'espace, physique appliquée & systèmes matériels",
      "pro": "Prototypage rapide, diagnostic de pannes & ingénierie pragmatique",
      "parcoursup": "« Concevoir ou modéliser des objets en 3D m'a permis de relier les concepts de physique à la réalité concrète des matériaux. »",
    },
    "Débat / Éloquence / Géopolitique / Actualités": {
      "academique": "Dialectique, structuration de l'argumentation & culture historique",
      "pro": "Prise de parole en public, négociation & esprit critique",
      "parcoursup": "« Mon intérêt pour le débat et la géopolitique nourrit ma capacité à défendre une thèse structurée à l'oral. »",
    },
    "Manga / Dessin / Design / Modélisation 3D": {
      "academique": "Sens de l'observation, proportions/perspectives & culture visuelle",
      "pro": "Direction artistique, conception graphique & exigence du détail",
      "parcoursup": "« La pratique régulière du dessin a forgé ma patience, mon sens de l'observation spatiale et ma rigueur d'exécution. »",
    },
    "Achat-Revente / Sneakers / E-commerce / Finance": {
      "academique": "Calcul de marges, analyse offre/demande & gestion budgétaire",
      "pro": "Sens commercial, négociation & détection d'opportunités",
      "parcoursup": "« Gérer une activité d'achat-revente m'a initié concrètement aux mécanismes de prix et à la relation client. »",
    },
    "Aide aux autres / Tutorat / Animation / Bénévolat": {
      "academique": "Pédagogie & maturité civique",
      "pro": "Management bienveillant, médiation & responsabilité d'équipe",
      "parcoursup": "« Accompagner des plus jeunes m'a appris à adapter mon discours, à faire preuve de pédagogie et à assumer des responsabilités. »",
    },
  };

  Widget _buildDecodedTalentsSection(UserProfile? profile) {
    final passions = profile?.passionsDecoded ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Mes Talents Décodés (Skill 2)',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.bold,
                fontSize: 16.5,
                letterSpacing: -0.3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentEmeraldSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                passions.isEmpty ? "À renseigner" : "${passions.length} enregistrés",
                style: const TextStyle(
                  color: AppTheme.accentEmerald,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (passions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
              boxShadow: AppTheme.softShadow,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Aucun talent ou passion extra-scolaire encore sélectionné.",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppTheme.textMain),
                ),
                SizedBox(height: 4),
                Text(
                  "Rends-toi dans l'onglet « Profil & Notes » > « 2. Talents » pour traduire tes loisirs réels en compétences valorisables sur Parcoursup.",
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          )
        else
          ...passions.map((passion) {
            final details = _decodeurTalents[passion] ?? {
              "academique": "Compétence transversale appliquée",
              "pro": "Rigueur et engagement opérationnel",
              "parcoursup": "« Cette passion témoigne de ma constance et de ma capacité d'investissement personnel. »",
            };

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          passion,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.school_outlined, size: 16, color: Color(0xFF16A34A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Académique : ${details['academique']}",
                            style: const TextStyle(color: Color(0xFF15803D), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.work_outline_rounded, size: 16, color: Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Professionnel : ${details['pro']}",
                            style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Text(
                      details["parcoursup"] ?? "",
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 22),
      ],
    );
  }

  User? get _currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  String? _selectedClasse;

  static const List<String> _classesDisponibles = [
    '3e',
    '2nde',
    'Première',
    'Terminale',
  ];

  @override
  void initState() {
    super.initState();
    final user = _currentUser;
    if (user != null) {
      UserService.syncUserSession(user);
    }
  }

  String _getUserDisplayName(UserProfile? profile) {
    if (profile != null && profile.displayName.trim().isNotEmpty) {
      return profile.displayName.trim();
    }
    final user = _currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }
    final email = user?.email;
    if (email != null && email.contains('@')) {
      final handle = email.split('@').first;
      if (handle.isNotEmpty) {
        return handle[0].toUpperCase() + handle.substring(1);
      }
    }
    return "Élève";
  }

  Future<void> _showEditIdentityDialog(UserProfile? profile) async {
    final nameController =
        TextEditingController(text: _getUserDisplayName(profile) == "Élève" ? "" : _getUserDisplayName(profile));
    String? tempClasse = profile?.classeActuelle ?? _selectedClasse;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text(
                "Paramètres Scolaires",
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Prénom / Nom",
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: "Saisis ton prénom ou nom",
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Classe actuelle",
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _classesDisponibles.map((classe) {
                      final isSelected = tempClasse == classe;
                      return ChoiceChip(
                        label: Text(classe),
                        selected: isSelected,
                        selectedColor: AppTheme.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textMain,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setModalState(() => tempClasse = classe);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    final uid = _currentUser?.uid;
                    setState(() => _selectedClasse = tempClasse);
                    if (uid != null) {
                      if (newName.isNotEmpty) {
                        await UserService.updateDisplayName(uid, newName);
                      }
                      if (tempClasse != null) {
                        await UserService.updateAcademicStrategy(
                          uid: uid,
                          classeActuelle: tempClasse,
                        );
                      }
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text("Enregistrer"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddCheckpointDialog(UserProgress progress) async {
    double moyenne = 0.0;
    double noteMaths = 0.0;
    double notePhysique = 0.0;
    final filiereCible = progress.gapAnalysisResult?['filiere_cible']?.toString() ??
        progress.doubleTrajectoire?['parcours_ambition']?['titre']?.toString() ??
        "Aucune filière cible définie";

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text(
                "Nouveau Checkpoint Mensuel",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textMain),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Cible : $filiereCible",
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  Text("Moyenne générale : ${moyenne.toStringAsFixed(1)} / 20",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Slider(
                    value: moyenne,
                    min: 0,
                    max: 20,
                    divisions: 40,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setModalState(() => moyenne = v),
                  ),
                  Text("Matière Majeure 1 : ${noteMaths.toStringAsFixed(1)} / 20",
                      style: const TextStyle(fontSize: 12.5)),
                  Slider(
                    value: noteMaths,
                    min: 0,
                    max: 20,
                    divisions: 40,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setModalState(() => noteMaths = v),
                  ),
                  Text("Matière Majeure 2 : ${notePhysique.toStringAsFixed(1)} / 20",
                      style: const TextStyle(fontSize: 12.5)),
                  Slider(
                    value: notePhysique,
                    min: 0,
                    max: 20,
                    divisions: 40,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setModalState(() => notePhysique = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final avgScore = (moyenne + noteMaths + notePhysique) / 3.0;
                    final prob = (65 + (avgScore - 15.0) * 10).round().clamp(10, 95);
                    await ProgressService.recordMonthlyCheckpoint(
                      moyenneGenerale: double.parse(moyenne.toStringAsFixed(1)),
                      matieres: {
                        "Matière Majeure 1": double.parse(noteMaths.toStringAsFixed(1)),
                        "Matière Majeure 2": double.parse(notePhysique.toStringAsFixed(1)),
                      },
                      admissionProbability: prob,
                      filiereCible: filiereCible,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text("Enregistrer le Checkpoint"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showJurySimulationModal(UserProgress progress) async {
    final targetName = progress.doubleTrajectoire?['parcours_ambition']?['titre']?.toString() ??
        progress.gapAnalysisResult?['filiere_cible']?.toString() ??
        "Filière Sélective";
    final TextEditingController argController = TextEditingController();
    String juryResponse =
        "Bonjour. En tant que jury d'admission pour « $targetName », nous constatons un écart entre certaines de tes moyennes actuelles et nos attendus. Quels éléments concrets nous prouvent que tu tiendras le rythme ?";
    bool isLoadingJury = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.gavel_rounded, color: AppTheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Simulateur Jury & Objections",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain),
                            ),
                            Text(
                              targetName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Text(
                      juryResponse,
                      style: const TextStyle(color: AppTheme.textMain, fontSize: 13.5, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: argController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: "Rédige ta réponse au jury...",
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: isLoadingJury
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                      label: const Text(
                        "Soumettre ma défense au Jury IA",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: isLoadingJury
                          ? null
                          : () async {
                              final txt = argController.text.trim();
                              if (txt.isEmpty) return;
                              setModalState(() => isLoadingJury = true);
                              final res = await ApiService.sendDebateObjection(
                                metierNom: targetName,
                                objection: txt,
                              );
                              setModalState(() {
                                isLoadingJury = false;
                                juryResponse = res["reponse_ia"]?.toString() ??
                                    "Ton argument est noté. Veille à chiffrer ta progression au prochain trimestre et à consolider ton Plan B.";
                                argController.clear();
                              });
                            },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFicheSynthesePreview(
      String displayName, String? classeActuelle, UserProgress progress) {
    final gap = progress.gapAnalysisResult;
    final traj = progress.doubleTrajectoire;
    final ambition = traj?['parcours_ambition']?['titre'] ??
        gap?['filiere_cible'] ??
        "Non renseignée";
    final realiste = traj?['parcours_realiste']?['titre'] ??
        "Non renseignée";
    final prob = gap?['probabilite_admission'] ?? progress.matchScore ?? 0;
    final statut = gap?['statut_global'] ?? "Dossier non renseigné";
    final ecarts = (gap?['ecarts_matieres'] as List?) ?? [];
    final talents = (gap?['talents_decodes'] as List?) ?? [];
    final classeStr = classeActuelle ?? "Non renseignée";

    final StringBuffer markdownDoc = StringBuffer()
      ..writeln("FICHE SYNTHÈSE D'ORIENTATION STRATÉGIQUE")
      ..writeln("Destinataires : Professeur Principal / Psy-EN / Conseil de Classe")
      ..writeln("================================================================")
      ..writeln("Élève : $displayName | Classe : $classeStr")
      ..writeln("Indice d'alignement & admissibilité : $prob% : $statut")
      ..writeln("")
      ..writeln("1. DOUBLE TRAJECTOIRE")
      ..writeln("• Voie Ambition : $ambition")
      ..writeln("• Plan B Réaliste sécurisé : $realiste")
      ..writeln("")
      ..writeln("2. ANALYSE D'ÉCART ACADÉMIQUE")
      ..writeln(ecarts.isEmpty
          ? "• Relevé de notes en attente de synchronisation."
          : ecarts
              .map((e) =>
                  "• ${e['matiere']} : ${e['note_actuelle']}/20 : Attendu : ${e['seuil_attendu']}/20 | Écart : ${e['delta']} pt")
              .join("\n"))
      ..writeln("")
      ..writeln("3. COMPÉTENCES TRANSVERSALES & ENGAGEMENTS")
      ..writeln(talents.isEmpty
          ? "• Aucun engagement extra-scolaire renseigné."
          : talents
              .map((t) => "• ${t['passion']} -> ${t['competence_academique']}")
              .join("\n"))
      ..writeln("")
      ..writeln("4. PLAN D'EXÉCUTION HEBDOMADAIRE")
      ..writeln("• ${progress.weeklyExecutionPlan.length} créneaux hebdomadaires de remédiation programmés.");

    final fullText = markdownDoc.toString();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.description_outlined, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Fiche Synthèse 1 Page",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: AppTheme.textMain),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: SelectableText(
                  fullText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AppTheme.textMain,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Fermer"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
              label: const Text("Copier la Fiche", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: fullText));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Fiche Synthèse copiée dans le presse-papiers !"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUser?.uid;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Suivi & Livrables',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          if (_currentUser != null)
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: AppTheme.textMuted),
              tooltip: "Se déconnecter",
              onPressed: () async {
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
        ],
      ),
      body: StreamBuilder<UserProfile?>(
        stream: uid != null
            ? UserService.getUserProfileStream(uid)
            : Stream.value(null),
        builder: (context, userSnap) {
          final userProfile = userSnap.data;
          final displayName = _getUserDisplayName(userProfile);
          final classeActuelle =
              userProfile?.classeActuelle ?? _selectedClasse;

          return StreamBuilder<UserProgress>(
            stream: ProgressService.streamProgress(),
            builder: (context, progSnap) {
              final progress = progSnap.data ?? UserProgress.empty;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // En-tête Identité Scolaire
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'E',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: AppTheme.textMain,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primarySoft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Niveau : ${classeActuelle ?? "Non renseigné"}',
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: AppTheme.textMuted),
                            tooltip: "Modifier le profil scolaire",
                            onPressed: () =>
                                _showEditIdentityDialog(userProfile),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ==========================================================
                    _buildDecodedTalentsSection(userProfile),
                    // CHECKPOINT MENSUEL
                    // ==========================================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Checkpoints Mensuels',
                          style: TextStyle(
                            color: AppTheme.textMain,
                            fontWeight: FontWeight.bold,
                            fontSize: 16.5,
                            letterSpacing: -0.3,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add_chart_rounded, size: 16),
                          label: const Text("Nouveau relevé", style: TextStyle(fontSize: 12.5)),
                          onPressed: () => _showAddCheckpointDialog(progress),
                        ),
                      ],
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: progress.bulletinsHistory.isEmpty
                          ? const Text(
                              "Aucun checkpoint enregistré. Clique sur « Nouveau relevé » ou lance le Gap Analyzer pour suivre l'évolution mensuelle de ton admissibilité.",
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...progress.bulletinsHistory.reversed
                                    .take(4)
                                    .map((item) {
                                  final moy = item['moyenneGenerale'] ?? ':';
                                  final prob =
                                      item['admissionProbability'] ?? ':';
                                  final cible =
                                      item['filiereCible'] ?? 'Filière visée';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "$cible : Moy. $moy/20",
                                            style: const TextStyle(
                                              color: AppTheme.textMain,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentEmeraldSoft,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            "Admissibilité : $prob%",
                                            style: const TextStyle(
                                              color: AppTheme.accentEmerald,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                    ),

                    const SizedBox(height: 22),

                    // ==========================================================
                    // MODE DÉBAT & SIMULATION JURY
                    // ==========================================================
                    const Text(
                      'Préparation Jury & Objections',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Entraîne-toi à défendre la cohérence de ton projet face aux objections d'un jury ou d'un conseil de classe.",
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.35),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.record_voice_over_outlined, size: 18, color: Colors.white),
                              label: const Text(
                                "Lancer une Simulation de Jury",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => _showJurySimulationModal(progress),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ==========================================================
                    // EXPORT FICHE SYNTHÈSE 1 PAGE
                    // ==========================================================
                    const Text(
                      'Livrable Institutionnel',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.picture_as_pdf_outlined,
                                  color: AppTheme.accentCoral, size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Fiche Synthèse 1 Page",
                                  style: TextStyle(
                                    color: AppTheme.textMain,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Document standardisé récapitulant ton profil RIASEC, l'analyse d'écart académique, ta Voie Ambition et ton Plan B sécurisé.",
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.description_outlined, size: 18),
                              label: const Text(
                                  "Générer & Exporter la Fiche Synthèse 1 Page"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(color: AppTheme.primary),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _showFicheSynthesePreview(
                                  displayName, classeActuelle, progress),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
