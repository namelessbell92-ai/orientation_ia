import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../matching/matching_screen.dart';

class TestsScreen extends StatefulWidget {
  final VoidCallback? onGoToProfile;
  const TestsScreen({super.key, this.onGoToProfile});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ==========================================
  //  VOLET 1 : DOSSIER SCOLAIRE & BULLETINS
  // ==========================================
  String? _classeActuelle;
  final List<String> _classesDisponibles = ["3e", "2nde", "Première", "Terminale"];

  final Set<String> _selectedSpecialites = {};
  final List<String> _specialitesDisponibles = [
    "Mathématiques",
    "Physique-Chimie",
    "SVT",
    "Informatique / NSI",
    "Sciences de l'Ingénieur",
    "SES",
    "Histoire-Géo, Géopolitique (HGGSP)",
    "Humanités, Littérature, Philo (HLP)",
    "LLCER (Anglais)",
    "Arts",
  ];

  final Map<String, double> _matieres = {};

  bool _isUploadingBulletin = false;
  double _extractionProgress = 0.0;
  String _extractionStep = "";
  final List<String> _detectedLiveItems = [];
  Timer? _extractionTimer;
  String? _bulletinUploadMessage;
  bool _bulletinSuccess = false;
  Map<String, dynamic>? _detectedLycee;
  double? _bulletinMoyenne;
  String? _detectedDominante;

  String? _selectedFiliereAmbitionId;
  bool _isComputingGap = false;
  Map<String, dynamic>? _gapAnalysisResult;

  final List<Map<String, String>> _filieresAmbitionDisponibles = [
    {"id": "pass_las_medecine", "label": "Santé / Médecine : PASS / L.AS"},
    {"id": "cpge_mpsi_pcsi", "label": "CPGE Scientifique : MPSI / PCSI / MP2I"},
    {"id": "ecole_inge_postbac", "label": "École d'Ingénieurs Post-Bac (INSA / UT)"},
    {"id": "sciences_po_bl_droit", "label": "Sciences Po, Droit & Études Politiques"},
    {"id": "cpge_ecg_commerce", "label": "CPGE Économique & Commerciale : ECG"},
    {"id": "but_info_geii", "label": "BUT Informatique / Réseaux / Cyber"},
    {"id": "ensa_archi_gobelins", "label": "Architecture (ENSA) & Arts Appliqués"},
  ];

  // ==========================================
  //  VOLET 2 : DÉCODEUR DE TALENTS & VŒUX
  // ==========================================
  bool _isDownloadingPdf = false;

