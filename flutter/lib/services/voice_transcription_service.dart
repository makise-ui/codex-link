import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

class VoiceTranscriptionResult {
  const VoiceTranscriptionResult({required this.text});

  final String text;
}

abstract class VoiceTranscriptionService {
  Future<VoiceTranscriptionResult> transcribeOnce();
}

class SpeechToTextVoiceTranscriptionService
    implements VoiceTranscriptionService {
  SpeechToTextVoiceTranscriptionService({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  Future<VoiceTranscriptionResult> transcribeOnce() async {
    final completer = Completer<String>();
    var latestText = '';
    final available = await _speech.initialize(
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(
              error.errorMsg.isEmpty ? 'Voice input failed.' : error.errorMsg,
            ),
          );
        }
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') &&
            !completer.isCompleted) {
          completer.complete(latestText);
        }
      },
    );
    if (!available) {
      throw StateError('Voice input is unavailable on this device.');
    }
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        latestText = result.recognizedWords.trim();
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(latestText);
        }
      },
    );
    final String text;
    try {
      text = await completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () => latestText,
      );
    } finally {
      await _speech.stop();
    }
    return VoiceTranscriptionResult(text: text.trim());
  }
}
