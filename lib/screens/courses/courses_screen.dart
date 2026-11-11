import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const String _storageKey = "user_courses_evolution_v1";

  List<Map<String, dynamic>> _userCourses = [];
  String _selectedSubjectFilter = "Toutes";

  // Banque d'épreuves de référence
  final List<Map<String, dynamic>> _banqueEpreuves = [
    {
      "matiere": "Mathématiques",
      "titre": "Sujet Bac Métropole 2024 • Session Principale",
      "duree": "4h00",
      "coeff": "16",
      "niveau": "Examen Officiel",
      "themes": "Suites & Récurrence, Géométrie dans l'espace, Loi binomiale, Fonctions exponentielles",
      "correction": "4 exercices complets corrigés avec barème officiel et points de vigilance de rédaction.",
    },
    {
      "matiere": "Mathématiques",
      "titre": "Concours Avenir / Puissance Alpha • QCM Ingénieurs",
      "duree": "1h30",
      "coeff": "Concours",
      "niveau": "Sélectif Ingénieur",
      "themes": "Calcul rapide, Logique, Limites, Trigonométrie, Probabilités conditionnelles",
      "correction": "45 questions à choix multiples avec astuces d'élimination rapide des distracteurs.",
    },
    {
      "matiere": "Physique-Chimie",
      "titre": "Sujet Bac Métropole 2024 • Physique & Chimie",
      "duree": "3h30",
      "coeff": "16",
      "niveau": "Examen Officiel",
      "themes": "Cinématique de Newton, Lunette astronomique, Titrage acido-basique, Synthèse organique",
      "correction": "Analyse dimensionnelle détaillée et justification des chiffres significatifs.",
    },
    {
      "matiere": "Physique-Chimie",
      "titre": "Devoir Type Prépa PCSI • Mécanique & Électrocinétique",
      "duree": "3h00",
      "coeff": "Prépa",
      "niveau": "Excellence Prépa",
      "themes": "Oscillateurs harmoniques amortis, Régime transitoire RLC, Énergie mécanique",
      "correction": "Résolution littérale intégrale et tracé des portraits de phase.",
    },
    {
      "matiere": "Informatique / NSI",
      "titre": "Épreuve Pratique & Écrite NSI • Sujet Bac 2024",
      "duree": "3h30",
      "coeff": "16",
      "niveau": "Examen Officiel",
      "themes": "Arbres binaires de recherche, Algorithmes gloutons, SQL et bases de données relationnelles",
      "correction": "Code Python complet commenté et requêtes SQL optimisées.",
    },
    {
      "matiere": "SVT",
      "titre": "Sujet Bac SVT 2024 • Sciences de la Vie et de la Terre",
      "duree": "3h30",
      "coeff": "16",
      "niveau": "Examen Officiel",
      "themes": "Génétique et évolution, Tectonique des plaques, Immunité adaptative",
      "correction": "Schémas bilans légendés et synthèse argumentative conforme aux attendus.",
    },
    {
      "matiere": "SES / Économie",
      "titre": "Dissertation Bac SES 2024 • Croissance & Société",
      "duree": "4h00",
      "coeff": "16",
      "niveau": "Examen Officiel",
      "themes": "Sources de la croissance économique, Commerce international, Mobilité sociale",
      "correction": "Plan détaillé en 2 parties et 4 sous-parties avec exploitation statistique des documents.",
    },
    {
      "matiere": "Français",
      "titre": "Épreuve Anticipée de Français • Commentaire & Dissertation",
      "duree": "4h00",
      "coeff": "10",
      "niveau": "Épreuve Anticipée",
      "themes": "Le théâtre du XVIIe au XXIe siècle, La poésie du XIXe au XXIe siècle, Baudelaire",
      "correction": "Axes de lecture rédigés, analyse stylistique approfondie des figures de style.",
    },
    {
      "matiere": "Philosophie",
      "titre": "Baccalauréat Général 2024 • Sujet de Philosophie",
      "duree": "4h00",
      "coeff": "8",
      "niveau": "Examen Officiel",
      "themes": "La liberté et l'État, La vérité scientifique, Commentaire d'un texte de Spinoza",
      "correction": "Problématisation, enjeux conceptuels et progression dialectique rigoureuse.",
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserCourses();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserCourses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        setState(() {
          _userCourses = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
        return;
      }
    } catch (_) {}

    // Cours initiaux par défaut
    setState(() {
      _userCourses = [
        {
          "id": "c1",
          "matiere": "Mathématiques",
          "chapitre": "Dérivation, convexité & optimisation",
          "progression": 75,
          "statut": "En bonne voie",
          "date": "2026-11-01",
        },
        {
          "id": "c2",
          "matiere": "Mathématiques",
          "chapitre": "Géométrie vectorielle dans l'espace",
          "progression": 50,
          "statut": "À consolider",
          "date": "2026-11-03",
        },
        {
          "id": "c3",
          "matiere": "Physique-Chimie",
          "chapitre": "Cinématique & Lois du mouvement de Newton",
          "progression": 60,
          "statut": "À consolider",
          "date": "2026-11-04",
        },
        {
          "id": "c4",
          "matiere": "Français",
          "chapitre": "Méthodologie du commentaire composé",
          "progression": 85,
          "statut": "Maîtrisé",
          "date": "2026-11-02",
        },
      ];
    });
    _saveUserCourses();
  }

  Future<void> _saveUserCourses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_userCourses));
    } catch (_) {}
  }

  void _addNewCourse({required String matiere, required String chapitre, required int progressionInitiale}) {
    final newCourse = {
      "id": "c_${DateTime.now().millisecondsSinceEpoch}",
      "matiere": matiere,
      "chapitre": chapitre,
      "progression": progressionInitiale,
      "statut": progressionInitiale >= 75 ? "Maîtrisé" : (progressionInitiale >= 45 ? "En bonne voie" : "À renforcer"),
      "date": DateTime.now().toIso8601String().split('T').first,
    };

    setState(() {
      _userCourses.insert(0, newCourse);
    });
    _saveUserCourses();
  }

  void _updateProgress(String id, int delta) {
    setState(() {
      for (final c in _userCourses) {
        if (c["id"] == id) {
          final cur = (c["progression"] as num).toInt();
          final next = (cur + delta).clamp(0, 100);
          c["progression"] = next;
          c["statut"] = next >= 80 ? "Maîtrisé" : (next >= 50 ? "En bonne voie" : "À renforcer");
          break;
        }
      }
    });
    _saveUserCourses();
  }

  void _deleteCourse(String id) {
    setState(() {
      _userCourses.removeWhere((c) => c["id"] == id);
    });
    _saveUserCourses();
  }

  double get _moyenneProgression {
    if (_userCourses.isEmpty) return 0.0;
    final sum = _userCourses.fold<num>(0, (prev, c) => prev + ((c["progression"] as num?) ?? 0));
    return sum / _userCourses.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Cours & Banque d'Épreuves",
          style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary),
            tooltip: "Ajouter un cours / chapitre",
            onPressed: _showAddCourseDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: "Mes Cours en cours"),
            Tab(text: "Banque d'Épreuves"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCoursesTab(),
          _buildEpreuvesTab(),
        ],
      ),
    );
  }

  Widget _buildCoursesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Synthèse globale
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Évolution & Maîtrise des notions",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textMain),
                    ),
                    Text(
                      "${_moyenneProgression.toStringAsFixed(0)}% acquis",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _moyenneProgression / 100,
                    minHeight: 8,
                    backgroundColor: AppTheme.cardBgElevated,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "${_userCourses.length} chapitres suivis • Ajoute un cours ci-dessous si tu as une difficulté ciblée.",
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Bouton d'ajout rapide
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                "Ajouter un cours / chapitre à travailler",
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _showAddCourseDialog,
            ),
          ),
          const SizedBox(height: 16),

          // 3. Liste des cours
          const Text(
            "Chapitres en cours d'acquisition :",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMain),
          ),
          const SizedBox(height: 10),

          if (_userCourses.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text(
                "Aucun cours ajouté pour l'instant.\nClique sur le bouton ci-dessus pour ajouter ton premier chapitre.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            )
          else
            ..._userCourses.map((c) => _buildCourseCard(c)),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> c) {
    final id = c["id"] as String;
    final matiere = c["matiere"]?.toString() ?? "Matière";
    final chapitre = c["chapitre"]?.toString() ?? "Chapitre";
    final prog = (c["progression"] as num?)?.toInt() ?? 50;
    final statut = c["statut"]?.toString() ?? "En cours";

    Color statusColor = AppTheme.primary;
    if (prog >= 75) statusColor = AppTheme.accentEmerald;
    if (prog < 45) statusColor = AppTheme.accentCoral;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  matiere,
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statut,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _deleteCourse(id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            chapitre,
            style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: prog / 100,
                    minHeight: 6,
                    backgroundColor: AppTheme.cardBgElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "$prog%",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text("Ajuster ma maîtrise :", style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(width: 6),
              InkWell(
                onTap: prog > 0 ? () => _updateProgress(id, -10) : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: AppTheme.borderColor), borderRadius: BorderRadius.circular(4)),
                  child: const Text("-10%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: prog < 100 ? () => _updateProgress(id, 10) : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(4)),
                  child: const Text("+10%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEpreuvesTab() {
    final matieresList = ["Toutes", "Mathématiques", "Physique-Chimie", "Informatique / NSI", "SVT", "SES / Économie", "Français", "Philosophie"];

    final filtered = _selectedSubjectFilter == "Toutes"
        ? _banqueEpreuves
        : _banqueEpreuves.where((e) => e["matiere"] == _selectedSubjectFilter).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filtre des matières
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: matieresList.map((m) {
                final isSel = _selectedSubjectFilter == m;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: FilterChip(
                    label: Text(m),
                    selected: isSel,
                    onSelected: (_) => setState(() => _selectedSubjectFilter = m),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                      color: isSel ? Colors.white : AppTheme.textMain,
                    ),
                    backgroundColor: Colors.white,
                    selectedColor: AppTheme.primary,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: isSel ? AppTheme.primary : AppTheme.borderColor),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          Text(
            "Annales & Épreuves officielles (${filtered.length}) :",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMain),
          ),
          const SizedBox(height: 10),

          ...filtered.map((ep) => _buildEpreuveCard(ep)),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildEpreuveCard(Map<String, dynamic> ep) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ep["matiere"] ?? "",
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.cardBgElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "Coeff ${ep['coeff']} • ${ep['duree']}",
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentEmeraldSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ep["niveau"] ?? "",
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.accentEmerald),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ep["titre"] ?? "",
            style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            "Thèmes : ${ep['themes']}",
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text("Consulter l'épreuve & Corrigé pas-à-pas", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.borderColor),
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showEpreuveDetailDialog(ep),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCourseDialog() {
    final matieresPossibles = [
      "Mathématiques",
      "Physique-Chimie",
      "Informatique / NSI",
      "SVT",
      "SES / Économie",
      "Français",
      "Philosophie",
      "Histoire-Géographie",
      "Anglais / LV1",
    ];

    String chosenMatiere = matieresPossibles[0];
    final chapitreController = TextEditingController();
    int initialProg = 40;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Ajouter un cours / chapitre",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Indique la notion où tu as des difficultés pour l'ajouter à ton plan de travail.",
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),

                    // Matière
                    const Text("Matière :", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: chosenMatiere,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: AppTheme.cardBgElevated,
                      ),
                      items: matieresPossibles
                          .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => chosenMatiere = v);
                      },
                    ),
                    const SizedBox(height: 14),

                    // Intitulé du chapitre
                    const Text("Chapitre ou notion à travailler :", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: chapitreController,
                      decoration: InputDecoration(
                        hintText: "Ex : Suites géométriques, Titrage pH-métrique...",
                        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: AppTheme.cardBgElevated,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Niveau initial de maîtrise
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Niveau actuel estimé :", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Text("$initialProg%", style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                    Slider(
                      value: initialProg.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 10,
                      activeColor: AppTheme.primary,
                      onChanged: (v) => setModalState(() => initialProg = v.toInt()),
                    ),
                    const SizedBox(height: 14),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final text = chapitreController.text.trim();
                          if (text.isEmpty) return;
                          _addNewCourse(
                            matiere: chosenMatiere,
                            chapitre: text,
                            progressionInitiale: initialProg,
                          );
                          Navigator.pop(ctx);
                        },
                        child: const Text("Ajouter à mes cours", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

  void _showEpreuveDetailDialog(Map<String, dynamic> ep) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(6)),
                    child: Text(ep["matiere"] ?? "", style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ep["titre"] ?? "",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
              ),
              const SizedBox(height: 4),
              Text("Durée : ${ep['duree']} • Coeff : ${ep['coeff']} • ${ep['niveau']}", style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const Divider(height: 24),
              const Text("Thématiques clés abordées :", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Text(ep["themes"] ?? "", style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              const Text("Conseils & Corrigé pas-à-pas :", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cardBgElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Text(
                  ep["correction"] ?? "",
                  style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.textMain),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18, color: Colors.white),
                  label: const Text("Marquer comme travaillée", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Épreuve ajoutée à ton historique d'entraînement !"), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