  Future<void> _handleDownloadDiagnosticPdf() async {
    if (_isDownloadingPdf) return;
    setState(() => _isDownloadingPdf = true);
    try {
      final res = await ApiService.exportDiagnosticPdf();
      if (!mounted) return;
      setState(() => _isDownloadingPdf = false);
      if (res.containsKey("error")) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentCoral,
            content: Text(res["error"].toString()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentEmerald,
            behavior: SnackBarBehavior.floating,
            content: Text("Fiche de Diagnostic téléchargée (${res['size_kb']} Ko)"),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDownloadingPdf = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accentCoral,
          content: Text("Erreur lors du téléchargement : $e"),
        ),
      );
    }
  }

  Widget _buildDownloadDiagnosticButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton.icon(
        icon: _isDownloadingPdf
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
              )
            : const Icon(Icons.picture_as_pdf_outlined, size: 18, color: AppTheme.primary),
        label: Text(
          _isDownloadingPdf ? "Génération du PDF..." : "Télécharger ma Fiche de Diagnostic PDF",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.primary, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _isDownloadingPdf ? null : _handleDownloadDiagnosticPdf,
      ),
    );
  }

  Widget _buildGpsStrategyShortcutButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton.icon(
        icon: const Icon(Icons.alt_route_rounded, size: 18, color: Colors.white),
        label: const Text(
          "Voir ma Stratégie GPS (3 Pôles)",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => MatchingScreen(profileData: _buildProfilePayload()),
            ),
          );
        },
      ),
    );
  }

  final Set<String> _selectedPassions = {};
  bool _talentsLocked = false;

  static const Map<String, Map<String, String>> _decodeurTalentsLocal = {
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

  final Set<String> _selectedSecteurs = {};
  final List<Map<String, dynamic>> _secteursDisponibles = [
    {"titre": "Santé, Médecine & Soins", "icone": Icons.medical_services_outlined},
    {"titre": "Intelligence Artificielle & Data", "icone": Icons.memory_outlined},
    {"titre": "Ingénierie, Robotique & Aéronautique", "icone": Icons.precision_manufacturing_outlined},
    {"titre": "Commerce, Finance & Audit", "icone": Icons.trending_up_outlined},
    {"titre": "Droit, Sciences Po & Relations Internationales", "icone": Icons.gavel_outlined},
    {"titre": "Architecture, BTP & Urbanisme", "icone": Icons.apartment_outlined},
  ];

  String? _roleVise;
  final List<Map<String, dynamic>> _rolesDisponibles = [
    {
      "titre": "Aide & Santé humaine",
      "desc": "Soigner, accompagner, conseiller et protéger les autres",
      "icone": Icons.favorite_border_outlined
    },
    {
      "titre": "Expertise technique & R&D",
      "desc": "Concevoir, programmer, analyser et inventer des technologies",
      "icone": Icons.science_outlined
    },
    {
      "titre": "Management & Leadership",
      "desc": "Piloter des projets, diriger des équipes et entreprendre",
      "icone": Icons.rocket_launch_outlined
    },
    {
      "titre": "Création & Design",
      "desc": "Imaginer des univers, prototyper des interfaces et créer",
      "icone": Icons.brush_outlined
    },
  ];

  String? _preferenceSociale;
  String? _environnement;
  String? _teletravail;

  final List<String> _optionsSociales = ["En équipe", "Autonome / Seul", "Peu importe"];
  final List<String> _optionsEnvironnement = [
    "Hôpital / Médical",
    "Bureau / Start-up",
    "Extérieur / Terrain",
    "Atelier / Labo"
  ];
  final List<String> _optionsTeletravail = [
    "Hybride",
    "Majoritairement Télétravail",
    "100% sur site / Terrain",
    "Peu importe"
  ];

  // ==========================================
  //  VOLET 3 : PROFILAGE RIASEC ADAPTÉ (15 QUESTIONS OFFICIELLES)
  // ==========================================
  static const List<Map<String, dynamic>> _riasecQuestions = [
    // R : Réaliste (max 4 pts)
    {
      "code": "R",
      "famille": "Réaliste",
      "sous_titre": "Pratique, concret, manuel, extérieur",
      "texte": "J'aime démonter des objets, bricoler, réparer ou comprendre comment fonctionne un moteur ou un appareil.",
    },
    {
      "code": "R",
      "famille": "Réaliste",
      "sous_titre": "Pratique, concret, manuel, extérieur",
      "texte": "Je préfère une activité où je bouge, travaille dehors ou fabrique quelque chose de mes mains plutôt que de rester assis toute la journée devant un écran.",
    },
    // I : Investigateur (max 6 pts)
    {
      "code": "I",
      "famille": "Investigateur",
      "sous_titre": "Logique, analyse, sciences, énigmes",
      "texte": "Quand je bloque sur un problème de maths ou une énigme, je préfère chercher longtemps par moi-même plutôt qu'on me donne la solution.",
    },
    {
      "code": "I",
      "famille": "Investigateur",
      "sous_titre": "Logique, analyse, sciences, énigmes",
      "texte": "J'aime regarder des vidéos de vulgarisation scientifique, d'astronomie, de tech ou comprendre l'origine des choses.",
    },
    {
      "code": "I",
      "famille": "Investigateur",
      "sous_titre": "Logique, analyse, sciences, énigmes",
      "texte": "Face à une information ou une rumeur, mon premier réflexe est de chercher les preuves et de vérifier si les chiffres sont vrais.",
    },
    // A : Artistique (max 4 pts)
    {
      "code": "A",
      "famille": "Artistique",
      "sous_titre": "Création, expression, originalité, design",
      "texte": "J'ai besoin d'exprimer mes idées à travers une forme de création (musique, dessin, montage vidéo, écriture, style vestimentaire).",
    },
    {
      "code": "A",
      "famille": "Artistique",
      "sous_titre": "Création, expression, originalité, design",
      "texte": "Je déteste suivre des règles rigides ou faire exactement comme tout le monde ; j'aime apporter ma propre touche.",
    },
    // S : Social (max 4 pts)
    {
      "code": "S",
      "famille": "Social",
      "sous_titre": "Entraide, écoute, transmission, équipe",
      "texte": "Quand un ami ou un camarade de classe a un problème ou ne comprend pas un cours, je prends naturellement le temps de lui expliquer.",
    },
    {
      "code": "S",
      "famille": "Social",
      "sous_titre": "Entraide, écoute, transmission, équipe",
      "texte": "Je préfère mille fois travailler en groupe ou faire du sport d'équipe plutôt que de bosser seul dans mon coin.",
    },
    // E : Entreprenant (max 6 pts)
    {
      "code": "E",
      "famille": "Entreprenant",
      "sous_titre": "Persuasion, leadership, initiative, défi",
      "texte": "Dans un projet de groupe ou une sortie entre amis, c'est souvent moi qui prends les devants et qui motive les autres pour décider.",
    },
    {
      "code": "E",
      "famille": "Entreprenant",
      "sous_titre": "Persuasion, leadership, initiative, défi",
      "texte": "J'aime l'idée de monter un projet, vendre un objet, négocier ou convaincre quelqu'un qui n'était pas d'accord avec moi au départ.",
    },
    {
      "code": "E",
      "famille": "Entreprenant",
      "sous_titre": "Persuasion, leadership, initiative, défi",
      "texte": "J'aime la compétition, les défis et voir directement le résultat concret de mes efforts.",
    },
    // C : Conventionnel (max 6 pts)
    {
      "code": "C",
      "famille": "Conventionnel",
      "sous_titre": "Organisation, méthode, rigueur, précision",
      "texte": "Mes affaires, mes dossiers de cours ou mes fichiers sur mon ordi/téléphone sont plutôt bien rangés et ordonnés.",
    },
    {
      "code": "C",
      "famille": "Conventionnel",
      "sous_titre": "Organisation, méthode, rigueur, précision",
      "texte": "J'aime savoir exactement ce qu'on attend de moi avec des consignes claires et un planning précis plutôt que d'improviser.",
    },
    {
      "code": "C",
      "famille": "Conventionnel",
      "sous_titre": "Organisation, méthode, rigueur, précision",
      "texte": "J'ai le sens du détail : je repère vite les fautes, les bugs ou les petites erreurs que les autres ne remarquent pas.",
    },
  ];

  final Map<int, int> _reponsesRiasec = {};
  int _current16PIndex = 0;

  bool get _hasSavedTalents => _selectedPassions.isNotEmpty && _talentsLocked;

  void _showTalentsAlreadySavedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppTheme.primary, size: 22),
            SizedBox(width: 8),
            Text(
              "Talents déjà enregistrés",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textMain),
            ),
          ],
        ),
        content: const Text(
          "Tes passions ont déjà été analysées et sont enregistrées dans ton Profil. Tu peux les consulter et les gérer directement dans ton onglet Profil.",
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer", style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onGoToProfile?.call();
            },
            child: const Text("Voir dans mon Profil"),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _extractionTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Map<String, double> get _riasecScores {
    double rRaw = 0, iRaw = 0, aRaw = 0, sRaw = 0, eRaw = 0, cRaw = 0;
    for (int i = 0; i < _riasecQuestions.length; i++) {
      final val = (_reponsesRiasec[i] ?? 0).toDouble();
      final code = _riasecQuestions[i]["code"];
      if (code == "R") rRaw += val;
      if (code == "I") iRaw += val;
      if (code == "A") aRaw += val;
      if (code == "S") sRaw += val;
      if (code == "E") eRaw += val;
      if (code == "C") cRaw += val;
    }
    // Normalisation en pourcentage (sur 100) selon le barème officiel du document
    return {
      "R": double.parse(((rRaw / 4.0) * 100).toStringAsFixed(1)),
      "I": double.parse(((iRaw / 6.0) * 100).toStringAsFixed(1)),
      "A": double.parse(((aRaw / 4.0) * 100).toStringAsFixed(1)),
      "S": double.parse(((sRaw / 4.0) * 100).toStringAsFixed(1)),
      "E": double.parse(((eRaw / 6.0) * 100).toStringAsFixed(1)),
      "C": double.parse(((cRaw / 6.0) * 100).toStringAsFixed(1)),
    };
  }

  int get _scoreLogique => (_riasecScores["I"]! / 10).round().clamp(0, 10);
  int get _scoreCommunication => (_riasecScores["E"]! / 10).round().clamp(0, 10);
  int get _scoreCreativite => (_riasecScores["A"]! / 10).round().clamp(0, 10);
  int get _scoreEmpathie => (_riasecScores["S"]! / 10).round().clamp(0, 10);
  int get _scoreOrganisation => (_riasecScores["C"]! / 10).round().clamp(0, 10);

  String get _dominantHollandCode {
    if (_reponsesRiasec.isEmpty) return ":";
    final sorted = _riasecScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return "${sorted[0].key}${sorted[1].key}";
  }

  List<Map<String, String>> get _recommendedMetiers {
    final code = _dominantHollandCode;

    final isIaData = _selectedSecteurs.any((s) => s.toLowerCase().contains("intelligence") || s.toLowerCase().contains("data"))
        || _selectedPassions.any((p) => p.toLowerCase().contains("programmation") || p.toLowerCase().contains("mods") || p.toLowerCase().contains("cyber"))
        || _selectedSpecialites.contains("Informatique / NSI")
        || (_selectedFiliereAmbitionId != null && _selectedFiliereAmbitionId!.contains("info"));

    final isSante = _selectedSecteurs.any((s) => s.toLowerCase().contains("santé") || s.toLowerCase().contains("médecine"))
        || (_selectedFiliereAmbitionId != null && _selectedFiliereAmbitionId!.contains("sante"));

    final isIngenierie = _selectedSecteurs.any((s) => s.toLowerCase().contains("ingénierie") || s.toLowerCase().contains("robotique") || s.toLowerCase().contains("aéronautique"))
        || _selectedPassions.any((p) => p.toLowerCase().contains("bricolage") || p.toLowerCase().contains("électronique"))
        || (_selectedFiliereAmbitionId != null && (_selectedFiliereAmbitionId!.contains("mpsi") || _selectedFiliereAmbitionId!.contains("inge")));

    final isCommerce = _selectedSecteurs.any((s) => s.toLowerCase().contains("commerce") || s.toLowerCase().contains("finance"))
        || (_selectedFiliereAmbitionId != null && _selectedFiliereAmbitionId!.contains("ecg"));

    final isDroitScPo = _selectedSecteurs.any((s) => s.toLowerCase().contains("droit") || s.toLowerCase().contains("sciences po"))
        || _selectedPassions.any((p) => p.toLowerCase().contains("débat") || p.toLowerCase().contains("éloquence"))
        || (_selectedFiliereAmbitionId != null && _selectedFiliereAmbitionId!.contains("po"));

    final isDesign = _selectedSecteurs.any((s) => s.toLowerCase().contains("architecture"))
        || _selectedPassions.any((p) => p.toLowerCase().contains("vidéo") || p.toLowerCase().contains("musique"));

    if (isIaData) {
      if (code.contains("R")) {
        return [
          {
            "titre": "Ingénieur IA & Robotique / MLOps",
            "filiere": "CPGE MP2I / MPSI ou Écoles d'Ingénieurs (INSA, UT, Polytech)",
            "desc": "Conception et déploiement de modèles de machine learning sur des infrastructures matérielles et serveurs cloud.",
          },
          {
            "titre": "Ingénieur Cybersécurité & Réseaux de Données",
            "filiere": "BUT Informatique / Réseaux ou Master Cyber",
            "desc": "Sécurisation des architectures cloud et analyse des vulnérabilités des systèmes d'intelligence artificielle.",
          },
        ];
      } else if (code.contains("E")) {
        return [
          {
            "titre": "Lead Data Scientist & Product Manager IA",
            "filiere": "Grandes Écoles d'Ingénieurs ou Double diplôme Ingénieur / Manager",
            "desc": "Pilotage stratégique de projets d'intelligence artificielle et valorisation des données d'entreprise.",
          },
          {
            "titre": "Consultant en Stratégie Data & IA",
            "filiere": "CPGE ECG / Sciences Po ou Master Data / Business Analytics",
            "desc": "Accompagnement des organisations pour intégrer des modèles prédictifs et des agents autonomes.",
          },
        ];
      } else if (code.contains("C")) {
        return [
          {
            "titre": "Data Engineer & Architecte Big Data",
            "filiere": "BUT Informatique (parcours DACS) ou Licence/Master Informatique",
            "desc": "Conception et automatisation de pipelines de données massives fiables pour alimenter les modèles IA.",
          },
          {
            "titre": "Analyste Big Data & Gouvernance des Données",
            "filiere": "Master Informatique / Gouvernance des données ou École spécialisée",
            "desc": "Gestion de la qualité des données, conformité réglementaire et optimisation des flux décisionnels.",
          },
        ];
      } else {
        return [
          {
            "titre": "Ingénieur R&D en Machine Learning & Deep Learning",
            "filiere": "CPGE MP2I/MPSI, ENS, Universités Paris-Saclay / Sorbonne",
            "desc": "Recherche algorithmique avancée, entraînement de réseaux neuronaux profonds et modèles de langage.",
          },
          {
            "titre": "Data Scientist & Concepteur de Modèles Prédictifs",
            "filiere": "Écoles d'ingénieurs (INSA, Télécom, Centrale) ou Master Math-Info",
            "desc": "Analyse prédictive de données complexes pour résoudre des problématiques techniques et sociétales.",
          },
        ];
      }
    }

    if (isSante) {
      return [
        {
          "titre": "Médecin / Spécialiste hospitalier",
          "filiere": "PASS / L.AS (Faculté de Santé / Médecine)",
          "desc": "Diagnostic clinique, prise en charge des patients et expertise médicale.",
        },
        {
          "titre": "Ingénieur en Technologies Médicales & Bio-santé",
          "filiere": "Écoles d'ingénieurs en santé (ISIFC, UTC Bio) ou Master Bio-santé",
          "desc": "Conception d'instruments médicaux de pointe et analyse de données biologiques.",
        },
      ];
    }

    if (isIngenierie) {
      return [
        {
          "titre": "Ingénieur en Systèmes Embarqués & Robotique",
          "filiere": "CPGE Scientifique (MPSI/PCSI) ou École d'Ingénieurs Post-Bac",
          "desc": "Programmation de microcontrôleurs, mécatronique et modélisation de robots autonomes.",
        },
        {
          "titre": "Ingénieur R&D Aéronautique & Énergies",
          "filiere": "Grandes Écoles d'Ingénieurs (ISAE-Supaéro, Centrale, Arts & Métiers)",
          "desc": "Optimisation des performances techniques et conception de prototypes industriels avancés.",
        },
      ];
    }

    if (isCommerce) {
      return [
        {
          "titre": "Analyste Financier & Business Analytics",
          "filiere": "CPGE ECG, Top Écoles de Commerce (HEC, ESSEC, ESCP) ou Dauphine",
          "desc": "Analyse de marché, valorisation d'actifs et modélisation économique stratégique.",
        },
        {
          "titre": "Chef de Projet Entrepreneuriat & Croissance",
          "filiere": "Programme Grande École ou BUT Gestion des Entreprises",
          "desc": "Développement commercial, négociation et coordination de nouveaux produits.",
        },
      ];
    }

    if (isDroitScPo) {
      return [
        {
          "titre": "Juriste en Droit des Nouvelles Technologies & IA",
          "filiere": "Sciences Po / IEP ou Master Droit du Numérique",
          "desc": "Régulation des données personnelles, propriété intellectuelle et contrats de haute technologie.",
        },
        {
          "titre": "Analyste en Politiques Publiques & Stratégie",
          "filiere": "Sciences Po, Affaires Publiques ou Double cursus Droit-Éco",
          "desc": "Évaluation d'impact de réformes et conseil aux institutions territoriales et nationales.",
        },
      ];
    }

    if (isDesign) {
      return [
        {
          "titre": "Lead Product Designer & UX Technologist",
          "filiere": "Écoles de Design (Ensci, Gobelins, Strate) ou BUT Métiers du Multimédia",
          "desc": "Création d'interfaces logicielles ergonomiques, prototypes interactifs et design de service.",
        },
        {
          "titre": "Architecte & Concepteur d'Espaces Innovants",
          "filiere": "Écoles Nationales Supérieures d'Architecture (ENSA)",
          "desc": "Modélisation 3D, maîtrise d'œuvre et conception d'habitats durables.",
        },
      ];
    }

    return [
      {
        "titre": "Ingénieur d'Études & Chef de Projet Technique",
        "filiere": "Classes Préparatoires aux Grandes Écoles ou Cycle Universitaire",
        "desc": "Conduite d'études complexes, résolution méthodique de problèmes et coordination de solutions.",
      },
      {
        "titre": "Analyste Stratégique & Conseil",
        "filiere": "Grandes Écoles ou BUT spécialisé",
        "desc": "Synthèse d'informations multidimensionnelles et accompagnement vers l'optimisation des résultats.",
      },
    ];
  }

  Map<String, String> get _hollandArchetypeDetails {
    final isIaData = _selectedSecteurs.any((s) => s.toLowerCase().contains("intelligence") || s.toLowerCase().contains("data"))
        || _selectedPassions.any((p) => p.toLowerCase().contains("programmation") || p.toLowerCase().contains("mods") || p.toLowerCase().contains("cyber"))
        || _selectedSpecialites.contains("Informatique / NSI")
        || (_selectedFiliereAmbitionId != null && _selectedFiliereAmbitionId!.contains("info"));

    final code = _dominantHollandCode;
    const mapping = {
      "IR": {
        "titre": "L'analyste de terrain",
        "desc": "Tu aimes comprendre comment fonctionnent les systèmes complexes, mais tu as besoin de voir une application concrète ou technique à tes idées.",
        "domaines": "Ingénierie, robotique, sciences appliquées, cybersécurité, biotechnologies."
      },
      "RI": {
        "titre": "L'ingénieur système & terrain",
        "desc": "Tu privilégies l'action concrète et la maîtrise technique appuyées sur une rigueur scientifique solide.",
        "domaines": "Aéronautique, électronique, énergies renouvelables, mécatronique."
      },
      "IE": {
        "titre": "Le stratège & innovateur tech",
        "desc": "Tu combines analyse rationnelle des données et vision d'impact pour convaincre et bâtir de nouveaux projets.",
        "domaines": "Intelligence artificielle, data science, conseil en stratégie, finance tech."
      },
      "EI": {
        "titre": "L'entrepreneur visionnaire",
        "desc": "Tu aimes piloter des équipes et lancer des initiatives en t'appuyant sur des preuves tangibles et des métriques claires.",
        "domaines": "Management technologique, entrepreneuriat, marketing stratégique."
      },
      "IA": {
        "titre": "Le chercheur concepteur",
        "desc": "Curieux et inventif, tu aimes explorer des hypothèses théoriques et concevoir des solutions originales hors des sentiers battus.",
        "domaines": "R&D, architecture, design industriel, modélisation 3D, neurosciences."
      },
      "AI": {
        "titre": "Le designer scientifique",
        "desc": "Tu mets ta créativité au service de concepts fonctionnels et d'expériences interactives novatrices.",
        "domaines": "UX/UI design, infographie scientifique, game design, médias interactifs."
      },
      "IS": {
        "titre": "L'expert pédagogue & santé",
        "desc": "Tu mobilises ton savoir scientifique et logique au service du bien commun et de l'aide aux autres.",
        "domaines": "Médecine, recherche biomédicale, enseignement, psychologie cognitive."
      },
      "SI": {
        "titre": "Le praticien d'écoute & de science",
        "desc": "L'humain est ta priorité absolue, éclairée par une démarche de compréhension rigoureuse.",
        "domaines": "Santé publique, soins infirmiers, orthophonie, kinésithérapie, ergonomie."
      },
      "IC": {
        "titre": "L'auditeur méthodique & data",
        "desc": "Précis, objectif et minutieux, tu aimes analyser des ensembles d'informations complexes sans laisser passer la moindre erreur.",
        "domaines": "Cybersécurité, audit financier, contrôle qualité, bio-informatique."
      },
      "CI": {
        "titre": "L'analyste de précision",
        "desc": "Tu excelles dans l'organisation rigoureuse des données et la conformité aux protocoles établis.",
        "domaines": "Gestion de bases de données, conformité réglementaire, actuariat, logistique."
      },
      "AS": {
        "titre": "Le créateur engagé & médiateur",
        "desc": "Tu t'exprimes à travers des réalisations sensibles et humaines destinées à rassembler et émouvoir.",
        "domaines": "Médiation culturelle, communication visuelle, journalisme, art-thérapie."
      },
      "SA": {
        "titre": "L'animateur & pédagogue créatif",
        "desc": "Tu transmets, coaches et soutiens autrui en utilisant l'imagination et l'expression.",
        "domaines": "Éducation, animation socio-culturelle, coaching, ressources humaines."
      },
      "AE": {
        "titre": "Le directeur artistique & communiquant",
        "desc": "Tu allie audace créative et sens de la conviction pour faire rayonner des projets artistiques.",
        "domaines": "Publicité, production audiovisuelle, événementiel, mode, relations publiques."
      },
      "EA": {
        "titre": "L'entrepreneur créatif",
        "desc": "Tu inventes de nouveaux concepts et sais les vendre avec enthousiasme.",
        "domaines": "Création de marque, médias numériques, communication d'influence."
      },
      "EC": {
        "titre": "Le gestionnaire de projets & affaires",
        "desc": "Organisé et orienté résultat, tu pilotes des projets en respectant les délais et les objectifs chiffrés.",
        "domaines": "Gestion d'entreprise, commerce international, droit des affaires, supply chain."
      },
      "CE": {
        "titre": "L'administrateur de gestion",
        "desc": "Méthodique et fiable, tu garantis le bon fonctionnement structurel et financier d'une organisation.",
        "domaines": "Expertise-comptable, contrôle de gestion, administration publique, gestion de patrimoine."
      },
      "ES": {
        "titre": "Le leader d'équipe & fédérateur",
        "desc": "Tu aimes motiver un collectif, négocier et accompagner chacun vers la réussite.",
        "domaines": "Management, management associatif, direction d'établissement, recrutement."
      },
      "SE": {
        "titre": "Le responsable des relations humaines",
        "desc": "Attentif aux besoins individuels, tu crées les conditions d'un travail d'équipe harmonieux et performant.",
        "domaines": "Ressources humaines, formation d'adultes, travail social, médiation."
      },
      "RC": {
        "titre": "Le technicien méthodique & précis",
        "desc": "Tu appliques des protocoles stricts sur des équipements concrets avec minutie et exactitude.",
        "domaines": "Maintenance industrielle, télécoms, topographie, contrôle technique."
      },
      "CR": {
        "titre": "L'opérateur de flux & sécurité",
        "desc": "Tu organises avec ordre et calme les opérations techniques et les inventaires.",
        "domaines": "Logistique d'entrepôt, gestion des stocks, gestion d'infrastructures."
      },
    };
    final resMap = Map<String, String>.from(mapping[code] ?? {
      "titre": "Profil Polyvalent & Équilibré",
      "desc": "Tes centres d'intérêts croisent harmonieusement plusieurs facettes du modèle Holland.",
      "domaines": "Filières pluridisciplinaires, classes préparatoires, licences générales, BUT."
    });
    if (isIaData) {
      resMap["domaines"] = "Intelligence Artificielle, Machine Learning, Data Science, Cybersécurité, Recherche & Dev.";
    }
    return resMap;
  }

  String get _mbtiArchetype => "Code Holland : $_dominantHollandCode : ${_hollandArchetypeDetails['titre']}";

  // --- Calculs Bulletin ---
  double? _calculerMoyenne() {
    if (_bulletinMoyenne != null) return _bulletinMoyenne!;
    if (_matieres.isEmpty) return null;
    final total = _matieres.values.reduce((a, b) => a + b);
    return double.parse((total / _matieres.length).toStringAsFixed(2));
  }

  List<String> _getPointsForts() {
    return _matieres.entries
        .where((e) => e.value >= 13.0)
        .map((e) => e.key)
        .toList();
  }

  String _getDominante() {
    if (_detectedDominante != null) return _detectedDominante!;
    if (_matieres.isEmpty) return "En attente de notes";

    double sciSum = 0;
    int sciCount = 0;
    double litSum = 0;
    int litCount = 0;

    _matieres.forEach((key, val) {
      final k = key.toLowerCase();
      if (k.contains("math") || k.contains("phys") || k.contains("chim") || k.contains("indus") || k.contains("ingén") || k.contains("svt") || k.contains("info")) {
        sciSum += val;
        sciCount++;
      } else if (k.contains("franc") || k.contains("litt") || k.contains("arab") || k.contains("hist") || k.contains("geo") || k.contains("angl") || k.contains("lang") || k.contains("philo") || k.contains("islam")) {
        litSum += val;
        litCount++;
      }
    });

    final sciAvg = sciCount > 0 ? (sciSum / sciCount) : 0.0;
    final litAvg = litCount > 0 ? (litSum / litCount) : 0.0;
    final moy = _calculerMoyenne() ?? 0.0;

    if (sciAvg >= 13.5 && sciAvg > litAvg + 0.8) {
      return "Dominante Scientifique & Technique";
    } else if (litAvg >= 13.5 && litAvg > sciAvg + 0.8) {
      return "Dominante Littéraire, Humaine & Langues";
    } else if (moy >= 13.5) {
      return "Profil Équilibré & Polyvalent";
    } else {
      return "Profil Général en Évolution";
    }
  }

  Future<void> _syncToBackendIfReady() async {
    if (_classeActuelle == null && _matieres.isEmpty) return;
    await ApiService.saveStudentProfileAndGrades(
      classeActuelle: _classeActuelle ?? "Non renseignée",
      targetDomain: _selectedSecteurs.isNotEmpty ? _selectedSecteurs.first : null,
      specialties: _selectedSpecialites.toList(),
      interests: _selectedPassions.toList(),
      riasecScores: _riasecScores,
      grades: Map<String, double>.from(_matieres),
    );
  }

  Future<void> _pickAndUploadBulletin() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );

      if (pickedFiles.isEmpty) return;

      final file = pickedFiles.first;
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        setState(() {
          _bulletinUploadMessage = "Le fichier sélectionné est vide.";
          _bulletinSuccess = false;
        });
        return;
      }

      _extractionTimer?.cancel();
      _detectedLiveItems.clear();
      setState(() {
        _isUploadingBulletin = true;
        _extractionProgress = 0.08;
        _extractionStep = " Numérisation et découpage OCR du document...";
        _bulletinUploadMessage = null;
      });

      _extractionTimer = Timer.periodic(const Duration(milliseconds: 140), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_extractionProgress < 0.28) {
            _extractionProgress += 0.04;
            _extractionStep = " Prétraitement et détection des contrastes...";
          } else if (_extractionProgress < 0.52) {
            _extractionProgress += 0.035;
            _extractionStep = " Détection du tableau de notes & coefficients...";
            if (!_detectedLiveItems.contains("Tableau OCR")) {
              _detectedLiveItems.add("Tableau OCR");
            }
          } else if (_extractionProgress < 0.76) {
            _extractionProgress += 0.03;
            _extractionStep = " Extraction des matières & conversion sur 20...";
            if (!_detectedLiveItems.contains("Matières & Notes")) {
              _detectedLiveItems.add("Matières & Notes");
            }
          } else if (_extractionProgress < 0.92) {
            _extractionProgress += 0.015;
            _extractionStep = " Calcul de la moyenne générale et dominante...";
            if (!_detectedLiveItems.contains("Moyenne & Dominante")) {
              _detectedLiveItems.add("Moyenne & Dominante");
            }
          }
        });
      });

      final res = await ApiService.uploadAndParseBulletin(
        fileBytes: bytes,
        filename: file.name,
      );

      _extractionTimer?.cancel();

      if (res.containsKey("error")) {
        setState(() {
          _isUploadingBulletin = false;
          _bulletinUploadMessage = res["error"];
          _bulletinSuccess = false;
        });
        return;
      }

      if (mounted) {
        setState(() {
          _extractionProgress = 1.0;
          _extractionStep = " Extraction terminée avec succès !";
        });
        await Future.delayed(const Duration(milliseconds: 400));
      }

      final parsedMatieres = res["matieres"] as Map<String, dynamic>?;
      final parsedMoyenne = (res["moyenne_generale"] as num?)?.toDouble();
      final parsedDominante = res["dominante"] as String?;
      final parsedClasse = res["classe_detectee"] as String?;
      final parsedSpecs = (res["specialites_detectees"] as List?)
          ?.map((e) => e.toString())
          .toList();
      final parsedLycee = res["lycee_detecte"] as Map<String, dynamic>?;
      if (parsedLycee != null) {
        _detectedLycee = parsedLycee;
      }

      if (parsedMatieres != null && parsedMatieres.isNotEmpty) {
        setState(() {
          _matieres.clear();
          parsedMatieres.forEach((key, val) {
            _matieres[key] = (val as num).toDouble();
          });
          if (parsedMoyenne != null) {
            _bulletinMoyenne = parsedMoyenne;
          }
          if (parsedDominante != null && parsedDominante.isNotEmpty) {
            _detectedDominante = parsedDominante;
          }
          if (parsedClasse != null && parsedClasse.isNotEmpty) {
            _classeActuelle = parsedClasse;
          }
          if (parsedSpecs != null && parsedSpecs.isNotEmpty) {
            for (final sp in parsedSpecs) {
              if (_specialitesDisponibles.contains(sp)) {
                _selectedSpecialites.add(sp);
              }
            }
          }
          _isUploadingBulletin = false;
          _bulletinSuccess = true;
          final moyLabel = parsedMoyenne != null ? " • Moyenne: ${parsedMoyenne.toStringAsFixed(2)}/20" : "";
          _bulletinUploadMessage = "Bulletin analysé avec succès ! ${parsedMatieres.length} matières importées$moyLabel";
        });
        await _syncToBackendIfReady();
      } else {
        setState(() {
          _isUploadingBulletin = false;
          _bulletinSuccess = false;
          _bulletinUploadMessage = "Aucune note n'a pu être détectée automatiquement sur ce document.";
        });
      }
    } catch (e) {
      _extractionTimer?.cancel();
      setState(() {
        _isUploadingBulletin = false;
        _bulletinUploadMessage = "Erreur lors du téléversement : $e";
        _bulletinSuccess = false;
      });
    }
  }

  Widget _buildExtractionSimulationCard() {
    final pct = (_extractionProgress * 100).toInt().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.document_scanner_outlined, color: AppTheme.primaryLight, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Lecture du bulletin scolaire",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textMain),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                ),
                child: Text(
                  "$pct %",
                  style: const TextStyle(
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _extractionProgress,
              minHeight: 8,
              backgroundColor: AppTheme.borderColorSoft,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _extractionStep,
            style: const TextStyle(
              color: AppTheme.primaryLight,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getMoyenneColor(double? moy) {
    if (moy == null) return AppTheme.textMuted;
    if (moy >= 15.0) return AppTheme.accentEmerald;
    if (moy >= 12.0) return AppTheme.accentAmber;
    return AppTheme.accentCoral;
  }

  Map<String, dynamic> _buildProfilePayload() {
    final effectiveMatieres = _matieres.isNotEmpty
        ? _matieres
        : <String, double>{};

    String? resolvedFiliereId = _selectedFiliereAmbitionId;
    if (effectiveMatieres.isEmpty && _selectedPassions.isNotEmpty) {
      final pStr = _selectedPassions.join(" ").toLowerCase();
      if (pStr.contains("gaming") || pStr.contains("programmation") || pStr.contains("cyber") || pStr.contains("serveurs")) {
        resolvedFiliereId = "but_info_geii";
      } else if (pStr.contains("manga") || pStr.contains("dessin") || pStr.contains("musique") || pStr.contains("montage")) {
        resolvedFiliereId = "ensa_archi_gobelins";
      } else if (pStr.contains("achat-revente") || pStr.contains("sneakers") || pStr.contains("commerce")) {
        resolvedFiliereId = "cpge_ecg_commerce";
      } else if (pStr.contains("débat") || pStr.contains("éloquence") || pStr.contains("géopolitique")) {
        resolvedFiliereId = "sciences_po_bl_droit";
      } else if (pStr.contains("bricolage") || pStr.contains("mécanique") || pStr.contains("électronique")) {
        resolvedFiliereId = "ecole_inge_postbac";
      } else if (pStr.contains("sport") || pStr.contains("aide")) {
        resolvedFiliereId = "pass_las_medecine";
      }
    }

    return {
      "classe_actuelle": _classeActuelle,
      "specialites_choisies": _selectedSpecialites.toList(),
      "filiere_ambition_id": resolvedFiliereId,
      "riasec_scores": _riasecScores,
      "passions_brutes": _selectedPassions.toList(),
      "creativite": _scoreCreativite,
      "empathie": _scoreEmpathie,
      "communication": _scoreCommunication,
      "organisation": _scoreOrganisation,
      "logique": _scoreLogique,
      "mbti_archetype": _mbtiArchetype,
      "secteurs_souhaits": _selectedSecteurs.toList(),
      "role_vise": _roleVise,
      "style_vie": _teletravail,
      "preferences_sociales": _preferenceSociale,
      "environnement_prefere": _environnement,
      "lycee_nom": _detectedLycee?["nom"],
      "lycee_ville": _detectedLycee?["ville"],
      "lycee_region": _detectedLycee?["region"],
      "lycee_bonus_selectivite": _detectedLycee?["bonus_selectivite"],
      "bulletin": {
        "lycee_nom": _detectedLycee?["nom"],
        "lycee_ville": _detectedLycee?["ville"],
        "lycee_region": _detectedLycee?["region"],
        "lycee_bonus_selectivite": _detectedLycee?["bonus_selectivite"],
        "moyenne_generale": _calculerMoyenne(),
        "matieres": effectiveMatieres,
        "classe_actuelle": _classeActuelle,
        "specialites": _selectedSpecialites.toList(),
        "points_forts": _getPointsForts(),
        "dominante": _getDominante(),
      },
    };
  }

  Future<void> _runGapAnalyzerNow() async {
    if (_classeActuelle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sélectionne d'abord ta classe actuelle.")),
      );
      return;
    }
    if (_selectedFiliereAmbitionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sélectionne une filière visée.")),
      );
      return;
    }
    if (_matieres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Importe ton bulletin ou ajoute au moins une note.")),
      );
      return;
    }

    setState(() => _isComputingGap = true);
    try {
      await _syncToBackendIfReady();
      final payload = _buildProfilePayload();
      final res = await ApiService.runGapAnalyzer(payload);
      if (!mounted) return;
      if (!res.containsKey("error")) {
        setState(() {
          _gapAnalysisResult = res;
        });
        await ProgressService.saveGapAnalysis(res);
        final moy = ((payload["bulletin"] as Map)["moyenne_generale"] as num?)?.toDouble() ?? 0.0;
        final matMap = Map<String, double>.from((payload["bulletin"] as Map)["matieres"] as Map);
        final prob = (res["probabilite_admission"] as num?)?.toInt() ?? 0;
        await ProgressService.recordMonthlyCheckpoint(
          moyenneGenerale: moy,
          matieres: matMap,
          admissionProbability: prob,
          filiereCible: res["filiere_cible"]?.toString(),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isComputingGap = false);
      }
    }
  }

  Future<void> _launchFullAnalysis() async {
    await _syncToBackendIfReady();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MatchingScreen(
          profileData: _buildProfilePayload(),
        ),
      ),
    );
  }

  // --- Composant RIASEC 15 Questions officielles ---
  void _onRiasecOptionSelected(int questionIndex, int val) {
    setState(() {
      _reponsesRiasec[questionIndex] = val;
    });
  }

  Widget _build16PCardFlow() {
    final isSummary = _current16PIndex >= _riasecQuestions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. En-tête : Titre & Numéro d'étape (Fix overflow 81px avec Expanded)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Profilage RIASEC",
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "15 questions rapides : choisis spontanément ton degré d'accord.",
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                isSummary ? "Terminé" : "Q${_current16PIndex + 1}/15",
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. Barre de progression continue
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: isSummary ? 1.0 : (_current16PIndex + 1) / _riasecQuestions.length,
            minHeight: 6,
            backgroundColor: AppTheme.borderColorSoft,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
        const SizedBox(height: 12),

        // Pastilles d'étapes horizontales défilables (Fix overflow 35px & sans trophée)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...List.generate(_riasecQuestions.length, (i) {
                final isCurrent = i == _current16PIndex;
                final isAnswered = _reponsesRiasec.containsKey(i);

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _current16PIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppTheme.primary
                            : isAnswered
                                ? AppTheme.accentEmeraldSoft
                                : AppTheme.cardBgElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? AppTheme.primary
                              : isAnswered
                                  ? AppTheme.accentEmerald.withValues(alpha: 0.5)
                                  : AppTheme.borderColor,
                        ),
                      ),
                      child: Text(
                        "Q${i + 1}",
                        style: TextStyle(
                          color: isCurrent
                              ? Colors.white
                              : isAnswered
                                  ? AppTheme.accentEmerald
                                  : AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              GestureDetector(
                onTap: () => setState(() => _current16PIndex = _riasecQuestions.length),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSummary ? AppTheme.accentAmberSoft : AppTheme.cardBgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSummary ? AppTheme.accentAmber : AppTheme.borderColor),
                  ),
                  child: Text(
                    "Fin",
                    style: TextStyle(
                      color: isSummary ? AppTheme.accentAmber : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 3. Carte Active : Question Unique OU Bilan Archétype
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: isSummary
              ? _build16PFinalResultCard()
              : _buildSingleQuestionCard(_current16PIndex, _riasecQuestions[_current16PIndex]),
        ),
      ],
    );
  }

  Widget _buildSingleQuestionCard(int index, Map<String, dynamic> q) {
    final currentVal = _reponsesRiasec[index];

    return Container(
      key: ValueKey('riasec_question_$index'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Question ${index + 1} / ${_riasecQuestions.length}",
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.cardBgElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Text(
                  "${((index + 1) / _riasecQuestions.length * 100).toInt()}%",
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Énoncé de la question
          Text(
            q["texte"] ?? "",
            style: const TextStyle(
              color: AppTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),

          // 3 Options officielles (0: Pas du tout moi, 1: Un peu moi, 2: Tout à fait moi)
          Column(
            children: [
              _buildRiasecOptionTile(
                index: index,
                value: 0,
                label: "Pas du tout moi",
                icon: Icons.radio_button_unchecked,
                isSelected: currentVal == 0,
              ),
              const SizedBox(height: 8),
              _buildRiasecOptionTile(
                index: index,
                value: 1,
                label: "Un peu moi",
                icon: Icons.check_circle_outline,
                isSelected: currentVal == 1,
              ),
              const SizedBox(height: 8),
              _buildRiasecOptionTile(
                index: index,
                value: 2,
                label: "Tout à fait moi",
                icon: Icons.check_circle,
                isSelected: currentVal == 2,
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Boutons Précédent / Suivant
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (index > 0)
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text("Précédent"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textMain,
                    side: const BorderSide(color: AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() => _current16PIndex--),
                )
              else
                const SizedBox(width: 80),

              ElevatedButton.icon(
                icon: Icon(
                  index == _riasecQuestions.length - 1 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  index == _riasecQuestions.length - 1 ? "Voir mes résultats" : "Suivant",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() {
                    if (index < _riasecQuestions.length) {
                      _current16PIndex = index + 1;
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiasecOptionTile({
    required int index,
    required int value,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    Color selectedColor;
    Color softColor;
    if (value == 0) {
      selectedColor = const Color(0xFF64748B);
      softColor = const Color(0xFFF1F5F9);
    } else if (value == 1) {
      selectedColor = const Color(0xFF0284C7);
      softColor = const Color(0xFFE0F2FE);
    } else {
      selectedColor = const Color(0xFF059669);
      softColor = const Color(0xFFD1FAE5);
    }

    return InkWell(
      onTap: () {
        _onRiasecOptionSelected(index, value);
        Future.delayed(const Duration(milliseconds: 220), () {
          if (mounted && _current16PIndex == index && index < _riasecQuestions.length) {
            setState(() {
              _current16PIndex = index + 1;
            });
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? softColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? selectedColor : AppTheme.borderColor,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? selectedColor : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.textMain : AppTheme.textMuted,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build16PFinalResultCard() {
    final details = _hollandArchetypeDetails;
    final scores = _riasecScores;

    return Container(
      key: const ValueKey('riasec_summary_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35), width: 1.5),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.psychology_rounded, color: AppTheme.primary, size: 36),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              "Profilage RIASEC Complété",
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Code Holland : $_dominantHollandCode : ${details['titre']}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  details["desc"] ?? "",
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  "Domaines recommandés : ${details['domaines'] ?? ''}",
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            "Métiers cibles alignés avec tes choix & ton profil :",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          ..._recommendedMetiers.map((metier) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardBgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.work_outline_rounded, size: 16, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          metier["titre"] ?? "",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textMain),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    metier["desc"] ?? "",
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMain, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Text(
                      "Voies : ${metier['filiere'] ?? ''}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text(
            "Répartition de tes scores normalisés (% sur 100) :",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),

          _buildScoreBar("R • Réaliste (terrain & manuel)", (scores["R"] ?? 0).round(), 100, const Color(0xFF0D9488)),
          _buildScoreBar("I • Investigateur (sciences & logique)", (scores["I"] ?? 0).round(), 100, const Color(0xFF2563EB)),
          _buildScoreBar("A • Artistique (création & design)", (scores["A"] ?? 0).round(), 100, const Color(0xFFD97706)),
          _buildScoreBar("S • Social (entraide & transmission)", (scores["S"] ?? 0).round(), 100, const Color(0xFFE11D48)),
          _buildScoreBar("E • Entreprenant (leadership & projets)", (scores["E"] ?? 0).round(), 100, const Color(0xFF7C3AED)),
          _buildScoreBar("C • Conventionnel (organisation & rigueur)", (scores["C"] ?? 0).round(), 100, const Color(0xFF059669)),

          const SizedBox(height: 22),

          // Boutons d'action
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text(
                    "Recommencer",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textMain,
                    side: const BorderSide(color: AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() {
                      _reponsesRiasec.clear();
                      _current16PIndex = 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  label: const Text(
                    "Valider mon profil",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    await _syncToBackendIfReady();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Profil RIASEC enregistré avec succès !"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDownloadDiagnosticButton(),
          const SizedBox(height: 4),
          _buildGpsStrategyShortcutButton(),
        ],
      ),
    );
  }

  Widget _buildScoreBar(String label, int score, int maxScore, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text("$score / $maxScore", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (score / maxScore).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.borderColorSoft,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moyenne = _calculerMoyenne();
    final pointsForts = _getPointsForts();
    final dominante = _getDominante();
    final moyenneColor = _getMoyenneColor(moyenne);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Profil & Orientation"),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: "1. Notes & Écart"),
            Tab(icon: Icon(Icons.bolt_outlined), text: "2. Talents"),
            Tab(icon: Icon(Icons.psychology_outlined), text: "3. RIASEC"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ==========================================
          //  ONGLET 1 : DOSSIER SCOLAIRE & BULLETINS
          // ==========================================
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. CLASSE & SPÉCIALITÉS
                const Text(
                  "1. Ta classe actuelle :",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _classesDisponibles.map((cl) {
                    final isSel = _classeActuelle == cl;
                    return ChoiceChip(
                      label: Text(cl),
                      selected: isSel,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : AppTheme.textMain,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isSel ? AppTheme.primary : AppTheme.borderColor),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _classeActuelle = cl);
                          _syncToBackendIfReady();
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Spécialités (Lycée)
                if (_classeActuelle == "Première" || _classeActuelle == "Terminale") ...[
                  const Text(
                    "Tes spécialités choisies :",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _specialitesDisponibles.map((sp) {
                      final isSel = _selectedSpecialites.contains(sp);
                      return FilterChip(
                        label: Text(sp),
                        selected: isSel,
                        selectedColor: AppTheme.primary,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : AppTheme.textMain,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                          fontSize: 12.5,
                        ),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isSel ? AppTheme.primary : AppTheme.borderColor),
                        ),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedSpecialites.add(sp);
                            } else {
                              _selectedSpecialites.remove(sp);
                            }
                          });
                          _syncToBackendIfReady();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                // 2. FILIÈRE AMBITION VISÉE
                const Text(
                  "2. Filière d'Ambition visée :",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedFiliereAmbitionId,
                      hint: const Text(
                        "Choisir une filière cible...",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                      items: _filieresAmbitionDisponibles.map((fil) {
                        return DropdownMenuItem<String>(
                          value: fil["id"],
                          child: Text(fil["label"] ?? ""),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedFiliereAmbitionId = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Bouton Calculer l'écart aux seuils
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: _isComputingGap
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.calculate_outlined, color: Colors.white),
                    label: Text(
                      _isComputingGap ? "Calcul en cours..." : "Calculer mon écart aux seuils",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _isComputingGap ? null : _runGapAnalyzerNow,
                  ),
                ),

                // Résultat du Gap Analyzer
                if (_gapAnalysisResult != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _gapAnalysisResult!["filiere_cible"] ?? "Filière Cible",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textMain),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primarySoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${_gapAnalysisResult!['probabilite_admission'] ?? 0}% d'admission",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...((_gapAnalysisResult!["ecarts_matieres"] as List?) ?? []).map((ecart) {
                          final mat = ecart["matiere"] ?? "";
                          final delta = (ecart["delta"] as num?)?.toDouble() ?? 0.0;
                          final seuil = (ecart["seuil_attendu"] as num?)?.toDouble() ?? 0.0;
                          final noteAct = (ecart["note_actuelle"] as num?)?.toDouble() ?? 0.0;
                          final c = delta >= 0 ? AppTheme.accentEmerald : AppTheme.accentCoral;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "$mat : $noteAct / $seuil",
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMain),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: c.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    delta >= 0 ? "+$delta pt OK" : "$delta pt à combler",
                                    style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Carte Scan Bulletin
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _bulletinSuccess
                          ? AppTheme.accentEmerald.withValues(alpha: 0.6)
                          : AppTheme.borderColor,
                      width: 1.2,
                    ),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primarySoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.document_scanner_outlined, color: AppTheme.primary, size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Importer un Bulletin",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  "PDF Pronote / EcoleDirecte / ENT ou Photo",
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isUploadingBulletin) ...[
                        _buildExtractionSimulationCard(),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.file_upload_outlined),
                            label: const Text("Parcourir mon fichier"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _pickAndUploadBulletin,
                          ),
                        ),
                      ],
                      if (_bulletinUploadMessage != null && !_isUploadingBulletin) ...[
                        const SizedBox(height: 10),
                        Text(
                          _bulletinUploadMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _bulletinSuccess ? AppTheme.accentEmerald : AppTheme.accentAmber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Synthèse Bulletin (Fix overflow 19px avec Flexible)
                Container(
                  padding: const EdgeInsets.all(18),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Moyenne Générale", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    moyenne != null ? moyenne.toStringAsFixed(2) : "-",
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: moyenneColor,
                                    ),
                                  ),
                                  const Text(" / 20", style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: moyenne != null ? AppTheme.accentEmeraldSoft : AppTheme.cardBgElevated,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: moyenne != null
                                      ? AppTheme.accentEmerald.withValues(alpha: 0.3)
                                      : AppTheme.borderColor,
                                ),
                              ),
                              child: Text(
                                dominante,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: TextStyle(
                                  color: moyenne != null ? AppTheme.accentEmerald : AppTheme.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (pointsForts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Divider(color: AppTheme.borderColor),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: pointsForts.map((matiere) {
                            final note = _matieres[matiere] ?? 0.0;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.accentEmeraldSoft,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.accentEmerald.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "$matiere : ${note.toStringAsFixed(1)}",
                                    style: const TextStyle(color: AppTheme.textMain, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Bouton suivant vers Décodeur de Talents
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    label: const Text(
                      "Étape 2 : Décodeur de Talents & Vœux ",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () => _tabController.animateTo(1),
                  ),
                ),
                const SizedBox(height: 10),
                _buildDownloadDiagnosticButton(),
                const SizedBox(height: 4),
                _buildGpsStrategyShortcutButton(),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ==========================================
          //  ONGLET 2 : DÉCODEUR DE TALENTS & VŒUX
          // ==========================================
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Décodeur de Talents",
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Sélectionne tes passions réelles hors-cadre scolaire pour valoriser tes compétences méthodologiques et arguments concrets sur Parcoursup.",
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
                ),
                const SizedBox(height: 14),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _decodeurTalentsLocal.keys.map((passion) {
                    final isSel = _selectedPassions.contains(passion);
                    return FilterChip(
                      selected: isSel,
                      label: Text(passion),
                      selectedColor: AppTheme.primary,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : AppTheme.textMain,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12.5,
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isSel ? AppTheme.primary : AppTheme.borderColor),
                      ),
                      onSelected: (v) {
                        if (_hasSavedTalents) {
                          _showTalentsAlreadySavedDialog();
                          return;
                        }
                        setState(() {
                          if (v) {
                            _selectedPassions.add(passion);
                            if (passion.contains("Gaming") || passion.contains("Programmation")) {
                              _selectedFiliereAmbitionId = "but_info_geii";
                            } else if (passion.contains("Manga") || passion.contains("Production musicale") || passion.contains("Montage")) {
                              _selectedFiliereAmbitionId = "ensa_archi_gobelins";
                            } else if (passion.contains("Achat-Revente") || passion.contains("Sneakers")) {
                              _selectedFiliereAmbitionId = "cpge_ecg_commerce";
                            } else if (passion.contains("Débat") || passion.contains("Éloquence")) {
                              _selectedFiliereAmbitionId = "sciences_po_bl_droit";
                            } else if (passion.contains("Bricolage") || passion.contains("Mécanique")) {
                              _selectedFiliereAmbitionId = "ecole_inge_postbac";
                            } else if (passion.contains("Sport") || passion.contains("Aide aux autres")) {
                              _selectedFiliereAmbitionId = "pass_las_medecine";
                            }
                          } else {
                            _selectedPassions.remove(passion);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),

                if (_selectedPassions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Text(
                        "Compétences décodées :",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                      ),
                      TextButton.icon(
                        icon: Icon(_talentsLocked ? Icons.lock_rounded : Icons.save_outlined, size: 14),
                        label: Text(
                          _talentsLocked ? "Verrouillé dans le Profil" : "Enregistrer dans le Profil",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          foregroundColor: _talentsLocked ? AppTheme.accentEmerald : AppTheme.primary,
                        ),
                        onPressed: () async {
                          setState(() => _talentsLocked = true);
                          await _syncToBackendIfReady();
                          try {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user != null) {
                              await UserService.updateAcademicStrategy(
                                uid: user.uid,
                                passionsDecoded: _selectedPassions.toList(),
                              );
                            }
                          } catch (_) {}
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Talents enregistrés ! Tu peux les consulter dans ton onglet Profil."),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._selectedPassions.map((passion) {
                    final info = _decodeurTalentsLocal[passion]!;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            passion,
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "• Compétence académique : ${info['academique']}",
                            style: const TextStyle(color: AppTheme.textMain, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "• Compétence pro : ${info['pro']}",
                            style: const TextStyle(color: AppTheme.textMain, fontSize: 12.5),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.accentEmeraldSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "Argument Parcoursup : ${info['parcoursup']}",
                              style: const TextStyle(color: AppTheme.textMain, fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 22),

                // 1. SECTEURS D'INTÉRÊT
                const Text(
                  "Secteurs professionnels visés :",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _secteursDisponibles.map((sec) {
                    final titre = sec["titre"] as String;
                    final icone = sec["icone"] as IconData;
                    final isSelected = _selectedSecteurs.contains(titre);

                    return FilterChip(
                      selected: isSelected,
                      label: Text(titre),
                      avatar: Icon(icone, size: 16, color: isSelected ? Colors.white : AppTheme.primary),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textMain,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      ),
                      selectedColor: AppTheme.primary,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primary : AppTheme.borderColor,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedSecteurs.add(titre);
                          } else {
                            _selectedSecteurs.remove(titre);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 26),

                /* 
                // 2. RÔLE D'IMPACT VISÉ
                const Text(
                  "Comment te vois-tu agir au quotidien ?",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 12),

                ..._rolesDisponibles.map((r) {
                  final titre = r["titre"] as String;
                  final desc = r["desc"] as String;
                  final icone = r["icone"] as IconData;
                  final isSelected = _roleVise == titre;

                  return GestureDetector(
                    onTap: () => setState(() => _roleVise = (_roleVise == titre) ? null : titre),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primarySoft : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.borderColor,
                          width: isSelected ? 1.6 : 1.0,
                        ),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : AppTheme.cardBgElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icone, color: isSelected ? AppTheme.primary : AppTheme.textMuted, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titre,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isSelected ? AppTheme.primary : AppTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (isSelected) const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 22),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                */

                // 3. STYLE DE VIE & CADRE
                const Text(
                  "Cadre & Rythme de travail souhaité :",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String?>(
                  initialValue: _environnement,
                  dropdownColor: AppTheme.cardBg,
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 15),
                  decoration: const InputDecoration(labelText: "Cadre de travail"),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text("Non défini / Peu importe", style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    ..._optionsEnvironnement.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
                  ],
                  onChanged: (v) => setState(() => _environnement = v),
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String?>(
                  initialValue: _preferenceSociale,
                  dropdownColor: AppTheme.cardBg,
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 15),
                  decoration: const InputDecoration(labelText: "Mode relationnel"),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text("Non défini / Peu importe", style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    ..._optionsSociales.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
                  ],
                  onChanged: (v) => setState(() => _preferenceSociale = v),
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String?>(
                  initialValue: _teletravail,
                  dropdownColor: AppTheme.cardBg,
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 15),
                  decoration: const InputDecoration(labelText: "Télétravail / Mobilité"),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text("Non défini / Peu importe", style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    ..._optionsTeletravail.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
                  ],
                  onChanged: (v) => setState(() => _teletravail = v),
                ),

                const SizedBox(height: 26),

                // Bouton 1 : Lancer directement le matching avec les vœux
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.explore_outlined, color: Colors.white),
                    label: const Text(
                      "Découvrir mes orientations recommandées",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _launchFullAnalysis,
                  ),
                ),
                const SizedBox(height: 12),

                // Bouton 2 : Suivant vers Test RIASEC
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.arrow_forward, color: AppTheme.primaryLight),
                    label: const Text(
                      "Étape suivante : Profilage RIASEC ",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryLight),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _tabController.animateTo(2),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ==========================================
          //  ONGLET 3 : PROFILAGE RIASEC ADAPTÉ
          // ==========================================
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _build16PCardFlow(),
          ),
        ],
      ),
    );
  }
}
