import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceState {
  const VoiceState({
    this.isListening = false,
    this.isSpeaking = false,
    this.partialTranscript = '',
    this.lastFinalTranscript,
    this.error,
  });

  final bool isListening;
  final bool isSpeaking;
  final String partialTranscript;
  final String? lastFinalTranscript;
  final String? error;

  VoiceState copyWith({
    bool? isListening,
    bool? isSpeaking,
    String? partialTranscript,
    String? lastFinalTranscript,
    bool clearFinal = false,
    String? error,
    bool clearError = false,
  }) => VoiceState(
    isListening: isListening ?? this.isListening,
    isSpeaking: isSpeaking ?? this.isSpeaking,
    partialTranscript: partialTranscript ?? this.partialTranscript,
    lastFinalTranscript: clearFinal
        ? null
        : (lastFinalTranscript ?? this.lastFinalTranscript),
    error: clearError ? null : (error ?? this.error),
  );
}

class VoiceController extends Notifier<VoiceState> {
  static const _methods = MethodChannel('agy/voice');
  static const _events = EventChannel('agy/voice/events');
  StreamSubscription<Object?>? _sub;

  @override
  VoiceState build() {
    try {
      _sub = _events.receiveBroadcastStream().listen(
        _onEvent,
        onError: (_) {},
      );
    } catch (_) {
      // Non-Android / test environment.
    }
    ref.onDispose(() => unawaited(_sub?.cancel()));
    return const VoiceState();
  }

  Future<void> toggleListening({String locale = 'zh-CN'}) async {
    if (state.isListening) {
      await stopListening();
    } else {
      await startListening(locale: locale);
    }
  }

  Future<void> startListening({String locale = 'zh-CN'}) async {
    state = state.copyWith(clearError: true, partialTranscript: '');
    try {
      await _methods.invokeMethod<bool>('startListening', {'locale': locale});
    } on PlatformException catch (e) {
      state = state.copyWith(
        isListening: false,
        error: e.message ?? '无法启动语音识别',
      );
    } on MissingPluginException {
      state = state.copyWith(error: '语音识别仅在 Android 真机可用');
    }
  }

  Future<void> stopListening() async {
    try {
      await _methods.invokeMethod<void>('stopListening');
    } on MissingPluginException {
      // Non-Android environment.
    }
    state = state.copyWith(isListening: false);
  }

  Future<void> speak(String text, {String locale = 'zh-CN'}) async {
    try {
      await _methods.invokeMethod<void>('speak', {
        'text': text,
        'locale': locale,
      });
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _methods.invokeMethod<void>('stopSpeaking');
    } on MissingPluginException {
      // Non-Android environment.
    }
    state = state.copyWith(isSpeaking: false);
  }

  void consumeFinalTranscript() {
    state = state.copyWith(clearFinal: true, partialTranscript: '');
  }

  void _onEvent(Object? raw) {
    if (!ref.mounted || raw is! Map) return;
    switch (raw['type']) {
      case 'listening':
        state = state.copyWith(isListening: raw['active'] == true);
      case 'partial':
        state = state.copyWith(
          partialTranscript: raw['text'] as String? ?? '',
          clearError: true,
        );
      case 'final':
        state = state.copyWith(
          isListening: false,
          partialTranscript: '',
          lastFinalTranscript: raw['text'] as String? ?? '',
          clearError: true,
        );
      case 'error':
        state = state.copyWith(
          isListening: false,
          error: raw['message'] as String? ?? '语音识别失败',
        );
      case 'ttsStart':
        state = state.copyWith(isSpeaking: true);
      case 'ttsDone':
        state = state.copyWith(isSpeaking: false);
    }
  }
}

final voiceProvider = NotifierProvider<VoiceController, VoiceState>(
  VoiceController.new,
);
