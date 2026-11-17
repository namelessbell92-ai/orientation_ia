import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../utils/pdf_downloader.dart';

class ApiService {
  // Identifiant de session vierge généré au lancement (aucune donnée pré-remplie par défaut)
  static final String _sessionUserId =
      "eleve-session-${DateTime.now().millisecondsSinceEpoch}";

  // URL de production Cloud Render (24h/24 autonome sans PC)
  static const String cloudBackendUrl = "https://orientation-ia-w93q.onrender.com/api";

  // Liste des URLs candidates (Cloud Render en priorité, puis fallback local/Wi-Fi)
  static const List<String> _candidateUrls = [
    cloudBackendUrl,
    "http://127.0.0.1:8000/api",
    "http://10.234.90.134:8000/api",
    "http://localhost:8000/api",
    "http://10.0.2.2:8000/api",
  ];

  static String? _resolvedBaseUrl;

  /// Retourne l'UID Firebase Auth courant s'il existe, sinon l'identifiant de session vierge.
  static String getCurrentUserId([String? overrideUserId]) {
    if (overrideUserId != null && overrideUserId.trim().isNotEmpty) {
      return overrideUserId.trim();
    }
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.trim().isNotEmpty) {
        return uid.trim();
      }
    } catch (_) {}
    return _sessionUserId;
  }

  static Future<String> getBaseUrl() async {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;

    // 1. Si environnement Web local
    final dynamicWebHost = Uri.base.host;
    final dynamicWebPort = Uri.base.hasPort ? Uri.base.port : null;
    if (dynamicWebHost.isNotEmpty &&
        dynamicWebPort != null &&
        (dynamicWebHost == 'localhost' || dynamicWebHost == '127.0.0.1')) {
      final localUrl = "http://$dynamicWebHost:8000/api";
      try {
        final res = await http
            .get(Uri.parse("$localUrl/health"))
            .timeout(const Duration(milliseconds: 600));
        if (res.statusCode == 200) {
          _resolvedBaseUrl = localUrl;
          return localUrl;
        }
      } catch (_) {}
    }

    // 2. Si adb reverse actif en dev local (127.0.0.1:8000 accessible immédiatement)
    try {
      final res = await http
          .get(Uri.parse("http://127.0.0.1:8000/api/health"))
          .timeout(const Duration(milliseconds: 400));
      if (res.statusCode == 200) {
        _resolvedBaseUrl = "http://127.0.0.1:8000/api";
        return _resolvedBaseUrl!;
      }
    } catch (_) {}

    // 3. Par défaut et en priorité absolue sur smartphone 4G/Wi-Fi : Cloud Render 24h/24
    _resolvedBaseUrl = cloudBackendUrl;
    return cloudBackendUrl;
  }

  /// Récupère le référentiel stratégique complet
  static Future<Map<String, dynamic>> getStrategicReferentiel() async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/strategy/referentiel");
    try {
      final response =
          await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        "error":
            "Erreur référentiel (${response.statusCode}) : ${response.body}"
      };
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de charger le référentiel stratégique : $e"};
    }
  }

  /// Enregistre le profil réel saisi par l'élève et ses notes dans la base SQLite
  static Future<Map<String, dynamic>> saveStudentProfileAndGrades({
    required String classeActuelle,
    String? targetDomain,
    List<String> specialties = const [],
    List<String> interests = const [],
    Map<String, double> riasecScores = const {},
    Map<String, double> grades = const {},
  }) async {
    final base = await getBaseUrl();
    final uid = getCurrentUserId();
    final headers = {
      "Content-Type": "application/json",
      "X-User-Id": uid,
    };

    String normalizedGradeLevel = "PREMIERE";
    final lower = classeActuelle.toLowerCase();
    if (lower.contains("3")) {
      normalizedGradeLevel = "TROISIEME";
    } else if (lower.contains("2") || lower.contains("sec")) {
      normalizedGradeLevel = "SECONDE";
    } else if (lower.contains("term")) {
      normalizedGradeLevel = "TERMINALE";
    } else if (lower.contains("prem") || lower.contains("1")) {
      normalizedGradeLevel = "PREMIERE";
    }

    try {
      final profRes = await http
          .post(
            Uri.parse("$base/profile"),
            headers: headers,
            body: jsonEncode({
              "grade_level": normalizedGradeLevel,
              "target_domain": targetDomain,
              "interests": interests,
              "specialties": specialties,
              "riasec_scores": riasecScores,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (profRes.statusCode != 200 && profRes.statusCode != 201) {
        return {
          "error":
              "Erreur lors de l'enregistrement du profil (${profRes.statusCode}) : ${profRes.body}"
        };
      }

      if (grades.isNotEmpty) {
        final gradesList = grades.entries
            .map((e) => {
                  "subject": e.key,
                  "grade": e.value,
                })
            .toList();

        final gradesRes = await http
            .post(
              Uri.parse("$base/profile/grades"),
              headers: headers,
              body: jsonEncode({
                "school_year": "2026-2027",
                "trimester": 1,
                "grades": gradesList,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (gradesRes.statusCode != 200 && gradesRes.statusCode != 201) {
          return {
            "error":
                "Erreur lors de l'enregistrement des notes (${gradesRes.statusCode}) : ${gradesRes.body}"
          };
        }
      }

      return {"success": true};
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible d'enregistrer le profil : $e"};
    }
  }

  /// Calcul d'écart académique aux seuils d'admission
  static Future<Map<String, dynamic>> runGapAnalyzer(
      Map<String, dynamic> profilePayload) async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/diagnostic/gap-analyzer");
    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(profilePayload),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        "error":
            "Erreur d'analyse (${response.statusCode}) : ${response.body}"
      };
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de calculer l'écart aux seuils : $e"};
    }
  }

  /// Double Trajectoire et Simulateur de Spécialités
  static Future<Map<String, dynamic>> getDoubleTrajectory(
      Map<String, dynamic> profilePayload) async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/strategy/double-trajectory");
    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(profilePayload),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        "error":
            "Erreur Double Trajectoire (${response.statusCode}) : ${response.body}"
      };
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de générer la Double Trajectoire : $e"};
    }
  }

  /// Générateur de Planning Hebdomadaire & Entraîneur Adaptatif
  static Future<Map<String, dynamic>> generateWeeklyPlan(
      Map<String, dynamic> profilePayload) async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/execution/weekly-plan");
    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(profilePayload),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        "error": "Erreur Planning (${response.statusCode}) : ${response.body}"
      };
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de générer le planning hebdomadaire : $e"};
    }
  }

  /// Analyse d'orientation autonome de secours via Gemini Cloud (si PC déconnecté)
  static Future<Map<String, dynamic>> _getOrientationAnalysisWithGeminiCloud(
    Map<String, dynamic> payload,
  ) async {
    try {
      final prompt =
          "Tu es l'algorithme officiel d'orientation stratégique Parcoursup. "
          "Analyse le profil de l'élève suivant : ${jsonEncode(payload)}\n"
          "RÉPONDS UNIQUEMENT en format JSON strict valide sans texte superflu avec cette structure :\n"
          "{\n"
          "  \"gap_analysis\": {\"probabilite_admission\": 72, \"probabilite_plan_b\": 90, \"points_vigilance\": [\"Régularité du travail\", \"Épreuves de spécialités\"]},\n"
          "  \"double_trajectoire\": {\n"
          "    \"poles_trajectoire\": {\n"
          "      \"securite\": {\"titre\": \"Voie Sécurité\", \"sous_titre\": \"Socle Garanti\", \"national\": [{\"formation_id\": \"f1\", \"nom\": \"BUT Informatique\", \"etablissement\": \"IUT\", \"ville\": \"Paris\", \"region\": \"Ile-de-France\", \"taux_acces\": 65.0, \"seuil_moyenne_estime\": 12.0, \"probabilite_admission\": 88}], \"regional\": []},\n"
          "      \"cible\": {\"titre\": \"Voie Cible\", \"sous_titre\": \"Ton Niveau Réel\", \"national\": [{\"formation_id\": \"f2\", \"nom\": \"Licence Sciences du Numérique\", \"etablissement\": \"Université\", \"ville\": \"Lyon\", \"region\": \"Auvergne-Rhône-Alpes\", \"taux_acces\": 45.0, \"seuil_moyenne_estime\": 13.5, \"probabilite_admission\": 74}], \"regional\": []},\n"
          "      \"ambition\": {\"titre\": \"Voie Ambition\", \"sous_titre\": \"Défi d'Excellence\", \"national\": [{\"formation_id\": \"f3\", \"nom\": \"CPGE MPSI / MP2I\", \"etablissement\": \"Lycée d'Excellence\", \"ville\": \"Paris\", \"region\": \"Ile-de-France\", \"taux_acces\": 22.0, \"seuil_moyenne_estime\": 15.5, \"probabilite_admission\": 55}], \"regional\": []}\n"
          "    },\n"
          "    \"lycee_analyse\": {\"nom\": \"${payload['lycee_nom'] ?? 'Lycée'}\", \"ville\": \"${payload['lycee_ville'] ?? ''}\", \"region\": \"${payload['lycee_region'] ?? ''}\", \"bonus_selectivite\": 0.8, \"moyenne_brute\": 13.5, \"moyenne_ponderee\": 14.3}\n"
          "  },\n"
          "  \"top_metiers\": [{\"nom\": \"Ingénieur en Intelligence Artificielle\", \"compatibilite\": 92, \"secteur\": \"Numérique / IA\"}],\n"
          "  \"execution_plan\": {\"weekly_plan\": [{\"jour\": \"Lundi\", \"objectif\": \"Automatismes mathématiques\", \"duree_min\": 45}]}\n"
          "}";

      final body = jsonEncode({
        "contents": [
          {
            "parts": [{"text": prompt}]
          }
        ],
        "generationConfig": {
          "temperature": 0.2,
          "responseMimeType": "application/json",
        }
      });

      const models = ["gemini-flash-latest", "gemini-2.5-flash", "gemini-1.5-flash"];
      for (final m in models) {
        try {
          final url = Uri.parse(
              "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent");
          final res = await http.post(
            url,
            headers: {
              "Content-Type": "application/json",
              "X-goog-api-key": _geminiCloudApiKey,
            },
            body: body,
          ).timeout(const Duration(seconds: 25));

          if (res.statusCode == 200) {
            final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
            final candidates = data["candidates"] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final rawJson = candidates[0]["content"]?["parts"]?[0]?["text"]?.toString() ?? "";
              if (rawJson.trim().isNotEmpty) {
                final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
                if (parsed.containsKey("double_trajectoire")) {
                  return parsed;
                }
              }
            }
          }
        } catch (_) {}
      }
      return {"error": "L'analyse d'orientation n'a pas pu être finalisée."};
    } catch (e) {
      return {"error": "Échec de l'analyse d'orientation : $e"};
    }
  }

  /// Lance l'analyse stratégique complète du profil de l'élève
  static Future<Map<String, dynamic>> getOrientationAnalysis({
    int creativite = 0,
    int empathie = 0,
    int communication = 0,
    int organisation = 0,
    int logique = 0,
    String? classeActuelle,
    List<String>? specialitesChoisies,
    String? filiereAmbitionId,
    Map<String, double>? riasecScores,
    List<String>? passionsBrutes,
    String? preferencesSociales,
    String? environnementPrefere,
    List<String>? secteursSouhaits,
    String? roleVise,
    String? styleVie,
    String? mbtiArchetype,
    Map<String, dynamic>? bulletin,
    String? lyceeNom,
    String? lyceeVille,
    String? lyceeRegion,
    double? lyceeBonusSelectivite,
  }) async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/analyze");

    final Map<String, dynamic> payload = {
      "creativite": creativite,
      "empathie": empathie,
      "communication": communication,
      "organisation": organisation,
      "logique": logique,
      "classe_actuelle": ?classeActuelle,
      "specialites_choisies": ?specialitesChoisies,
      "filiere_ambition_id": ?filiereAmbitionId,
      "riasec_scores": ?riasecScores,
      "passions_brutes": ?passionsBrutes,
      "preferences_sociales": ?preferencesSociales,
      "environnement_prefere": ?environnementPrefere,
      "secteurs_souhaits": ?secteursSouhaits,
      "role_vise": ?roleVise,
      "style_vie": ?styleVie,
      "mbti_archetype": ?mbtiArchetype,
      "bulletin": ?bulletin,
      "lycee_nom": ?lyceeNom,
      "lycee_ville": ?lyceeVille,
      "lycee_region": ?lyceeRegion,
      "lycee_bonus_selectivite": ?lyceeBonusSelectivite,
    };

    final body = jsonEncode(payload);

    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          "error":
              "Erreur du serveur (${response.statusCode}) : ${response.body}"
        };
      }
    } catch (e) {
      _resolvedBaseUrl = null;
      // Bascule autonome sur Gemini Cloud si le serveur local est déconnecté
      return await _getOrientationAnalysisWithGeminiCloud(payload);
    }
  }

  /// Envoie une objection ou un argument au mode Débat / Jury d'admission
  static Future<Map<String, dynamic>> sendDebateObjection({
    required String metierNom,
    String? metierCodeRome,
    required String objection,
    List<Map<String, String>>? history,
    Map<String, dynamic>? profile,
  }) async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/debate");
    final body = jsonEncode({
      "metier_nom": metierNom,
      "metier_code_rome": metierCodeRome,
      "objection": objection,
      "history": ?history,
      "profile": ?profile,
    });

    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          "error": "Erreur serveur (${response.statusCode}) : ${response.body}"
        };
      }
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de contacter l'IA de débat : $e"};
    }
  }

  /// Discussion interactive avec le conseiller IA sur un métier ou une filière
  static Future<Map<String, dynamic>> sendMetierChat({
    required String metierNom,
    String? metierCodeRome,
    String? metierDescription,
    List<dynamic>? metierMissions,
    List<dynamic>? metierEtudes,
    Map<String, dynamic>? metierSalaire,
    required String question,
    List<Map<String, String>>? history,
    Map<String, dynamic>? profile,
  }) async {
    final base = await getBaseUrl();
    final url = Uri.parse("$base/chat-metier");
    final body = jsonEncode({
      "metier_nom": metierNom,
      "metier_code_rome": metierCodeRome,
      "metier_description": metierDescription,
      "metier_missions":
          (metierMissions ?? []).map((e) => e.toString()).toList(),
      "metier_etudes": (metierEtudes ?? []).map((e) => e.toString()).toList(),
      "metier_salaire": metierSalaire,
      "question": question,
      "history": ?history,
      "profile": ?profile,
    });

    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          "error": "Erreur serveur (${response.statusCode}) : ${response.body}"
        };
      }
    } catch (e) {
      return {
        "error":
            "L'IA a mis trop de temps à répondre. Réessaie ou pose une question plus directe."
      };
    }
  }

  /// Analyse autonome de bulletin via Google Gemini Cloud Vision (100% sans PC)
  static Future<Map<String, dynamic>> _parseBulletinWithGeminiCloud(
    List<int> fileBytes,
    String filename,
  ) async {
    try {
      final base64Data = base64Encode(fileBytes);
      final fnLower = filename.toLowerCase();
      String mimeType = "image/jpeg";
      if (fnLower.endsWith(".png")) {
        mimeType = "image/png";
      } else if (fnLower.endsWith(".webp")) {
        mimeType = "image/webp";
      } else if (fnLower.endsWith(".pdf")) {
        mimeType = "application/pdf";
      }

      final prompt =
          "Tu es un extracteur expert de bulletin scolaire français (Pronote, ÉcoleDirecte, ENT ou scan). "
          "Analyse attentivement ce document. Extrais toutes les matières et les notes de l'élève (sur 20), "
          "la moyenne générale (si indiquée ou calcule-la), la classe détectée (ex: Seconde, Première Générale, Terminale), "
          "les spécialités s'il s'agit d'une classe de 1ère ou Terminale, ainsi que le nom du lycée et sa ville si visibles. "
          "IMPORTANT : Réponds UNIQUEMENT avec un objet JSON strict valide sans texte d'accompagnement, suivant ce format :\n"
          "{\n"
          "  \"success\": true,\n"
          "  \"is_detected\": true,\n"
          "  \"moyenne_generale\": 14.2,\n"
          "  \"matieres\": {\"Mathématiques\": 15.0, \"Physique-Chimie\": 13.5, \"Français\": 12.0},\n"
          "  \"points_forts\": [\"Mathématiques\"],\n"
          "  \"dominante\": \"Profil Scientifique & Technique\",\n"
          "  \"classe_detectee\": \"Première\",\n"
          "  \"specialites_detectees\": [\"Mathématiques\", \"Physique-Chimie\"],\n"
          "  \"lycee_detecte\": {\"nom\": \"Nom du lycée\", \"ville\": \"Ville\"}\n"
          "}";

      final body = jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt},
              {
                "inlineData": {
                  "mimeType": mimeType,
                  "data": base64Data,
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.1,
          "responseMimeType": "application/json",
        }
      });

      const models = ["gemini-flash-latest", "gemini-2.5-flash", "gemini-1.5-flash"];
      for (final m in models) {
        try {
          final url = Uri.parse(
              "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent");
          final res = await http.post(
            url,
            headers: {
              "Content-Type": "application/json",
              "X-goog-api-key": _geminiCloudApiKey,
            },
            body: body,
          ).timeout(const Duration(seconds: 25));

          if (res.statusCode == 200) {
            final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
            final candidates = data["candidates"] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final rawJson = candidates[0]["content"]?["parts"]?[0]?["text"]?.toString() ?? "";
              if (rawJson.trim().isNotEmpty) {
                final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
                if (parsed.containsKey("matieres")) {
                  parsed["success"] = true;
                  parsed["is_detected"] = true;
                  return parsed;
                }
              }
            }
          }
        } catch (_) {}
      }
      return {"error": "L'IA n'a pas pu extraire de notes exploitables. Vérifie la lisibilité du document."};
    } catch (e) {
      return {"error": "Échec de l'analyse automatique du bulletin : $e"};
    }
  }

  /// Téléverse un bulletin (PDF ou image) pour extraire les notes et matières
  static Future<Map<String, dynamic>> uploadAndParseBulletin({
    required List<int> fileBytes,
    required String filename,
  }) async {
    try {
      final base = await getBaseUrl();
      final url = Uri.parse("$base/bulletin/parse");
      final request = http.MultipartRequest("POST", url);
      request.files.add(
        http.MultipartFile.fromBytes(
          "file",
          fileBytes,
          filename: filename,
        ),
      );

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
      return await _parseBulletinWithGeminiCloud(fileBytes, filename);
    } catch (e) {
      _resolvedBaseUrl = null;
      // Bascule autonome sur Gemini Cloud Vision si le serveur local est injoignable
      return await _parseBulletinWithGeminiCloud(fileBytes, filename);
    }
  }

  /// Exécute `POST /api/diagnostic/run` avec l'en-tête `X-User-Id`.
  /// Ne crée AUCUN profil fictif par défaut : si l'élève n'a pas encore saisi
  /// sa classe et ses notes, retourne `{"not_configured": true}`.
  static Future<Map<String, dynamic>> runStudentDiagnostic({
    String? userId,
    String? targetDomain,
  }) async {
    final base = await getBaseUrl();
    final uid = getCurrentUserId(userId);
    final url = Uri.parse("$base/diagnostic/run");
    final headers = {
      "Content-Type": "application/json",
      "X-User-Id": uid,
    };
    final body = jsonEncode({
      if (targetDomain != null && targetDomain.trim().isNotEmpty)
        "target_domain": targetDomain.trim(),
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 404) {
        return {
          "not_configured": true,
          "message":
              "Aucune donnée scolaire saisie. Renseignez d'abord votre classe et vos notes pour lancer le diagnostic."
        };
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        "error":
            "Erreur Diagnostic (${response.statusCode}) : ${response.body}"
      };
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de joindre le serveur de diagnostic : $e"};
    }
  }

  /// Télécharge et ouvre la Fiche Stratégique PDF 1 page A4 via `GET /api/diagnostic/export-pdf`.
  static Future<Map<String, dynamic>> exportDiagnosticPdf({
    String? userId,
    String? targetDomain,
  }) async {
    final base = await getBaseUrl();
    final uid = getCurrentUserId(userId);
    final queryParams = <String, String>{
      "user_id": uid,
      if (targetDomain != null && targetDomain.trim().isNotEmpty)
        "target_domain": targetDomain.trim(),
    };
    final uri = Uri.parse("$base/diagnostic/export-pdf")
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {"X-User-Id": uid},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final savedLocation = await downloadOrOpenPdf(
          pdfBytes: response.bodyBytes,
          pdfDirectUrl: uri.toString(),
          filename: "fiche_orientation.pdf",
        );
        return {
          "success": true,
          "size_kb": (response.bodyBytes.length / 1024).toStringAsFixed(1),
          "location": savedLocation,
        };
      }
      return {
        "error":
            "Veuillez d'abord renseigner votre classe et vos notes avant de générer la fiche PDF."
      };
    } catch (e) {
      _resolvedBaseUrl = null;
      return {"error": "Impossible de télécharger le PDF : $e"};
    }
  }

  static final String _geminiCloudApiKey = utf8.decode(
      base64Decode("QVEuQWI4Uk42TDlJSzROYXc3dzgwVW5TZEdPUnlDV3Bic0RzQ0NSVWd4MG9WSUZwM1ZZTmc="));

  /// Réponses expertes directes et immédiates pour Nova (secours autonome 100% hors-ligne)
  static String _buildNovaLocalFallback(
    String message,
    Map<String, dynamic>? studentProfile,
  ) {
    final msgLow = message.toLowerCase();
    final prof = studentProfile ?? {};
    final classe = prof["classe_actuelle"] ?? "au lycée";

    if (msgLow.contains("bonjour") ||
        msgLow.contains("salut") ||
        msgLow.contains("hello") ||
        msgLow.contains("coucou") ||
        msgLow.contains("bonsoir") ||
        msgLow.contains("hey")) {
      return "Bonjour ! Je suis Nova, ton mentor dédié à l'orientation et à la réussite scolaire.\n\nComment puis-je t'aider aujourd'hui ? Pose-moi une question sur le choix de tes spécialités, les filières post-bac (prépas, BUT, universités, écoles), ou la stratégie de ton dossier Parcoursup.";
    } else if (msgLow.contains("qui es-tu") ||
        msgLow.contains("tu es qui") ||
        msgLow.contains("c'est quoi nova") ||
        msgLow.contains("présente-toi") ||
        msgLow.contains("presente-toi")) {
      return "Je suis Nova, ton coach d'orientation stratégique. Mon rôle est de décrypter ton dossier, d'étalonner tes résultats avec le niveau réel de ton lycée (via les indicateurs officiels IVAL) et de t'aider à construire une trajectoire ambitieuse et sécurisée pour le post-bac.";
    } else if (msgLow.contains("math") ||
        msgLow.contains("calcul") ||
        msgLow.contains("note") ||
        msgLow.contains("progresser") ||
        msgLow.contains("remédiation") ||
        msgLow.contains("remediation")) {
      return "Pour faire grimper ta moyenne en maths, la clé n'est pas de refaire 50 fois les mêmes exercices faciles, mais de cibler les automatismes de calcul et les démonstrations de cours.\n\nConsacre 3 sessions de 35 minutes par semaine exclusivement aux exercices types du bac ou de concours. Rédige chaque étape au propre comme si tu étais le jour de l'épreuve.";
    } else if (msgLow.contains("parcoursup") ||
        msgLow.contains("dossier") ||
        msgLow.contains("commission") ||
        msgLow.contains("selection") ||
        msgLow.contains("sélecti")) {
      return "Pour les commissions Parcoursup, deux éléments pèsent lourdement en dehors des notes : la progression entre le 1er et le 2e trimestre, et l'adéquation de tes spécialités avec la filière visée.\n\nSi ton lycée applique une notation exigeante, n'hésite pas à le faire valoir via la fiche Avenir et ta lettre de motivation.";
    } else if (msgLow.contains("prépa") ||
        msgLow.contains("prepa") ||
        msgLow.contains("mpsi") ||
        msgLow.contains("pcsi") ||
        msgLow.contains("ecg") ||
        msgLow.contains("bcpst") ||
        msgLow.contains("concours")) {
      return "Viser une classe préparatoire est une excellente ambition qui structure ta méthode pour toute ta carrière. Les prépas recherchent avant tout de la régularité et une capacité à surmonter les moments de doute.\n\nAssure-toi de consolider tes bases dès maintenant et prévois toujours un plan B sécurisé (BUT ou licence sélective).";
    } else if (msgLow.contains("lycee") ||
        msgLow.contains("lycée") ||
        msgLow.contains("ival") ||
        msgLow.contains("etablissement")) {
      return "Le lycée d'origine est en effet scruté par les meilleures formations : un 14 dans un établissement réputé pour sa sévérité vaut souvent un 16 ou 17 dans un lycée moyen.\n\nC'est précisément pour cela que l'application étalonne ton dossier via les indicateurs officiels IVAL.";
    } else if (msgLow.contains("medecine") ||
        msgLow.contains("médecine") ||
        msgLow.contains("pass") ||
        msgLow.contains("las") ||
        msgLow.contains("santé") ||
        msgLow.contains("sante")) {
      return "L'accès aux études de santé (PASS ou LAS) exige une immense capacité de travail en autonomie et une mémorisation rapide. En Première et Terminale, privilégie les spécialités scientifiques (SVT, Physique-Chimie, Maths).\n\nEn PASS, le rythme est très soutenu dès la première semaine : travailler la régularité dès maintenant est ton meilleur atout.";
    } else if (msgLow.contains("ingénieur") ||
        msgLow.contains("ingenieur") ||
        msgLow.contains("école") ||
        msgLow.contains("ecole")) {
      return "Pour intégrer une école d'ingénieurs, plusieurs voies s'offrent à toi : les prépas classiques (CPGE), les écoles post-bac avec prépa intégrée (INSA, UT, Polytech via Geipi), ou les admissions parallèles après un BUT.\n\nLe choix dépend de ton profil : si tu as besoin de concret, le BUT ou la prépa intégrée sont d'excellentes options.";
    } else {
      return "Je prends bien en compte ta question par rapport à ta situation $classe.\n\nPour construire une trajectoire solide, concentre-toi d'abord sur la régularité de tes notes et l'alignement de tes spécialités avec tes objectifs. Quelle est la filière ou le métier qui t'attire le plus en ce moment ?";
    }
  }

  /// Appel direct à Google Gemini Cloud depuis le smartphone (100% autonome sans PC)
  static Future<String> _askGeminiDirect({
    required String message,
    List<Map<String, String>> history = const [],
    Map<String, dynamic>? studentProfile,
  }) async {
    const models = ["gemini-flash-latest", "gemini-2.5-flash", "gemini-1.5-flash"];
    final sysPrompt =
        "Tu es Nova, le mentor d'orientation officiel pour lycéens. "
        "Tu es bienveillant, direct, stratégique et expert des filières post-bac "
        "(Parcoursup, CPGE, BUT, Licences, PASS/LAS Médecine, Écoles d'ingénieurs et de commerce). "
        "IMPORTANT : Reste concis et percutant. Rédige ta réponse en 2 courts paragraphes maximum (environ 100 à 130 mots). Donne des étapes concrètes sans bavardage superflu.";

    final contents = <Map<String, dynamic>>[];
    for (final h in history) {
      final role = (h["role"] == "assistant" || h["role"] == "model")
          ? "model"
          : "user";
      final txt = h["content"] ?? "";
      if (txt.trim().isNotEmpty) {
        contents.add({
          "role": role,
          "parts": [
            {"text": txt}
          ]
        });
      }
    }
    contents.add({
      "role": "user",
      "parts": [
        {"text": message}
      ]
    });

    final body = jsonEncode({
      "systemInstruction": {
        "parts": [
          {"text": sysPrompt}
        ]
      },
      "contents": contents,
      "generationConfig": {
        "temperature": 0.7,
        "maxOutputTokens": 800,
      }
    });

    for (final m in models) {
      try {
        final url = Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent");
        final res = await http
            .post(
              url,
              headers: {
                "Content-Type": "application/json",
                "X-goog-api-key": _geminiCloudApiKey,
              },
              body: body,
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final data =
              jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final candidates = data["candidates"] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]["content"]?["parts"] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts
                  .map((p) => p["text"]?.toString() ?? "")
                  .join("\n")
                  .trim();
              if (text.isNotEmpty) return text;
            }
          }
        }
      } catch (_) {}
    }
    return _buildNovaLocalFallback(message, studentProfile);
  }

  /// Envoie un message au mentor IA Nova avec historique et contexte de l'élève
  static Future<String> askNova({
    required String message,
    List<Map<String, String>> history = const [],
    Map<String, dynamic>? studentProfile,
  }) async {
    try {
      final base = await getBaseUrl();
      final uri = Uri.parse("$base/nova/chat");
      final body = jsonEncode({
        "message": message,
        "conversation_history": history,
        "student_profile": studentProfile,
      });
      // Délai adapté au réveil à froid de Render (cold-start 20-30s sans échec)
      final res = await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 40));

      if (res.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final reply = data["reply"]?.toString();
        if (reply != null && reply.trim().isNotEmpty) {
          return reply.trim();
        }
      }
      return await _askGeminiDirect(
        message: message,
        history: history,
        studentProfile: studentProfile,
      );
    } catch (_) {
      // En cas de coupure réseau ou instance en cours d'initialisation : réponse experte immédiate
      return await _askGeminiDirect(
        message: message,
        history: history,
        studentProfile: studentProfile,
      );
    }
  }

  /// Recherche un lycée français par nom, commune, code postal ou département dans la table officielle des 4 783 lycées (Open Data)
  static Future<List<Map<String, dynamic>>> searchLycees(
    String query, {
    String? region,
    String? departement,
    int limit = 25,
  }) async {
    final cleanQ = query.trim();
    try {
      final base = await getBaseUrl();
      final qParams = <String, String>{
        "limit": limit.toString(),
      };
      if (cleanQ.isNotEmpty) {
        qParams["q"] = cleanQ;
      }
      if (region != null && region.isNotEmpty && region != "Toutes les régions") {
        qParams["region"] = region;
      }
      if (departement != null && departement.isNotEmpty && departement != "Tous les départements") {
        qParams["departement"] = departement;
      }
      final uri = Uri.parse("$base/lycees/search").replace(queryParameters: qParams);
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final list = (data["results"] as List?) ?? [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      print("Erreur searchLycees: $e");
      return [];
    }
  }

  /// Récupère la hiérarchie officielle : Régions -> Départements pour les filtres
  static Future<Map<String, dynamic>> getLyceesHierarchy() async {
    try {
      final base = await getBaseUrl();
      final uri = Uri.parse("$base/lycees/hierarchy");
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      print("Erreur getLyceesHierarchy: $e");
      return {};
    }
  }
}