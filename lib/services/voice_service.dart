import 'package:flutter/foundation.dart';
import 'voice_service_mobile.dart'
    if (dart.library.html) 'voice_service_web.dart';

class VoiceService {
  static bool _isSpeaking = false;
  static bool _isListening = false;

  static bool get isSpeaking => _isSpeaking;
  static bool get isListening => _isListening;

  /// Nettoie un texte pour une diction orale fluide et naturelle :
  /// - Supprime les émojis Unicode (évite que le TTS lise "chapeau de remise de diplôme", "ampoule", etc.)
  /// - Transforme l'écriture inclusive avec barres obliques : "expert/experte" -> "expert ou experte"
  /// - Supprime les mentions de genre entre parenthèses : "(H/F)", "(h/f)"
  /// - Supprime le formatage Markdown (astérisques, dièses, backticks, puces)
  /// - Traduit les symboles courants : "&" -> "et", "%" -> "pour cent", "€" -> "euros"
  static String cleanForSpeech(String text) {
    if (text.isEmpty) return text;
    String res = text;

    // 1. Supprime les mentions (H/F), (h/f), (F/H)
    res = res.replaceAll(RegExp(r'\(\s*[hHfF]\s*/\s*[hHfF]\s*\)'), '');

    // 2. Traite les notes scolaires et fractions : ex "8/20" -> "8 sur 20", "14.5/20" -> "14.5 sur 20"
    res = res.replaceAllMapped(
      RegExp(r'(\d+(?:[.,]\d+)?)\s*/\s*(\d+)'),
      (match) => '${match.group(1)} sur ${match.group(2)}',
    );

    // 3. Traite les barres obliques de genre : ex "expert / experte" -> "expert ou experte"
    res = res.replaceAllMapped(
      RegExp(r'([A-Za-zÀ-ÿ]+)\s*/\s*([A-Za-zÀ-ÿ]+)'),
      (match) => '${match.group(1)} ou ${match.group(2)}',
    );

    // 4. Remplace les barres obliques restantes par une virgule
    res = res.replaceAll('/', ', ');

    // 4. Supprime tous les émojis Unicode
    res = res.replaceAll(
      RegExp(
        r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{FE00}-\u{FE0F}\u{200D}\u{20E3}\u{2934}\u{2935}\u{2190}-\u{21FF}]',
        unicode: true,
      ),
      '',
    );

    // 5. Supprime les balises et puces Markdown (*, **, _, __, #, `, •, ⁃, ▪, etc.)
    res = res.replaceAll(RegExp(r'(\*\*|__|\*|_|#+|`+|•|⁃|▪|▫|→|⇒)'), ' ');

    // 6. Remplacement des symboles oraux
    res = res.replaceAll('&', ' et ');
    res = res.replaceAll('%', ' pour cent ');
    res = res.replaceAll('€', ' euros ');

    // 7. Nettoyage des espaces multiples et ponctuation double
    res = res.replaceAll(RegExp(r'\s+'), ' ').trim();
    return res;
  }

  /// Prononce un texte à voix haute en français après nettoyage phonétique
  static void speak(String text, {VoidCallback? onStart, VoidCallback? onEnd}) {
    stopSpeaking();
    final cleaned = cleanForSpeech(text);
    if (cleaned.isEmpty) {
      onEnd?.call();
      return;
    }

    _isSpeaking = true;
    onStart?.call();

    VoicePlatform.speak(
      cleaned,
      onStart: onStart,
      onEnd: () {
        _isSpeaking = false;
        onEnd?.call();
      },
    );
  }

  /// Arrête la parole immédiatement
  static void stopSpeaking() {
    _isSpeaking = false;
    VoicePlatform.stopSpeaking();
  }

  /// Active l'écoute microphone
  static bool startListening({
    required Function(String text) onResult,
    VoidCallback? onEnd,
  }) {
    _isListening = true;
    final success = VoicePlatform.startListening(
      onResult: (text) {
        onResult(text);
      },
      onEnd: () {
        _isListening = false;
        onEnd?.call();
      },
    );
    if (!success) {
      _isListening = false;
    }
    return success;
  }

  /// Arrête l'écoute
  static void stopListening() {
    _isListening = false;
    VoicePlatform.stopListening();
  }
}
