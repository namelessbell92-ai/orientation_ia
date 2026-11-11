import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DiagnosticScreen extends StatefulWidget {
  final String? initialDomain;

  const DiagnosticScreen({super.key, this.initialDomain});

  @override
  DiagnosticScreenState createState() => DiagnosticScreenState();
}

class DiagnosticScreenState extends State<DiagnosticScreen> {
  void reload() => _runDiagnostic();
  bool _isLoading = true;
  bool _isDownloadingPdf = false;
  bool _isNotConfigured = false;
  String? _errorMessage;
  Map<String, dynamic>? _diagnosticData;
  String? _selectedDomain;

  static const List<String> _availableDomains = [
    "Ingénierie",
    "Santé & Médecine",
    "Commerce & Finance",
    "Droit & Sciences Po",
    "Architecture & Design",
  ];

  // Palette institutionnelle sobre
  static const Color _navyDark = Color(0xFF0F172A);
  static const Color _indigoAccent = Color(0xFF1E3A8A);
  static const Color _emeraldDark = Color(0xFF065F46);
  static const Color _emeraldAccent = Color(0xFF047857);
  static const Color _slateText = Color(0xFF334155);
  static const Color _slateMuted = Color(0xFF64748B);
  static const Color _borderLight = Color(0xFFE2E8F0);
  static const Color _bgPage = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    if (widget.initialDomain != null &&
        widget.initialDomain!.trim().isNotEmpty) {
      _selectedDomain = widget.initialDomain!.trim();
    }
    _runDiagnostic();
  }

  Future<void> _runDiagnostic({String? domainOverride}) async {
    final domain = domainOverride ?? _selectedDomain;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isNotConfigured = false;
      _selectedDomain = domain;
    });

    final result = await ApiService.runStudentDiagnostic(
      targetDomain: domain,
    );

    if (!mounted) return;

    if (result["not_configured"] == true) {
      setState(() {
        _isLoading = false;
        _isNotConfigured = true;
        _errorMessage = null;
        _diagnosticData = null;
      });
      return;
    }

    if (result.containsKey("error")) {
      setState(() {
        _isLoading = false;
        _errorMessage = result["error"].toString();
      });
      return;
    }

    setState(() {
      _diagnosticData = result;
      _isLoading = false;
      _isNotConfigured = false;
      _errorMessage = null;
    });
  }

  Future<void> _handleExportPdf() async {
    if (_isDownloadingPdf || _isNotConfigured || _diagnosticData == null) return;
    setState(() {
      _isDownloadingPdf = true;
    });

    final res = await ApiService.exportDiagnosticPdf(
      targetDomain: _selectedDomain,
    );

    if (!mounted) return;
    setState(() {
      _isDownloadingPdf = false;
    });

    if (res.containsKey("error")) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB91C1C),
          content: Text(res["error"].toString()),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _emeraldAccent,
        behavior: SnackBarBehavior.floating,
        content: Text(
          "Fiche PDF générée : ${res['size_kb']} Ko",
        ),
      ),
    );
  }

  String _fmtNum(dynamic value, {int decimals = 2, bool signed = false}) {
    if (value == null) return ":";
    final numVal = (value is num)
        ? value.toDouble()
        : double.tryParse(value.toString());
    if (numVal == null) return ":";
    final formatted = numVal.toStringAsFixed(decimals).replaceAll('.', ',');
    if (signed && numVal > 0) {
      return "+$formatted";
    }
    return formatted;
  }

  double? _computeDominantAverage(
      Map<String, dynamic> resume, Map<String, dynamic> ambition) {
    final gaps = (ambition["subject_gaps"] as List<dynamic>?) ?? [];
    if (gaps.isEmpty) {
      return (resume["general_average"] as num?)?.toDouble();
    }
    double sum = 0.0;
    int count = 0;
    for (final g in gaps.take(2)) {
      if (g is Map && g["student_grade"] is num) {
        sum += (g["student_grade"] as num).toDouble();
        count++;
      }
    }
    if (count == 0) {
      return (resume["general_average"] as num?)?.toDouble();
    }
    return sum / count;
  }

  String _buildProfileTag(Map<String, dynamic> resume) {
    final domain = (resume["target_domain"] ?? _selectedDomain ?? "").toString();
    if (domain.isEmpty) {
      return "Profil en cours d'analyse";
    }
    final lower = domain.toLowerCase();
    if (lower.contains("ing") || lower.contains("science")) {
      return "Profil à potentiel scientifique & technologique";
    }
    if (lower.contains("sant") || lower.contains("med")) {
      return "Profil à potentiel scientifique & bio-médical";
    }
    if (lower.contains("comm") || lower.contains("fin")) {
      return "Profil à potentiel économique & managérial";
    }
    if (lower.contains("droit") || lower.contains("po")) {
      return "Profil à potentiel juridique & sciences humaines";
    }
    return "Profil à potentiel créatif & architectural";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPage,
      appBar: AppBar(
        backgroundColor: _navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.query_stats_rounded, color: Color(0xFF60A5FA), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Bilan Stratégique & Double Trajectoire",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isLoading ? null : () => _runDiagnostic(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                "Recalculer",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildPersistentPdfBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderLight),
            boxShadow: [
              BoxShadow(
                color: _navyDark.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  color: _indigoAccent,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "Calcul du diagnostic stratégique en cours...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _navyDark,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Croisement déterministe des seuils Parcoursup, "
                "extraction des attendus ONISEP et génération des priorités hebdomadaires.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _slateMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

        if (_isNotConfigured || (_diagnosticData == null && !_isLoading && _errorMessage == null)) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderLight),
            boxShadow: [
              BoxShadow(
                color: _navyDark.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: _indigoAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Diagnostic en attente de calcul",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _navyDark,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Pour calculer ton écart aux seuils sélectifs Parcoursup et ta double trajectoire (Ambition vs Sécurité), charge ou saisis tes notes dans « Profil & Notes ».",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: _slateMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => _runDiagnostic(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _indigoAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("Calculer mon diagnostic"),
              ),
            ],
          ),
        ),
      );
    }

    final data = _diagnosticData ?? {};
    final resume = (data["profil_resume"] as Map<String, dynamic>?) ??
        (data["resume_eleve"] as Map<String, dynamic>?) ??
        {};
    final ambition = (data["voie_a_ambition"] as Map<String, dynamic>?) ??
        (data["parcours_ambition"] as Map<String, dynamic>?) ??
        {};
    final realiste = (data["voie_b_realiste"] as Map<String, dynamic>?) ??
        (data["parcours_realiste"] as Map<String, dynamic>?) ??
        {};
    final synthese =
        (data["synthese_strategique"] as Map<String, dynamic>?) ?? {};
    final actions = (synthese["actions_prioritaires"] as List<dynamic>?) ??
        (data["actions_prioritaires"] as List<dynamic>?) ??
        [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 32 : 16,
            vertical: 20,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDomainSelectorBar(),
                  const SizedBox(height: 16),
                  _buildHeaderBilanCard(resume, ambition),
                  const SizedBox(height: 22),
                  _buildSectionTitle(
                    icon: Icons.alt_route_rounded,
                    title: "Le Double Parcours : Voie A Ambition & Voie B Sécurité",
                    subtitle:
                        "Sélection SQL déterministe sur les données officielles Parcoursup",
                  ),
                  const SizedBox(height: 12),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildAmbitionCard(ambition)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildRealisteCard(realiste)),
                      ],
                    )
                  else ...[
                    _buildAmbitionCard(ambition),
                    const SizedBox(height: 14),
                    _buildRealisteCard(realiste),
                  ],
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                    icon: Icons.checklist_rtl_rounded,
                    title: "Plan d'Action Hebdomadaire",
                    subtitle:
                        "Protocole concret pour combler l'écart sur les matières critiques",
                  ),
                  const SizedBox(height: 12),
                  _buildPriorityActionsList(actions),
                  if ((synthese["discours_coach_llm"] ?? "")
                      .toString()
                      .isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildCoachSynthesisBanner(synthese),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDomainSelectorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderLight),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compass_calibration_rounded,
                  size: 17, color: _indigoAccent),
              SizedBox(width: 6),
              Text(
                "Cap visé :",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _navyDark,
                ),
              ),
            ],
          ),
          for (final dom in _availableDomains)
            ChoiceChip(
              label: Text(dom),
              selected: (_selectedDomain ?? "").toLowerCase() == dom.toLowerCase(),
              onSelected: (selected) {
                if (selected && _selectedDomain != dom) {
                  _runDiagnostic(domainOverride: dom);
                }
              },
              selectedColor: _indigoAccent,
              backgroundColor: _bgPage,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: (_selectedDomain ?? "").toLowerCase() == dom.toLowerCase()
                    ? Colors.white
                    : _slateText,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: (_selectedDomain ?? "").toLowerCase() == dom.toLowerCase()
                      ? _indigoAccent
                      : _borderLight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // A. HEADER "BILAN & DIAGNOSTIC"
  // ===========================================================================
  Widget _buildHeaderBilanCard(
      Map<String, dynamic> resume, Map<String, dynamic> ambition) {
    final genAvg = (resume["general_average"] as num?)?.toDouble();
    final domAvg = _computeDominantAverage(resume, ambition);
    final gradeLevel = (resume["grade_level"] ?? "Non renseignée").toString();
    final specialties = (resume["specialties"] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final profileTag = _buildProfileTag(resume);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _navyDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF93C5FD).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_outlined,
                        color: Color(0xFF93C5FD), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      profileTag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Classe : $gradeLevel",
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: [
              _buildHeaderMetricBox(
                label: "MOYENNE GÉNÉRALE",
                value: genAvg != null ? "${_fmtNum(genAvg, decimals: 1)} / 20" : ": / 20",
                sublabel: "Bilan trimestriel consolidé",
                icon: Icons.school_rounded,
              ),
              _buildHeaderMetricBox(
                label: "MOYENNE DES DOMINANTES",
                value: domAvg != null ? "${_fmtNum(domAvg, decimals: 1)} / 20" : ": / 20",
                sublabel: specialties.isNotEmpty
                    ? specialties.join(" • ")
                    : "Matières majeures",
                icon: Icons.functions_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetricBox({
    required String label,
    required String value,
    required String sublabel,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFBFDBFE),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // B. LE DOUBLE PARCOURS
  // ===========================================================================
  Widget _buildSelectivityGroupBadge({
    required int group,
    required String label,
  }) {
    late final Color bgColor;
    late final Color borderColor;
    late final Color textColor;
    late final Color iconColor;
    late final IconData iconData;

    if (group == 1) {
      // Groupe 1 : Badge Or / Violet foncé avec intitulé d'élite
      bgColor = const Color(0xFF3B0764);
      borderColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFFEF3C7);
      iconColor = const Color(0xFFFBBF24);
      iconData = Icons.workspace_premium_outlined;
    } else if (group == 2) {
      // Groupe 2 : Badge Bleu marine
      bgColor = const Color(0xFF1E3A8A);
      borderColor = const Color(0xFF3B82F6);
      textColor = Colors.white;
      iconColor = const Color(0xFF93C5FD);
      iconData = Icons.school_outlined;
    } else {
      // Groupe 3 : Badge Vert émeraude
      bgColor = const Color(0xFF047857);
      borderColor = const Color(0xFF10B981);
      textColor = Colors.white;
      iconColor = const Color(0xFFA7F3D0);
      iconData = Icons.verified_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 15, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceFooter(String? customSource) {
    final detail = (customSource != null && customSource.trim().isNotEmpty)
        ? customSource.trim()
        : "Source : Données certifiées MESR / Classements de référence";
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borderLight, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 13.5, color: _slateMuted),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  "Source : Données certifiées MESR / Classements de référence",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: _slateMuted,
                  ),
                ),
              ),
            ],
          ),
          if (detail != "Source : Données certifiées MESR / Classements de référence") ...[
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 10.5,
                color: _slateMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAmbitionCard(Map<String, dynamic> ambition) {
    final formationName =
        (ambition["formation_name"] ?? "Non définie").toString();
    final ville = (ambition["ville"] ?? ":").toString();
    final formationId = (ambition["formation_id"] ?? "").toString();
    final seuil = _fmtNum(ambition["seuil_moyenne_estime"]);
    final tauxAcces =
        _fmtNum(ambition["taux_acces_pct"], decimals: 0);
    final gapVal = (ambition["estimated_gap"] as num?)?.toDouble() ?? 0.0;
    final gapFormatted = _fmtNum(ambition["estimated_gap"], signed: true);
    final selectivityGroup =
        (ambition["selectivity_group"] as num?)?.toInt() ?? 2;
    final rankingLabel = (ambition["ranking_label"] ??
            (selectivityGroup == 1
                ? "Groupe 1 : Cibles Top Concours (X, ENS, HEC)"
                : "Groupe 2 : Cibles Grandes Écoles Nationales"))
        .toString();
    final sourceCitation = (ambition["source_citation"] ?? "").toString();
    final requirements = (ambition["requirements"] as List<dynamic>?)
            ?.map((e) => e.toString())
            .take(2)
            .toList() ??
        [];

    final isNegativeGap = gapVal < 0;
    final badgeBg =
        isNegativeGap ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    final badgeBorder =
        isNegativeGap ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7);
    final badgeText =
        isNegativeGap ? const Color(0xFFB91C1C) : const Color(0xFF047857);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _indigoAccent.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _navyDark.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _indigoAccent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14.5),
                topRight: Radius.circular(14.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "VOIE A : AMBITION / EXCELLENCE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (formationId.isNotEmpty)
                  Text(
                    "#$formationId",
                    style: const TextStyle(
                      color: Color(0xFFBFDBFE),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSelectivityGroupBadge(
                  group: selectivityGroup,
                  label: rankingLabel,
                ),
                const SizedBox(height: 10),
                Text(
                  formationName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _navyDark,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 15, color: _slateMuted),
                    const SizedBox(width: 4),
                    Text(
                      ville,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _slateMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isNegativeGap
                            ? Icons.trending_up_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                        color: badgeText,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isNegativeGap
                              ? "Écart à combler : $gapFormatted pts"
                              : "Objectif atteint : $gapFormatted pts",
                          style: TextStyle(
                            color: badgeText,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStatTile(
                        label: "Seuil estimé d'admission",
                        value: "$seuil / 20",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMiniStatTile(
                        label: "Taux d'accès Parcoursup",
                        value: "$tauxAcces %",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  "Conditions clés de sélection :",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _navyDark,
                  ),
                ),
                const SizedBox(height: 6),
                for (final req in requirements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(Icons.circle,
                              size: 6, color: _indigoAccent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            req,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _slateText,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildSourceFooter(sourceCitation),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealisteCard(Map<String, dynamic> realiste) {
    final formationName =
        (realiste["formation_name"] ?? "Non définie").toString();
    final ville = (realiste["ville"] ?? ":").toString();
    final formationId = (realiste["formation_id"] ?? "").toString();
    final seuil = _fmtNum(realiste["seuil_moyenne_estime"]);
    final tauxAcces =
        _fmtNum(realiste["taux_acces_pct"], decimals: 0);
    final gapFormatted = _fmtNum(realiste["estimated_gap"], signed: true);
    final selectivityGroup =
        (realiste["selectivity_group"] as num?)?.toInt() ?? 3;
    final rankingLabel = (realiste["ranking_label"] ??
            "Groupe 3 : Accès Régional & Tremplin Sécurisé")
        .toString();
    final sourceCitation = (realiste["source_citation"] ?? "").toString();
    final requirements = (realiste["requirements"] as List<dynamic>?)
            ?.map((e) => e.toString())
            .take(2)
            .toList() ??
        [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: _emeraldAccent.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _navyDark.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _emeraldDark,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14.5),
                topRight: Radius.circular(14.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "VOIE B : SÉCURITÉ / TREMPLIN PLAN B",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (formationId.isNotEmpty)
                  Text(
                    "#$formationId",
                    style: const TextStyle(
                      color: Color(0xFFA7F3D0),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSelectivityGroupBadge(
                  group: selectivityGroup,
                  label: rankingLabel,
                ),
                const SizedBox(height: 10),
                Text(
                  formationName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _navyDark,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 15, color: _slateMuted),
                    const SizedBox(width: 4),
                    Text(
                      ville,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _slateMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF6EE7B7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: _emeraldAccent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Marge de sécurité : $gapFormatted pt",
                          style: const TextStyle(
                            color: _emeraldAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStatTile(
                        label: "Taux d'accès Parcoursup",
                        value: "$tauxAcces %",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMiniStatTile(
                        label: "Seuil de référence",
                        value: "$seuil / 20",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  "Passerelles & poursuite d'études :",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _navyDark,
                  ),
                ),
                const SizedBox(height: 6),
                for (final req in requirements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(Icons.circle,
                              size: 6, color: _emeraldAccent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            req,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _slateText,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildSourceFooter(sourceCitation),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatTile({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bgPage,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: _slateMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _navyDark,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // C. PLAN D'ACTION HEBDOMADAIRE
  // ===========================================================================
  Widget _buildPriorityActionsList(List<dynamic> actions) {
    final icons = [
      Icons.calculate_outlined,
      Icons.science_outlined,
      Icons.folder_special_outlined,
    ];

    return Column(
      children: [
        for (int i = 0; i < actions.length; i++)
          _buildActionItemCard(
            action: (actions[i] as Map<String, dynamic>?) ?? {},
            icon: icons[i % icons.length],
            index: i + 1,
          ),
      ],
    );
  }

  Widget _buildActionItemCard({
    required Map<String, dynamic> action,
    required IconData icon,
    required int index,
  }) {
    final matiere = (action["matiere_ou_axe"] ?? "Matière prioritaire").toString();
    final objectif = (action["objectif_chiffre"] ?? "").toString();
    final protocole = (action["action_concrete_hebdo"] ?? "").toString();
    final duree = (action["duree_hebdo_recommandee"] ?? "").toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Icon(icon, color: _indigoAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "Priorité $index : $matiere",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _navyDark,
                      ),
                    ),
                    if (duree.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _navyDark,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              duree,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  objectif,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _indigoAccent,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  protocole,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _slateText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachSynthesisBanner(Map<String, dynamic> synthese) {
    final discours = (synthese["discours_coach_llm"] ?? "").toString();
    final mythe = (synthese["analyse_exigences_terrain"] ?? synthese["deconstruction_mythe"] ?? "").toString();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.fact_check_outlined, color: _navyDark, size: 20),
          title: const Text(
            "Voir l'analyse détaillée du coach",
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: _navyDark,
            ),
          ),
          children: [
            Text(
              discours,
              style: const TextStyle(
                fontSize: 12.5,
                color: _slateText,
                height: 1.4,
              ),
            ),
            if (mythe.isNotEmpty) ...[
              const Divider(height: 16, color: Color(0xFFCBD5E1)),
              Text(
                mythe,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: _slateMuted,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: _indigoAccent, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: _navyDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _slateMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // D. BOUTON D'EXPORT PDF
  // ===========================================================================
  Widget _buildPersistentPdfBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _borderLight)),
        boxShadow: [
          BoxShadow(
            color: _navyDark.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_isLoading || _isDownloadingPdf || _isNotConfigured || _diagnosticData == null)
                    ? null
                    : _handleExportPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navyDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _slateMuted.withValues(alpha: 0.4),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isDownloadingPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: Text(
                  _isDownloadingPdf
                      ? "Génération de la fiche PDF A4 en cours..."
                      : "Télécharger la fiche d'entretien (PDF)",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
