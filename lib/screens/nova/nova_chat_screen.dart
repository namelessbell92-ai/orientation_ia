import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/api_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';

class NovaChatScreen extends StatefulWidget {
  final String? initialPrompt;

  const NovaChatScreen({super.key, this.initialPrompt});

  @override
  State<NovaChatScreen> createState() => _NovaChatScreenState();
}

class _NovaChatScreenState extends State<NovaChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _conversations = [];
  String _currentConversationId = "";
  List<Map<String, dynamic>> _currentMessages = [];

  // Suivi indépendant des générations par conversation
  final Set<String> _generatingConversationIds = {};
  Map<String, dynamic>? _studentProfile;

  // Gestion vocale (Speech-to-Text) et Synthèse (TTS)
  final FlutterTts _flutterTts = FlutterTts();
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String? _currentlySpokenText;

  // Gestion des pièces jointes (fichiers/bulletins)
  String? _attachedFileName;
  List<int>? _attachedFileBytes;

  static const String _storageKey = "nova_chat_conversations_v2";

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
    _initTts();
    _loadConversations();
    _loadStudentContext();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    if (_isListening) {
      _speech.stop();
    }
    super.dispose();
  }

  void _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
  }

  void _initTts() {
    _flutterTts.setLanguage("fr-FR");
    _flutterTts.setSpeechRate(0.52);
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentlySpokenText = null;
        });
      }
    });
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking && _currentlySpokenText == text) {
      await _flutterTts.stop();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentlySpokenText = null;
        });
      }
      return;
    }
    await _flutterTts.stop();
    if (mounted) {
      setState(() {
        _isSpeaking = true;
        _currentlySpokenText = text;
      });
    }
    await _flutterTts.speak(text);
  }

  Future<void> _loadStudentContext() async {
    try {
      final prog = await ProgressService.loadProgress();
      if (mounted) {
        setState(() {
          _studentProfile = {
            "bulletin": prog.gapAnalysisResult?["bulletin"],
            "filiere_cible": prog.gapAnalysisResult?["filiere_cible"],
            "probabilite_admission": prog.gapAnalysisResult?["probabilite_admission"],
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _loadConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        _conversations = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      _startNewConversation(autoTitle: true);
      _sendMessage(widget.initialPrompt!.trim());
    } else if (_conversations.isEmpty) {
      _startNewConversation(autoTitle: false);
    } else {
      _selectConversation(_conversations.first["id"] as String);
    }
  }

  Future<void> _saveConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_conversations);
      await prefs.setString(_storageKey, raw);
    } catch (_) {}
  }

  void _startNewConversation({bool autoTitle = true}) {
    final newId = "conv_${DateTime.now().millisecondsSinceEpoch}";
    final newConv = {
      "id": newId,
      "title": "Nouvelle discussion",
      "date": DateTime.now().toIso8601String(),
      "messages": <Map<String, dynamic>>[],
    };

    setState(() {
      _conversations.insert(0, newConv);
      _currentConversationId = newId;
      _currentMessages = [];
      _attachedFileName = null;
      _attachedFileBytes = null;
    });
    _saveConversations();
  }

  void _selectConversation(String id) {
    final found = _conversations.firstWhere(
      (c) => c["id"] == id,
      orElse: () => _conversations.isNotEmpty ? _conversations.first : {
        "id": "conv_${DateTime.now().millisecondsSinceEpoch}",
        "title": "Nouvelle discussion",
        "date": DateTime.now().toIso8601String(),
        "messages": <Map<String, dynamic>>[],
      },
    );
    setState(() {
      _currentConversationId = found["id"] as String;
      final rawMsgs = (found["messages"] as List?) ?? [];
      _currentMessages = rawMsgs.map((m) => Map<String, dynamic>.from(m as Map)).toList();
      _attachedFileName = null;
      _attachedFileBytes = null;
    });
    _scrollToBottom();
  }

  void _deleteConversation(String id) {
    setState(() {
      _conversations.removeWhere((c) => c["id"] == id);
      _generatingConversationIds.remove(id);
      if (_conversations.isEmpty) {
        _startNewConversation(autoTitle: false);
      } else if (_currentConversationId == id) {
        _selectConversation(_conversations.first["id"] as String);
      }
    });
    _saveConversations();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFile() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (pickedFiles.isNotEmpty) {
        final f = pickedFiles.first;
        final bytes = await f.readAsBytes();
        setState(() {
          _attachedFileName = f.name;
          _attachedFileBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sélection de fichier : $e")),
        );
      }
    }
  }

  void _toggleSpeech() async {
    if (!_isListening) {
      bool available = _speechAvailable;
      if (!available) {
        available = await _speech.initialize(
          onStatus: (val) {
            if (val == 'done' || val == 'notListening') {
              if (mounted) setState(() => _isListening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _isListening = false);
          },
        );
        _speechAvailable = available;
      }
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: 'fr_FR',
          onResult: (val) {
            setState(() {
              _textController.text = val.recognizedWords;
            });
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Reconnaissance vocale non disponible sur cet appareil.")),
          );
        }
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _sendMessage([String? prefilledText]) async {
    final text = (prefilledText ?? _textController.text).trim();
    if (text.isEmpty && _attachedFileBytes == null) return;

    final targetConvId = _currentConversationId;
    if (_generatingConversationIds.contains(targetConvId)) return;

    final currentFileName = _attachedFileName;
    final currentFileBytes = _attachedFileBytes;

    if (prefilledText == null) {
      _textController.clear();
      setState(() {
        _attachedFileName = null;
        _attachedFileBytes = null;
      });
    }

    final userMsg = {
      "role": "user",
      "content": text.isNotEmpty ? text : "Analyse du document : $currentFileName",
      if (currentFileName != null) "attachment": currentFileName,
    };

    Map<String, dynamic>? targetConv;
    for (final c in _conversations) {
      if (c["id"] == targetConvId) {
        targetConv = c;
        break;
      }
    }
    if (targetConv == null) return;

    final targetMsgList = (targetConv["messages"] as List);

    if (targetMsgList.isEmpty || targetConv["title"] == "Nouvelle discussion") {
      final t = text.isNotEmpty ? text : "Document $currentFileName";
      targetConv["title"] = t.length > 32 ? "${t.substring(0, 29)}..." : t;
    }
    targetMsgList.add(userMsg);

    final historySnapshot = targetMsgList
        .map((m) => {
              "role": m["role"]?.toString() ?? "user",
              "content": m["content"]?.toString() ?? "",
            })
        .toList();

    setState(() {
      _generatingConversationIds.add(targetConvId);
      if (_currentConversationId == targetConvId) {
        _currentMessages = List.from(targetMsgList);
      }
    });
    _saveConversations();
    _scrollToBottom();

    String reply;
    if (currentFileBytes != null && currentFileName != null) {
      // Analyse du bulletin ou document
      try {
        final analysis = await ApiService.uploadAndParseBulletin(
          fileBytes: currentFileBytes,
          filename: currentFileName,
        );
        if (analysis["success"] == true) {
          final moy = analysis["moyenne_generale"];
          final mat = analysis["matieres"] as Map? ?? {};
          final matStr = mat.entries.map((e) => "${e.key}: ${e.value}/20").take(5).join(", ");
          reply = "J'ai bien analysé ton document ($currentFileName).\n\n"
              "• Moyenne détectée : ${moy != null ? '$moy/20' : 'Non précisée'}\n"
              "• Matières principales : $matStr\n\n"
              "Comment souhaites-tu exploiter ces notes pour tes vœux ou ton plan d'orientation ?";
        } else {
          reply = "J'ai bien reçu ton fichier $currentFileName. Quelles sont les questions précises que tu souhaites me poser dessus ?";
        }
      } catch (_) {
        reply = "Document $currentFileName bien réceptionné. Pose-moi ta question pour que je puisse t'aiguiller !";
      }
    } else {
      reply = await ApiService.askNova(
        message: text,
        history: historySnapshot,
        studentProfile: _studentProfile,
      );
    }

    if (!mounted) return;

    final assistantMsg = {"role": "assistant", "content": reply};
    targetMsgList.add(assistantMsg);
    _generatingConversationIds.remove(targetConvId);
    _saveConversations();

    if (mounted && _currentConversationId == targetConvId) {
      setState(() {
        _currentMessages = targetMsgList
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList();
      });
      _scrollToBottom();
    } else if (mounted) {
      setState(() {});
    }
  }

  bool get _isCurrentConversationGenerating {
    return _generatingConversationIds.contains(_currentConversationId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF1E293B), size: 24),
            tooltip: "Menu des conversations",
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Icon(Icons.auto_awesome, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text(
              "Nova",
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF1E293B), size: 26),
            tooltip: "Nouvelle conversation",
            onPressed: () => _startNewConversation(),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _currentMessages.isEmpty ? _buildEmptyState() : _buildMessagesList(),
          ),
          if (_isCurrentConversationGenerating) _buildGeneratingIndicator(),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// Barre latérale épurée : nom Nova, bouton Nouvelle conversation et historique
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Icon(Icons.auto_awesome, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Nova",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _startNewConversation();
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add_rounded, size: 20, color: Color(0xFF1E293B)),
                      SizedBox(width: 12),
                      Text(
                        "Nouvelle conversation",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 16, 16, 8),
              child: Text(
                "Récent",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _conversations.length,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemBuilder: (ctx, idx) {
                  final conv = _conversations[idx];
                  final convId = conv["id"] as String;
                  final isCurrent = convId == _currentConversationId;
                  final title = conv["title"]?.toString() ?? "Discussion";

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent ? const Color(0xFFE2E8F0) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      leading: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 17,
                        color: Color(0xFF64748B),
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                        onPressed: () => _deleteConversation(convId),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _selectConversation(convId);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Icon(Icons.auto_awesome, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 18),
            const Text(
              "Bonjour",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Par quoi commençons-nous aujourd'hui ?",
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildSuggestionCard("Quelles sont les prépas les plus adaptées à mes notes ?"),
            _buildSuggestionCard("Comment optimiser ma stratégie de vœux Parcoursup ?"),
            _buildSuggestionCard("Conseils pour faire décoller ma moyenne en sciences"),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _sendMessage(text),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      itemCount: _currentMessages.length,
      itemBuilder: (ctx, idx) {
        final msg = _currentMessages[idx];
        final isUser = msg["role"] == "user";
        final content = msg["content"]?.toString() ?? "";
        final attachment = msg["attachment"]?.toString();

        if (isUser) {
          // Bulle utilisateur : GRISE (comme demandé)
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 18),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), // Gris doux épuré
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attachment != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 14, color: Color(0xFF2563EB)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              attachment,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    content,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Réponse de l'IA (Nova) : PAS DE BULLE (style Gemini pur)
          return Container(
            margin: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Nova",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: SelectableText(
                    content,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 17, color: Color(0xFF94A3B8)),
                      tooltip: "Copier la réponse",
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Réponse copiée dans le presse-papier"),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        (_isSpeaking && _currentlySpokenText == content)
                            ? Icons.stop_circle_rounded
                            : Icons.volume_up_outlined,
                        size: 19,
                        color: (_isSpeaking && _currentlySpokenText == content)
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF94A3B8),
                      ),
                      tooltip: "Écouter la réponse",
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _speak(content),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildGeneratingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
            ).createShader(bounds),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text(
            "Nova réfléchit...",
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF94A3B8),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Barre de saisie style Gemini : bouton +, champ texte, micro, bouton d'envoi
  Widget _buildInputBar() {
    final hasText = _textController.text.trim().isNotEmpty || _attachedFileBytes != null;

    return Container(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom + 4 : 10,
      ),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachedFileName != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_file_rounded, size: 16, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Text(
                    _attachedFileName!,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _attachedFileName = null;
                        _attachedFileBytes = null;
                      });
                    },
                    child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9), // Capsule grise claire Gemini
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 22, color: Color(0xFF475569)),
                  tooltip: "Ajouter un fichier (bulletin ou PDF)",
                  onPressed: _pickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 14.5, color: Color(0xFF1E293B)),
                    decoration: const InputDecoration(
                      hintText: "Demander à Nova...",
                      hintStyle: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    size: 22,
                    color: _isListening ? Colors.red : const Color(0xFF475569),
                  ),
                  tooltip: "Dicter à la voix",
                  onPressed: _toggleSpeech,
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  child: IconButton(
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: hasText ? Colors.white : const Color(0xFF94A3B8),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: hasText ? const Color(0xFF2563EB) : Colors.transparent,
                    ),
                    onPressed: hasText ? () => _sendMessage() : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Nova est un mentor d'orientation et peut faire des erreurs. Vérifie les informations officielles.",
            style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
