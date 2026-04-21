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
  String get language => 'Interface Language';

  @override
  String get langSystem => 'System Default';

  @override
  String get inputLanguage => 'Input Language';

  @override
  String get inputLanguageDesc => 'Language you speak';

  @override
  String get outputLanguage => 'Output Language';

  @override
  String get outputLanguageDesc =>
      'Language for text output. Auto-translates when different from input';

  @override
  String get langAutoDetect => 'Auto-detect';

  @override
  String get langFollowInput => 'Follow input language';

  @override
  String get langZh => 'Chinese';

  @override
  String get langZhHans => 'Simplified Chinese';

  @override
  String get langZhHant => 'Traditional Chinese';

  @override
  String get langEn => 'English';

  @override
  String get langJa => 'Japanese';

  @override
  String get langKo => 'Korean';

  @override
  String get langYue => 'Cantonese';

  @override
  String get langEs => 'Spanish';

  @override
  String get langFr => 'French';

  @override
  String get langDe => 'German';

  @override
  String get langRu => 'Russian';

  @override
  String get langPt => 'Portuguese';

  @override
  String get translationModeHint => 'Translation Mode';

  @override
  String get translationNeedsSmartMode =>
      'Translation requires AI polish. Please switch to Smart Mode to enable it.';

  @override
  String get translationCloudLimited =>
      'Cloud mode has no AI polish. Translation quality will be limited. Recommend Smart Mode.';

  @override
  String inputLangModelHint(Object lang) {
    return 'Current model has limited support for $lang. Consider switching to Whisper Large-v3 for better recognition.';
  }

  @override
  String get audioInput => 'Audio Input Device';

  @override
  String get systemDefault => 'System Default';

  @override
  String get aiCorrection => 'AI Polish';

  @override
  String get aiCorrectionDesc =>
      'Use LLM to polish speech recognition results.';

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
  String get tabOrganize => 'AI Organize';

  @override
  String get organizeEnabled => 'AI Organize';

  @override
  String get organizeHotkey => 'Organize Hotkey';

  @override
  String get organizeHotkeyHint => 'Select text then press this hotkey';

  @override
  String get organizePrompt => 'Organize Instructions';

  @override
  String get organizeResetDefault => 'Reset Default';

  @override
  String get organizeDesc =>
      'Select any text and press the hotkey. AI will extract key points, restructure logic, and express professionally while preserving the original meaning.';

  @override
  String get organizeLlmHint => 'Uses the LLM provider configured in Work Mode';

  @override
  String get organizeGoConfig => 'Go to config →';

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
  String get offlineModels => 'Non-streaming Models (High Accuracy)';

  @override
  String get offlineModelsDesc =>
      'Recognizes after recording stops. Higher accuracy, no real-time subtitles.';

  @override
  String get switchToOfflineTitle => 'Switch to Non-streaming Model?';

  @override
  String get switchToOfflineBody =>
      'Non-streaming models recognize after you release the key — no real-time subtitles during recording. Accuracy is higher. Continue?';

  @override
  String get switchToStreamingTitle => 'Switch to Streaming Model?';

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
  String get modeOffline => 'Non-streaming';

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

  @override
  String get tabWorkMode => 'Work Mode';

  @override
  String get workModeOffline => 'Offline Mode';

  @override
  String get workModeOfflineDesc =>
      'Local Sherpa recognition, fully offline and private';

  @override
  String get workModeOfflineIcon => 'Privacy-first, zero network dependency';

  @override
  String get workModeSmart => 'Smart Mode';

  @override
  String get workModeSmartDesc =>
      'Local recognition + AI polish. Fixes homophones, removes filler words';

  @override
  String get workModeCloud => 'Cloud Recognition';

  @override
  String get workModeCloudDesc =>
      'Cloud high-accuracy recognition, requires internet';

  @override
  String get workModeSmartConfig => 'Smart Polish Config';

  @override
  String get workModeAdvanced => 'Advanced Settings';

  @override
  String get tabAiPolish => 'AI Polish';

  @override
  String get aiPolishDesc =>
      'Use LLM to polish speech results with professional vocabulary context.';

  @override
  String get vocabEnhancement => 'Professional Vocab';

  @override
  String get vocabEnhancementSubtitle =>
      'Provide terminology hints to AI for better domain recognition';

  @override
  String get vocabEnabled => 'Enable Professional Vocab';

  @override
  String get vocabIndustryPresets => 'Industry Preset Dictionaries';

  @override
  String get vocabCustomVocab => 'Personal Dictionary';

  @override
  String get vocabCustomEnabled => 'Enable Personal Dictionary';

  @override
  String get vocabAddEntry => 'Add Entry';

  @override
  String get vocabWrongForm => 'Wrong form (ASR output)';

  @override
  String get vocabCorrectForm => 'Correct form';

  @override
  String get vocabDelete => 'Delete';

  @override
  String get vocabTech => 'Software/IT';

  @override
  String get vocabMedical => 'Medical';

  @override
  String get vocabLegal => 'Legal';

  @override
  String get vocabFinance => 'Finance';

  @override
  String get vocabEducation => 'Education';

  @override
  String get vocabEnabledNote =>
      'When enabled, terminology is injected as context hints to AI Polish';

  @override
  String get vocabImportTsv => 'Import File';

  @override
  String get vocabImportTsvDesc =>
      'TSV or CSV format, one entry per line: wrong<Tab>correct';

  @override
  String vocabImportSuccess(Object count) {
    return '$count entries imported';
  }

  @override
  String vocabImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get vocabExportTsv => 'Export File';

  @override
  String get aiPolishWarning =>
      'AI Polish may alter meaning or introduce errors. Verify important text against the original. With AI off, raw ASR output is used — accuracy depends on the voice model.';

  @override
  String updateAvailable(Object version) {
    return 'New version $version available';
  }

  @override
  String get updateAction => 'View Update';

  @override
  String get updateUpToDate => 'Up to date';

  @override
  String get llmRewrite => 'LLM Rewrite';

  @override
  String get aiPolishMatrix =>
      'LLM ✓ + Vocab ✓ → Terms injected into LLM for smart correction\nLLM ✓ + Vocab ✗ → Pure LLM polish\nLLM ✗ + Vocab ✓ → Dictionary exact replacement (works offline)\nLLM ✗ + Vocab ✗ → Raw ASR output';

  @override
  String get tabCloudAccounts => 'Cloud Accounts';

  @override
  String get cloudAccountsTitle => 'Manage Cloud Accounts';

  @override
  String get cloudAccountAdd => 'Add Provider';

  @override
  String get cloudAccountEdit => 'Edit';

  @override
  String get cloudAccountDelete => 'Delete';

  @override
  String get cloudAccountCapabilityAsr => 'Speech Recognition';

  @override
  String get cloudAccountCapabilityLlm => 'AI Polish';

  @override
  String get cloudAccountNone => 'No accounts configured';

  @override
  String get cloudAccountSelectAsr => 'Select ASR Service';

  @override
  String get cloudAccountSelectLlm => 'Select LLM Service';

  @override
  String get cloudAccountGoConfig => 'Go to Cloud Accounts';

  @override
  String get cloudAccountSaved => 'Account saved';

  @override
  String get cloudAccountDeleted => 'Account deleted';

  @override
  String get cloudAccountDeleteConfirm => 'Delete this account?';

  @override
  String get cloudAccountProvider => 'Provider';

  @override
  String get cloudAccountName => 'Display Name';

  @override
  String get cloudAccountEnabled => 'Enabled';

  @override
  String get languageSettings => 'Language';

  @override
  String get translationDisabledReason =>
      'Translation requires AI polish, only available in Smart Mode';

  @override
  String get cloudAsrLangUnsupported =>
      'Current cloud ASR service only supports Chinese and English. Selected language will fall back to Chinese recognition.';

  @override
  String get quickTranslate => 'Quick Translate';

  @override
  String get quickTranslateDesc =>
      'Press hotkey to record, result auto-translates to target language (does not affect normal recording settings)';

  @override
  String get translateTargetLanguage => 'Target Language';

  @override
  String get translateHotkey => 'Translate Hotkey';

  @override
  String get translateNoLlm =>
      'Quick Translate requires an LLM service. Please add one in Cloud Accounts.';

  @override
  String get settingsV18PreviewTitle => 'Settings (v1.8 Preview)';

  @override
  String get sidebarSectionBasic => 'Basic';

  @override
  String get sidebarSectionVoice => 'Voice';

  @override
  String get sidebarSectionSuperpower => 'Superpower';

  @override
  String get sidebarSectionOther => 'Other';

  @override
  String get sidebarOverview => 'Overview';

  @override
  String get sidebarShortcuts => 'Shortcuts';

  @override
  String get sidebarPermissions => 'Permissions';

  @override
  String get sidebarRecognition => 'Recognition';

  @override
  String get sidebarAiPlus => 'AI Plus';

  @override
  String get sidebarVocab => 'Vocabulary';

  @override
  String get sidebarCorrection => 'Correction';

  @override
  String get sidebarAiReport => 'AI Debug';

  @override
  String get showAdvanced => 'Advanced';

  @override
  String get shortcutsRecordKey => 'Record Key';

  @override
  String get shortcutsSharedHint =>
      'Tap = toggle recording, Hold = push-to-talk';

  @override
  String get shortcutsSplitTitle => 'Record Key (PTT / Toggle separately)';

  @override
  String get shortcutsPttTitle => 'Push-to-Talk (PTT)';

  @override
  String get shortcutsPttHint => 'Hold to record, release to stop';

  @override
  String get shortcutsToggleTitle => 'Toggle';

  @override
  String get shortcutsToggleHint => 'Tap to start, tap again to stop';

  @override
  String get shortcutsTip =>
      'Recommended: Right Option / Fn / F13–F19 — Cmd / Ctrl combos are often taken by system apps.';

  @override
  String get hotkeyModalTitle => 'Record Hotkey';

  @override
  String get hotkeyModalSubtitle =>
      'Press the key or combination you want to set';

  @override
  String hotkeyModalCountdown(int seconds) {
    return 'Cancels in ${seconds}s · Press ESC to exit';
  }

  @override
  String get hotkeyModalRecommend => 'Recommended';

  @override
  String get hotkeyModalAvoid =>
      'Avoid Cmd / Ctrl combinations (often taken by system apps)';

  @override
  String hotkeyInUseTitle(String keyName, String feature) {
    return '$keyName is already used by \"$feature\"';
  }

  @override
  String get hotkeyInUseMessage => 'That key is taken. Please choose another.';

  @override
  String get hotkeyInUseOk => 'OK';

  @override
  String get hotkeyRecordDiary => 'Record Flash Note Key';

  @override
  String get hotkeyRecordDiaryHint => 'Hold to start recording a note';

  @override
  String get hotkeyRecordToggleDiary => 'Record Note Toggle Key';

  @override
  String get hotkeyRecordToggleDiaryHint => 'Tap to start, tap again to stop';

  @override
  String get hotkeyRecordOrganize => 'Record AI Organize Key';

  @override
  String get hotkeyRecordOrganizeHint =>
      'After selecting text, press to reorganize';

  @override
  String get hotkeyRecordTranslate => 'Record Quick Translate Key';

  @override
  String get hotkeyRecordTranslateHint =>
      'After selecting text, press to translate';

  @override
  String get hotkeyRecordCorrection => 'Record Correction Key';

  @override
  String get hotkeyRecordCorrectionHint =>
      'After selecting text, press to submit correction';

  @override
  String get hotkeyRecordAiReport => 'Record AI Debug Base Key';

  @override
  String get hotkeyRecordAiReportHint => 'Hold + digit 1-5 to activate';

  @override
  String get overviewWelcome => 'Welcome to SpeakOut';

  @override
  String get overviewTagline =>
      'macOS offline-first AI dictation · Private · Free & Open';

  @override
  String get overviewGetStarted => 'Get Started';

  @override
  String get featureOfflineTitle => 'Offline Recognition';

  @override
  String get featureOfflineDesc =>
      'Local Sherpa-ONNX ASR, on-device; accuracy rivals cloud';

  @override
  String get featureAiPolishTitle => 'AI Polish';

  @override
  String get featureAiPolishDesc =>
      'Cloud LLM fixes homophones, punctuation, and grammar';

  @override
  String get featureSuperpowerTitle => 'Superpower';

  @override
  String get featureSuperpowerDesc =>
      'Flash Note / AI Organize / Quick Translate / Correction / AI Debug';

  @override
  String get featureVocabTitle => 'Professional Vocab';

  @override
  String get featureVocabDesc =>
      'Custom terms injected into LLM prompt; medical / legal / finance packs';

  @override
  String get overviewHelpTitle => 'Help & Support';

  @override
  String get linkWikiFaq => 'Wiki · FAQ';

  @override
  String get linkChangelog => 'Changelog';

  @override
  String get linkXHandle => 'X · @4over7';

  @override
  String get linkFeedback => 'Feedback · 4over7@gmail.com';

  @override
  String get linkGithubIssues => 'GitHub Issues';

  @override
  String get smartNeedsAiPlusConfig =>
      'Smart mode needs LLM configured in \"AI Plus\" (provider / model / API key), otherwise AI polish won\'t apply.';

  @override
  String get gotoAiPlus => 'Go to AI Plus';

  @override
  String get aiPlusNotActive =>
      'AI Polish is not active: switch work mode to Smart (offline + cloud AI) in \"Recognition\". You can still edit LLM config here.';

  @override
  String get aboutModelsDir => 'Models Directory';

  @override
  String get aboutGatewayUrl => 'Gateway URL';

  @override
  String get aboutGatewayDesc => 'License / subscription / cloud token proxy';

  @override
  String get aboutDiagnostics => 'Diagnostics';

  @override
  String get aboutDiagnosticsDesc =>
      'Copy version / config / paths to clipboard (paste when reporting bugs)';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionCopied => 'Copied';

  @override
  String get permissionsSectionTitle => 'System Permissions';

  @override
  String get permissionsReauthTip =>
      'If shortcuts stop working after a code-signing change, re-grant each permission below.';

  @override
  String get permissionsAccessibility => 'Accessibility';

  @override
  String get permissionsAccessibilityDesc => 'Shortcuts + text injection';

  @override
  String get permissionsInputMonitoring => 'Input Monitoring';

  @override
  String get permissionsInputMonitoringDesc => 'Keyboard-triggered recording';

  @override
  String get permissionsMicrophone => 'Microphone';

  @override
  String get permissionsMicrophoneDesc => 'Audio capture';

  @override
  String get permissionsOpen => 'Open';

  @override
  String get aboutDeveloper => 'Developer';

  @override
  String get aboutVerboseLogging => 'Verbose Logging';

  @override
  String get aboutLogDir => 'Log Directory';

  @override
  String get aboutLogDirUnset => 'Not set (console only)';

  @override
  String get aboutLoading => 'Loading…';

  @override
  String get aboutConfigBackup => 'Config Backup';

  @override
  String get aboutExportConfig => 'Export Config';

  @override
  String get aboutExportConfigDesc =>
      'Export all settings and credentials to file (plaintext keys included, store safely)';

  @override
  String get aboutExportAction => 'Export';

  @override
  String get aboutExportFileTitle => 'Export Config File';

  @override
  String get aboutImportConfig => 'Import Config';

  @override
  String get aboutImportConfigDesc =>
      'Restore all settings from a backup file, takes effect immediately';

  @override
  String get aboutImportAction => 'Import';

  @override
  String get aboutImportFileTitle => 'Choose Config File';

  @override
  String aboutExportSuccess(String msg) {
    return 'Exported: $msg';
  }

  @override
  String aboutExportFailed(String err) {
    return 'Export failed: $err';
  }

  @override
  String aboutImportSuccess(String msg) {
    return '$msg, config applied';
  }

  @override
  String aboutImportFailed(String err) {
    return 'Import failed: $err';
  }

  @override
  String audioDeviceCurrent(String name) {
    return 'Current: $name';
  }

  @override
  String get bluetoothMicWarning => 'Bluetooth mic may reduce quality';

  @override
  String get switchToBuiltin => 'Switch to built-in';

  @override
  String get autoOptimizeAudio => 'Auto-optimize audio';

  @override
  String get autoOptimizeAudioDesc =>
      'Auto-switch to higher-quality mic when Bluetooth headset is connected';

  @override
  String get hotkeyConflictTaken => 'That key is taken. Please choose another.';

  @override
  String hotkeyConflictAutoClearTitle(String keyName, String feature) {
    return '$keyName is taken by \"$feature\"';
  }

  @override
  String get hotkeyConflictAutoClearMsg =>
      'The hotkey has been cleared. Please set a new one.';

  @override
  String modelActivateFailed(String err) {
    return 'Model activation failed: $err';
  }

  @override
  String get punctAutoLoaded => 'Punctuation model auto-loaded';

  @override
  String get punctMissingTitle => 'This model has no punctuation';

  @override
  String get punctMissingMsg =>
      'This model outputs text without punctuation. Consider downloading the punctuation model for better readability.\n\nDownload now?';

  @override
  String get punctDownload => 'Download';

  @override
  String get punctSkip => 'Not now';

  @override
  String get offlineDataLocal =>
      'All data is processed locally; nothing is uploaded';

  @override
  String get asrModel => 'ASR Model';

  @override
  String get manageCloudAccounts => 'Manage Cloud Accounts';

  @override
  String get typewriterEffect => 'Typewriter Effect';

  @override
  String get ollamaServerRequired =>
      'Make sure Ollama is running (ollama serve)';

  @override
  String get manageModels => 'Manage Models';

  @override
  String get llmRecommendations => 'Recommendations';

  @override
  String get llmTagFastest => 'Fastest';

  @override
  String get llmTagStable => 'Stable Pick';

  @override
  String get llmTagFastestNote => 'May fluctuate at peak';

  @override
  String get llmTagStableNote => 'Least fluctuation, stable quality';

  @override
  String get llmDataSource =>
      'Source: 2026-03-21 benchmark, non-streaming API, China Mainland network';

  @override
  String get llmModelField => 'Model';

  @override
  String get llmModelCustom => 'Custom...';

  @override
  String get llmModelNamePlaceholder => 'Model name';

  @override
  String get diaryDirNotSet => 'No save directory set';

  @override
  String get diaryDirCannotWrite =>
      'Cannot write to this directory, please reselect (macOS requires re-authorization)';

  @override
  String get diaryDirPick => 'Please select a save directory to grant access';

  @override
  String get diaryDesc =>
      'Record ideas anywhere with voice, auto-saved as Markdown diary.';

  @override
  String get organizeCollapse => 'Collapse';

  @override
  String get organizeEditInstruction => 'Edit Prompt';

  @override
  String get correctionHotkey => 'Correction Hotkey';

  @override
  String get correctionExportDialog => 'Export Correction Data';

  @override
  String get correctionImportDialog => 'Import Correction Data';

  @override
  String get correctionExportSuccess => 'Export successful';

  @override
  String get correctionExportFailedEmpty => 'Export failed: no data';

  @override
  String correctionImportSuccess(int count) {
    return 'Imported $count entries (vocab synced)';
  }

  @override
  String get correctionExportBtn => 'Export';

  @override
  String get correctionImportBtn => 'Import';

  @override
  String get correctionDesc =>
      'Select the corrected text and submit. ASR learns your wording over time.';

  @override
  String get aiReportBaseKey => 'Base Key';

  @override
  String aiReportBaseKeyDesc(String baseKeyName, int slotCount) {
    return 'Hold $baseKeyName + digit (1–$slotCount) to pick target window';
  }

  @override
  String get aiReportAddFirstWindow => 'Add First Window';

  @override
  String get aiReportAddWindow => 'Add Window';

  @override
  String get aiReportDescShort =>
      'Built for AI Coding — screenshot + voice auto-sent to bound window';

  @override
  String get aiReportDescLong =>
      'Built for AI Coding — screenshot + voice description, one-tap send to Claude Code / Cursor.';

  @override
  String get aiReportSwitchWindow => 'Switch to target window...';

  @override
  String get aiReportUnbound => 'Unbound';

  @override
  String get aiReportBindTitle => 'Bind AI Tool Window';

  @override
  String get aiReportBindMsg =>
      'After clicking \"Start\", you have 3 seconds to switch to the target window.';

  @override
  String get aiReportStart => 'Start';

  @override
  String get aiReportCancel => 'Cancel';

  @override
  String get activeHotkeys => 'Active Hotkeys';

  @override
  String get appProductName => 'SpeakOut · 子曰';

  @override
  String get aboutVersionCopyTip => 'Double-click to copy version';

  @override
  String get aboutVersionCopied => 'Copied';

  @override
  String get aboutUpdateDownload => 'Download Update';

  @override
  String get aboutPrivacyPolicy => 'Privacy Policy';

  @override
  String get clearHotkey => 'Clear hotkey';

  @override
  String get featureCorrection => 'Correction';

  @override
  String get featureAiReport => 'AI Debug';

  @override
  String get shortcutsAndDuration => 'Shortcuts & Duration';
}
