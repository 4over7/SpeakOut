import 'dart:ui';

import '../engine/engine_status.dart';
import '../l10n/generated/app_localizations.dart';
import 'config_service.dart';

String localizedEngineStatusForLocale(EngineStatus status, Locale locale) {
  final loc = lookupAppLocalizations(locale);
  final p = status.params;
  return switch (status.code) {
    'missing_permissions' => loc.engineMissingPermissions,
    'missing_input_monitoring' => loc.engineMissingInputMonitoring,
    'keyboard_listener_started' => loc.engineKeyboardListenerStarted,
    'accessibility_ready' => loc.engineAccessibilityReady,
    'accessibility_missing' => loc.engineAccessibilityMissing,
    'listener_failed_input_monitoring' =>
      loc.engineListenerFailedInputMonitoring,
    'listener_failed' => loc.engineListenerFailed,
    'connecting_provider' => loc.engineConnectingProvider(p['provider'] ?? ''),
    'provider_ready' => loc.engineProviderReady(p['provider'] ?? ''),
    'provider_connect_failed' => loc.engineProviderConnectFailed(
      p['provider'] ?? '',
      p['error'] ?? '',
    ),
    'loading_model' => loc.engineLoadingModel(p['model'] ?? ''),
    'model_ready' => loc.engineModelReady(p['model'] ?? ''),
    'model_load_failed' => loc.engineModelLoadFailed(
      p['model'] ?? '',
      p['error'] ?? '',
    ),
    'punctuation_ready_with_model' => loc.enginePunctuationReadyWithModel(
      p['model'] ?? '',
    ),
    'punctuation_ready' => loc.enginePunctuationReady,
    'punctuation_load_failed' => loc.enginePunctuationLoadFailed(
      p['error'] ?? '',
    ),
    'microphone_permission_required' => loc.engineMicrophonePermissionRequired,
    'speech_model_required' => loc.engineSpeechModelRequired,
    'speech_model_switching' => loc.engineSpeechModelSwitching,
    'microphone_start_failed' => loc.engineMicrophoneStartFailed,
    'recording_start_failed' => loc.engineRecordingStartFailed,
    'cancelled' => loc.engineCancelled,
    'processing' => loc.engineProcessing,
    'asr_failed' => loc.engineAsrFailed(p['error'] ?? ''),
    'translating' => loc.engineTranslating,
    'polishing' => loc.enginePolishing,
    'saving_note' => loc.engineSavingNote,
    'note_saved' => loc.engineNoteSaved,
    'note_save_failed' => loc.engineNoteSaveFailed,
    'ready' => loc.engineReady,
    'no_speech' => loc.noSpeech,
    'inject_failed' => loc.engineInjectFailed,
    'inject_partial' => loc.engineInjectPartial,
    'clipboard_restore_failed' => loc.engineClipboardRestoreFailed,
    'configuring_services' => loc.engineConfiguringServices,
    'starting_listener' => loc.engineStartingListener,
    'preparing_speech_model' => loc.enginePreparingSpeechModel,
    'speech_model_failed' => loc.engineSpeechModelFailed(p['error'] ?? ''),
    'recording_note' => loc.engineRecordingNote,
    'clipboard_busy' => loc.engineClipboardBusy,
    'selection_read_failed' => loc.engineSelectionReadFailed,
    'selection_empty' => loc.engineSelectionEmpty,
    'organizing' => loc.engineOrganizing,
    'organize_failed' => loc.engineOrganizeFailed,
    'organize_inject_failed' => loc.engineOrganizeInjectFailed,
    'offline_duration_warning' => loc.engineOfflineDurationWarning,
    'offline_duration_notification' => loc.engineOfflineDurationNotification,
    'silence_hint' => loc.engineSilenceHint,
    'silence_notification' => loc.engineSilenceNotification,
    _ => status.message,
  };
}

String localizedEngineStatusForCurrentLocale(EngineStatus status) {
  return localizedEngineStatusForLocale(status, currentAppLocale());
}

Locale currentAppLocale() {
  final configured = ConfigService().appLanguage;
  return switch (configured) {
    'zh' => const Locale('zh'),
    'en' => const Locale('en'),
    _ =>
      PlatformDispatcher.instance.locale.languageCode == 'zh'
          ? const Locale('zh')
          : const Locale('en'),
  };
}

AppLocalizations currentAppLocalizations() =>
    lookupAppLocalizations(currentAppLocale());
