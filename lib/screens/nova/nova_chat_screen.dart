import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  List<Map<String, String>> _currentMessages = [];

  // Suivi indépendant des générations par conversation (évite tout croisement)
  final Set<String> _generatingConversationIds = {};
  final Set<int> _expandedMessageIndices = {};
  Map<String, dynamic>? _studentProfile;

  static const String _storageKey = "nova_chat_conversations_v1";

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadStudentContext();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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
      "messages": <Map<String, String>>[],
    };

    setState(() {
      _conversations.insert(0, newConv);
      _currentConversationId = newId;
      _currentMessages = [];
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
        "messages": <Map<String, String>>[],
      },
    );
    setState(() {
      _currentConversationId = found["id"] as String;
      final rawMsgs = (found["messages"] as List?) ?? [];
      _currentMessages = rawMsgs.map((m) => Map<String, String>.from(m as Map)).toList();
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

  /// Envoi d'un message avec cloisonnement strict par conversation ID
  Future<void> _sendMessage([String? prefilledText]) async {
    final text = (prefilledText ?? _textController.text).trim();
    if (text.isEmpty) return;

    // Identifiant de la conversation ciblée par cet envoi précis
    final targetConvId = _currentConversationId;
    if (_generatingConversationIds.contains(targetConvId)) return;

    if (prefilledText == null) {
      _textController.clear();
    }

    final userMsg = {"role": "user", "content": text};

    // Trouver la conversation cible dans la liste
    Map<String, dynamic>? targetConv;
    for (final c in _conversations) {
      if (c["id"] == targetConvId) {
        targetConv = c;
        break;
      }
    }
    if (targetConv == null) return;

    final targetMsgList = (targetConv["messages"] as List);

    // Titrage automatique si premier message
    if (targetMsgList.isEmpty || targetConv["title"] == "Nouvelle discussion") {
      targetConv["title"] = text.length > 32 ? "${text.substring(0, 29)}..." : text;
    }
    targetMsgList.add(userMsg);

    // Snapshot de l'historique pour l'API
    final historySnapshot = targetMsgList
        .map((m) => Map<String, String>.from(m as Map))
        .toList();

    setState(() {
      _generatingConversationIds.add(targetConvId);
      if (_currentConversationId == targetConvId) {
        _currentMessages = List.from(historySnapshot);
      }
    });
    _saveConversations();
    _scrollToBottom();

    // Appel API à Nova
    final reply = await ApiService.askNova(
      message: text,
      history: historySnapshot,
      studentProfile: _studentProfile,
    );

    if (!mounted) return;

    final assistantMsg = {"role": "assistant", "content": reply};

    // Ajout de la réponse STRICTEMENT dans targetConv
    targetMsgList.add(assistantMsg);
    _generatingConversationIds.remove(targetConvId);
    _saveConversations();

    // Mise à jour de l'écran UNIQUEMENT si l'élève est toujours sur cette même conversation !
    if (mounted && _currentConversationId == targetConvId) {
      setState(() {
        _currentMessages = targetMsgList
            .map((m) => Map<String, String>.from(m as Map))
            .toList();
      });
      _scrollToBottom();
    } else if (mounted) {
      // S'il est sur une autre conversation, on déclenche un simple setState pour libérer l'indicateur
      setState(() {});
    }
  }

  String get _currentConversationTitle {
    for (final c in _conversations) {
      if (c["id"] == _currentConversationId) {
        final t = c["title"]?.toString() ?? "";
        if (t.isNotEmpty) return t;
      }
    }
    return "Nouvelle discussion";
  }

  bool get _isCurrentConversationGenerating {
    return _generatingConversationIds.contains(_currentConversationId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.history_rounded, color: AppTheme.textMain),
            tooltip: "Historique des discussions",
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.psychology_rounded, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentConversationTitle,
                    style: const TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.accentEmerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        "Nova • Mentor Orientation",
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: AppTheme.primary),
            tooltip: "Nouvelle discussion",
            onPressed: () => _startNewConversation(),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.borderColor),
        ),
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _currentMessages.isEmpty ? _buildEmptyState() : _buildMessagesList(),
          ),
          if (_isCurrentConversationGenerating) _buildTypingIndicator(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Historique Nova",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18, color: Colors.white),
                  label: const Text("Nouvelle discussion", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _startNewConversation();
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppTheme.borderColor),
            Expanded(
              child: ListView.separated(
                itemCount: _conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (ctx, idx) {
                  final conv = _conversations[idx];
                  final convId = conv["id"] as String;
                  final isCurrent = convId == _currentConversationId;
                  final title = conv["title"]?.toString() ?? "Discussion";
                  final isConvGen = _generatingConversationIds.contains(convId);

                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: AppTheme.primarySoft,
                    leading: isConvGen
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                          )
                        : Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: isCurrent ? AppTheme.primary : AppTheme.textMuted,
                          ),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent ? AppTheme.primary : AppTheme.textMain,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.textMuted),
                      onPressed: () => _deleteConversation(convId),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _selectConversation(convId);
                    },
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
    final suggestions = [
      "Comment progresser de 2 points en maths d'ici le prochain trimestre ?",
      "Quelles sont les prépas scientifiques les plus adaptées à mes notes ?",
      "Comment valoriser mes projets personnels dans mon dossier Parcoursup ?",
      "Quels débouchés réels après un BUT Informatique vs une Licence ?",
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology_outlined, size: 40, color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              "Bonjour, je suis Nova.",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              "Ton mentor dédié pour décrypter ton dossier, optimiser tes choix et réussir tes objectifs d'orientation.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.35),
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            "Suggestions de départ :",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textMain),
          ),
          const SizedBox(height: 10),
          ...suggestions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: InkWell(
                onTap: () => _sendMessage(s),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMain, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _currentMessages.length,
      itemBuilder: (ctx, idx) {
        final msg = _currentMessages[idx];
        final isUser = msg["role"] == "user";
        final content = msg["content"] ?? "";

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isUser ? AppTheme.primary : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 3),
                bottomRight: Radius.circular(isUser ? 3 : 14),
              ),
              border: Border.all(
                color: isUser ? AppTheme.primary : AppTheme.borderColor,
                width: 1,
              ),
              boxShadow: isUser ? null : AppTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (_) {
                    final isLong = !isUser && content.length > 280;
                    final isExpanded = _expandedMessageIndices.contains(idx);
                    final displayText = (isLong && !isExpanded)
                        ? "${content.substring(0, 240)}..."
                        : content;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayText,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: isUser ? Colors.white : AppTheme.textMain,
                            fontWeight: isUser ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                        if (isLong)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedMessageIndices.remove(idx);
                                  } else {
                                    _expandedMessageIndices.add(idx);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isExpanded ? "Réduire" : "Lire plus",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isExpanded ? AppTheme.textMuted : AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 16,
                                    color: isExpanded ? AppTheme.textMuted : AppTheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.psychology_outlined, size: 14, color: AppTheme.primary),
          ),
          const SizedBox(width: 8),
          const Text(
            "Nova formule sa réponse...",
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Pose ta question à Nova...",
                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppTheme.borderColor),
                ),
                filled: true,
                fillColor: AppTheme.cardBgElevated,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            onPressed: () => _sendMessage(),
          ),
        ],
      ),
    );
  }
}
