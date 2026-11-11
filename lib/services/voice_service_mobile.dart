import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoicePlatform {
  static FlutterTts? _flutterTts;
  static bool _ttsInitialized = false;
  static Timer? _simTimer;

  static stt.SpeechToText? _speech;
  static bool _speechInitialized = false;

  static Future<void> _initTts() async {
    if (_ttsInitialized) return;
    try {
      _flutterTts = FlutterTts();
      await _flutterTts!.setLanguage("fr-FR");
      await _flutterTts!.setPitch(1.02);
      await _flutterTts!.setSpeechRate(0.48); // Cadence posée, humaine et naturelle

      // Tenter de sélectionner la meilleure voix française (Google HD / Réseau si disponible)
      try {
        final voices = await _flutterTts!.getVoices;
        if (voices is List) {
          for (final v in voices) {
            if (v is Map) {
              final locale = (v["locale"] ?? "").toString().toLowerCase();
              final name = (v["name"] ?? "").toString().toLowerCase();
              if (locale.contains("fr") && (name.contains("fr-fr-x") || name.contains("google") || name.contains("high") || name.contains("natural"))) {
                await _flutterTts!.setVoice({"name": v["name"], "locale": v["locale"]});
                break;
              }
            }
          }
        }
      } catch (_) {}

      _ttsInitialized = true;
    } catch (e) {
      debugPrint("FlutterTts init error: $e");
    }
  }

  static void speak(String text, {VoidCallback? onStart, VoidCallback? onEnd}) {
    _initTts().then((_) async {
      if (_flutterTts != null) {
        try {
          _flutterTts!.setStartHandler(() {
            onStart?.call();
          });
          _flutterTts!.setCompletionHandler(() {
            onEnd?.call();
          });
          _flutterTts!.setErrorHandler((msg) {
            onEnd?.call();
          });
          await _flutterTts!.speak(text);
          return;
        } catch (e) {
          debugPrint("FlutterTts speak error: $e");
        }
      }

      // Simulation de secours si le moteur TTS du système est indisponible
      final durationMs = (text.length * 70).clamp(2000, 10000);
      _simTimer?.cancel();
      _simTimer = Timer(Duration(milliseconds: durationMs), () {
        onEnd?.call();
      });
    });
  }

  static void stopSpeaking() {
    _simTimer?.cancel();
    if (_flutterTts != null) {
      try {
        _flutterTts!.stop();
      } catch (_) {}
    }
  }

  static bool startListening({
    required Function(String text) onResult,
    VoidCallback? onEnd,
  }) {
    _startListeningAsync(onResult, onEnd);
    return true;
  }

  static Future<void> _startListeningAsync(
    Function(String text) onResult,
    VoidCallback? onEnd,
  ) async {
    try {
      _speech ??= stt.SpeechToText();
      if (!_speechInitialized) {
        _speechInitialized = await _speech!.initialize(
          onError: (val) {
            debugPrint("SpeechToText error: $val");
            if (val.permanent) {
              onEnd?.call();
            }
          },
          onStatus: (status) {
            debugPrint("SpeechToText status: $status");
            if (status == 'done') {
              onEnd?.call();
            }
          },
        );
      }

      if (_speechInitialized) {
        await _speech!.listen(
          onResult: (result) {
            if (result.recognizedWords.isNotEmpty) {
              onResult(result.recognizedWords);
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            cancelOnError: false,
            partialResults: true,
            localeId: 'fr_FR',
            pauseFor: const Duration(seconds: 4),
            listenFor: const Duration(minutes: 1),
          ),
        );
      } else {
        onEnd?.call();
      }
    } catch (e) {
      debugPrint("SpeechToText start error: $e");
      onEnd?.call();
    }
  }

  static void stopListening() {
    try {
      _speech?.stop();
    } catch (_) {}
  }
}
