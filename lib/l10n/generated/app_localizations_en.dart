// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SpeakOut · 子曰';

  @override
  String get tabGeneral => 'General';

  @override
  String get tabModels => 'Voice Models';

  @override
  String get language => 'Language';

  @override
  String get langSystem => 'System Default';

  @override
  String get audioInput => 'Audio Input Device';

  @override
  String get systemDefault => 'System Default';

  @override
  String get aiCorrection => 'AI Smart Correction (Beta)';

  @override
  String get aiCorrectionDesc =>
      'Use LLM to remove filler words and polish text.';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get apiConfig => 'API Config (OpenAI Compatible)';

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get resetDefault => 'Reset Default';

  @override
  String get triggerKey => 'Trigger Key (PTT)';

  @override
  String get triggerKeyDesc =>
      'Hold key to speak, release to input. Supports all keys (incl. FN).';

  @override
  String get pressAnyKey => 'Press any key...';

  @override
  String get activeEngine => 'Active Voice Engine';

  @override
  String get engineLocal => '🔒 Local Offline Model (Privacy)';

  @override
  String get engineLocalDesc =>
      'Fully offline, privacy protected. No internet required.';

  @override
  String get engineCloud => '☁️ Aliyun Smart Voice (Cloud)';

  @override
  String get engineCloudDesc => 'Higher accuracy via cloud. Requires API Key.';

  @override
  String get aliyunConfig => 'Aliyun Config';

  @override
  String get aliyunConfigDesc =>
      'Get AccessKey and AppKey from Aliyun NLS Console.';

  @override
  String get saveApply => 'Save & Apply';

  @override
  String get download => 'Download';

  @override
  String downloading(Object percent) {
    return 'Downloading... $percent%';
  }

  @override
  String get preparing => 'Preparing...';

  @override
  String get unzipping => 'Unzipping...';

  @override
  String get activate => 'Activate';

  @override
  String get active => 'Active';

  @override
  String get settings => 'Settings';

  @override
  String get initializing => 'Initializing...';

  @override
  String readyTip(Object key) {
    return 'Hold $key to speak';
  }

  @override
  String get recording => 'Recording...';

  @override
  String get processing => 'Processing...';

  @override
  String get error => 'Error';

  @override
  String get micError => 'Mic Error';

  @override
  String get noSpeech => 'No Speech Detected';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get modelZipformerName => 'Zipformer Bilingual (Recommended)';

  @override
  String get modelZipformerDesc =>
      'Balanced streaming model (Zh/En). Download: ~490MB';

  @override
  String get modelParaformerName => 'Paraformer Bilingual (Streaming)';

  @override
  String get modelParaformerDesc =>
      'High accuracy Zh/En streaming model with lookahead. ~1GB';

  @override
  String get change => 'Change';

  @override
  String get tabAbout => 'About';

  @override
  String get aboutTagline => 'Your Local AI Speech Assistant';

  @override
  String get aboutSubTagline => 'Secure. Fast. Offline.';

  @override
  String get aboutPoweredBy => 'Powered by';

  @override
  String get aboutCopyright => 'Copyright © 2026 Leon. All Rights Reserved.';

  @override
  String get diaryMode => 'Flash Note';

  @override
  String get diaryTrigger => 'Note Hotkey';

  @override
  String get diaryPath => 'Save Directory';

  @override
  String get createFolder => 'New Folder';

  @override
  String get folderCreated => 'Folder Created';

  @override
  String get chooseFile => 'Choose File...';

  @override
  String get diarySaved => 'Saved to Note';

  @override
  String get engineType => 'Engine Type';

  @override
  String get punctuationModel => 'Punctuation Model';

  @override
  String get punctuationModelDesc =>
      'Automatically adds punctuation to recognized text. This model is required.';

  @override
  String get asrModels => 'Speech Recognition Models';

  @override
  String get asrModelsDesc =>
      'Please download and activate at least one ASR model to use voice input.';

  @override
  String get required => 'Required';

  @override
  String get pickOne => 'Pick One';

  @override
  String get llmProvider => 'LLM Provider';

  @override
  String get llmProviderCloud => 'Cloud API';

  @override
  String get llmProviderOllama => 'Ollama (Local)';

  @override
  String get ollamaUrl => 'Ollama URL';

  @override
  String get ollamaModel => 'Model Name';

  @override
  String get permInputMonitoring => 'Input Monitoring';

  @override
  String get permInputMonitoringDesc => 'For listening to hotkey triggers';

  @override
  String get permAccessibility => 'Accessibility';

  @override
  String get permAccessibilityDesc => 'For typing text into applications';

  @override
  String get streamingModels => 'Streaming Models (Real-time)';

  @override
  String get streamingModelsDesc =>
      'Shows text in real-time as you speak. Best for long dictation.';

  @override
  String get offlineModels => 'Offline Models (High Accuracy)';

  @override
  String get offlineModelsDesc =>
      'Recognizes after recording stops. Higher accuracy, no real-time subtitles.';

  @override
  String get switchToOfflineTitle => 'Switch to Offline Mode?';

  @override
  String get switchToOfflineBody =>
      'Offline models recognize after you release the key — no real-time subtitles during recording. Accuracy is higher. Continue?';

  @override
  String get switchToStreamingTitle => 'Switch to Streaming Mode?';

  @override
  String get switchToStreamingBody =>
      'Streaming models show text in real-time as you speak. Accuracy may be slightly lower. Continue?';

  @override
  String get confirm => 'Confirm';

  @override
  String get modelSenseVoiceName => 'SenseVoice 2024 (Recommended)';

  @override
  String get modelSenseVoiceDesc =>
      'Alibaba DAMO, Zh/En/Ja/Ko/Yue, built-in punctuation. ~228MB';

  @override
  String get modelSenseVoice2025Name => 'SenseVoice 2025';

  @override
  String get modelSenseVoice2025Desc =>
      'Cantonese enhanced, no built-in punctuation. ~158MB';

  @override
  String get modelOfflineParaformerName => 'Paraformer Offline';

  @override
  String get modelOfflineParaformerDesc => 'Zh/En, mature & stable. ~217MB';

  @override
  String get modelParaformerDialectName => 'Paraformer Dialect 2025';

  @override
  String get modelParaformerDialectDesc =>
      'Zh/En + Sichuan/Chongqing dialects. ~218MB';

  @override
  String get modelWhisperName => 'Whisper Large-v3';

  @override
  String get modelWhisperDesc =>
      'OpenAI Whisper, great for Zh/En/Ja/Ko/Fr/De/Es/Ru + 90 more languages. ~1.0GB';

  @override
  String get modelFireRedName => 'FireRedASR Large';

  @override
  String get modelFireRedDesc => 'Zh/En + dialects, highest capacity. ~1.4GB';

  @override
  String get builtInPunctuation => 'Built-in punctuation';

  @override
  String get needsPunctuationModel => 'Requires punctuation model';

  @override
  String get recognizing => 'Recognizing...';

  @override
  String get modeStreaming => 'Streaming';

  @override
  String get modeOffline => 'Offline';

  @override
  String get chooseModel => 'Choose a Voice Model';

  @override
  String get chooseModelDesc =>
      'Select a model to download. You can change it later in Settings.';

  @override
  String get recommended => 'Recommended';

  @override
  String get onboardingWelcome => 'Welcome to SpeakOut';

  @override
  String get onboardingWelcomeDesc =>
      'Hold a hotkey to speak, release to auto-type\nSupports multilingual recognition';

  @override
  String get onboardingStartSetup => 'Get Started';

  @override
  String get onboardingPermTitle => 'Permissions Required';

  @override
  String get onboardingPermDesc =>
      'SpeakOut needs the following permissions to work properly';

  @override
  String get permMicrophone => 'Microphone';

  @override
  String get permMicrophoneDesc => 'For recording voice for recognition';

  @override
  String get permGrant => 'Grant';

  @override
  String get permGranted => 'Granted';

  @override
  String get permRefreshStatus => 'Refresh Status';

  @override
  String get permRestartHint =>
      'Granted? Restart app for permissions to take effect';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingGrantFirst => 'Please grant permissions first';

  @override
  String get onboardingSetupLater => 'Set up later';

  @override
  String get onboardingCustomSelect => 'Custom Selection';

  @override
  String onboardingBrowseModels(Object count) {
    return 'Browse all $count models, including dialects and large models';
  }

  @override
  String get onboardingModelSubtitle =>
      'Zh/En/Ja/Ko/Yue, built-in punctuation, ~228MB';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingDownloadTitle => 'Download Voice Model';

  @override
  String onboardingDownloading(Object name) {
    return 'Downloading $name';
  }

  @override
  String get onboardingPreparing => 'Preparing download...';

  @override
  String get onboardingDownloadPunct => 'Downloading punctuation model...';

  @override
  String onboardingDownloadPunctPercent(Object percent) {
    return 'Downloading punctuation model... $percent%';
  }

  @override
  String get onboardingDownloadASR => 'Downloading ASR model...';

  @override
  String onboardingDownloadASRPercent(Object percent) {
    return 'Downloading ASR model... $percent%';
  }

  @override
  String get onboardingActivating => 'Activating model...';

  @override
  String get onboardingDownloadDone => 'Download complete!';

  @override
  String get onboardingDownloadFail => 'Download failed';

  @override
  String get onboardingRetry => 'Retry';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingStartDownload => 'Start Download';

  @override
  String get onboardingDoneTitle => 'Setup Complete!';

  @override
  String get onboardingHoldToSpeak => 'Hold to speak';

  @override
  String get onboardingDoneDesc => 'Release to auto-type at cursor position';

  @override
  String get onboardingBegin => 'Start Using';

  @override
  String get tabTrigger => 'Triggers';

  @override
  String get pttMode => 'Hold to Speak (PTT)';

  @override
  String get toggleModeTip => 'Tap to Toggle';

  @override
  String get textInjection => 'Text Input (IME)';

  @override
  String get asrDedup => 'ASR De-duplicate';

  @override
  String get recordingProtection => 'Recording Protection';

  @override
  String get toggleMaxDuration => 'Max Recording Duration';

  @override
  String get toggleMaxNone => 'No Limit';

  @override
  String toggleMaxMin(Object count) {
    return '$count min';
  }

  @override
  String get toggleHint =>
      'Tap to start, tap again to stop. If same key as PTT, hold >1s for PTT mode.';

  @override
  String get notSet => 'Not Set';

  @override
  String get importModel => 'Import';

  @override
  String get manualDownload => 'Manual Download';

  @override
  String get importModelDesc => 'Select a downloaded .tar.bz2 model file';

  @override
  String get importing => 'Importing...';
}
