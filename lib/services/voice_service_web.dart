import 'package:flutter/foundation.dart';
import 'dart:js_interop' as js;

@js.JS('orientationVoice.speak')
external void _jsSpeak(js.JSString text, js.JSFunction? onStart, js.JSFunction? onEnd);

@js.JS('orientationVoice.stopSpeaking')
external void _jsStopSpeaking();

@js.JS('orientationVoice.startListening')
external js.JSBoolean _jsStartListening(js.JSFunction? onResult, js.JSFunction? onEnd);

@js.JS('orientationVoice.stopListening')
external void _jsStopListening();

class VoicePlatform {
  static void speak(String text, {VoidCallback? onStart, VoidCallback? onEnd}) {
    try {
      final jsText = text.toJS;
      final jsStart = (() {
        onStart?.call();
      }).toJS;
      final jsEnd = (() {
        onEnd?.call();
      }).toJS;

      _jsSpeak(jsText, jsStart, jsEnd);
    } catch (e) {
      debugPrint("VoiceService Web speak error: $e");
      onEnd?.call();
    }
  }

  static void stopSpeaking() {
    try {
      _jsStopSpeaking();
    } catch (_) {}
  }

  static bool startListening({
    required Function(String text) onResult,
    VoidCallback? onEnd,
  }) {
    try {
      final jsResult = ((js.JSString transcript) {
        onResult(transcript.toDart);
      }).toJS;

      final jsEnd = (() {
        onEnd?.call();
      }).toJS;

      return _jsStartListening(jsResult, jsEnd).toDart;
    } catch (e) {
      debugPrint("VoiceService Web listen error: $e");
      return false;
    }
  }

  static void stopListening() {
    try {
      _jsStopListening();
    } catch (_) {}
  }
}
