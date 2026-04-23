import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SpeakOut · 子曰'**
  String get appTitle;

  /// No description provided for @tabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get tabGeneral;

  /// No description provided for @tabModels.
  ///
  /// In en, this message translates to:
  /// **'Voice Models'**
  String get tabModels;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Interface Language'**
  String get language;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get langSystem;

  /// No description provided for @inputLanguage.
  ///
  /// In en, this message translates to:
  /// **'Input Language'**
  String get inputLanguage;

  /// No description provided for @inputLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Language you speak'**
  String get inputLanguageDesc;

  /// No description provided for @outputLanguage.
  ///
  /// In en, this message translates to:
  /// **'Output Language'**
  String get outputLanguage;

  /// No description provided for @outputLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Language for text output. Auto-translates when different from input'**
  String get outputLanguageDesc;

  /// No description provided for @langAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get langAutoDetect;

  /// No description provided for @langFollowInput.
  ///
  /// In en, this message translates to:
  /// **'Follow input language'**
  String get langFollowInput;

  /// No description provided for @langZh.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get langZh;

  /// No description provided for @langZhHans.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get langZhHans;

  /// No description provided for @langZhHant.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get langZhHant;

  /// No description provided for @langEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEn;

  /// No description provided for @langJa.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get langJa;

  /// No description provided for @langKo.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get langKo;

  /// No description provided for @langYue.
  ///
  /// In en, this message translates to:
  /// **'Cantonese'**
  String get langYue;

  /// No description provided for @langEs.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get langEs;

  /// No description provided for @langFr.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get langFr;

  /// No description provided for @langDe.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get langDe;

  /// No description provided for @langRu.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get langRu;

  /// No description provided for @langPt.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get langPt;

  /// No description provided for @translationModeHint.
  ///
  /// In en, this message translates to:
  /// **'Translation Mode'**
  String get translationModeHint;

  /// No description provided for @translationNeedsSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Translation requires AI polish. Please switch to Smart Mode to enable it.'**
  String get translationNeedsSmartMode;

  /// No description provided for @translationCloudLimited.
  ///
  /// In en, this message translates to:
  /// **'Cloud mode has no AI polish. Translation quality will be limited. Recommend Smart Mode.'**
  String get translationCloudLimited;

  /// No description provided for @inputLangModelHint.
  ///
  /// In en, this message translates to:
  /// **'Current model has limited support for {lang}. Consider switching to Whisper Large-v3 for better recognition.'**
  String inputLangModelHint(Object lang);

  /// No description provided for @audioInput.
  ///
  /// In en, this message translates to:
  /// **'Audio Input Device'**
  String get audioInput;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @aiCorrection.
  ///
  /// In en, this message translates to:
  /// **'AI Polish'**
  String get aiCorrection;

  /// No description provided for @aiCorrectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Use LLM to polish speech recognition results.'**
  String get aiCorrectionDesc;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @apiConfig.
  ///
  /// In en, this message translates to:
  /// **'API Config (OpenAI Compatible)'**
  String get apiConfig;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPrompt;

  /// No description provided for @resetDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset Default'**
  String get resetDefault;

  /// No description provided for @triggerKey.
  ///
  /// In en, this message translates to:
  /// **'Trigger Key (PTT)'**
  String get triggerKey;

  /// No description provided for @triggerKeyDesc.
  ///
  /// In en, this message translates to:
  /// **'Hold key to speak, release to input. Supports all keys (incl. FN).'**
  String get triggerKeyDesc;

  /// No description provided for @pressAnyKey.
  ///
  /// In en, this message translates to:
  /// **'Press any key...'**
  String get pressAnyKey;

  /// No description provided for @activeEngine.
  ///
  /// In en, this message translates to:
  /// **'Active Voice Engine'**
  String get activeEngine;

  /// No description provided for @engineLocal.
  ///
  /// In en, this message translates to:
  /// **'🔒 Local Offline Model (Privacy)'**
  String get engineLocal;

  /// No description provided for @engineLocalDesc.
  ///
  /// In en, this message translates to:
  /// **'Fully offline, privacy protected. No internet required.'**
  String get engineLocalDesc;

  /// No description provided for @engineCloud.
  ///
  /// In en, this message translates to:
  /// **'☁️ Aliyun Smart Voice (Cloud)'**
  String get engineCloud;

  /// No description provided for @engineCloudDesc.
  ///
  /// In en, this message translates to:
  /// **'Higher accuracy via cloud. Requires API Key.'**
  String get engineCloudDesc;

  /// No description provided for @aliyunConfig.
  ///
  /// In en, this message translates to:
  /// **'Aliyun Config'**
  String get aliyunConfig;

  /// No description provided for @aliyunConfigDesc.
  ///
  /// In en, this message translates to:
  /// **'Get AccessKey and AppKey from Aliyun NLS Console.'**
  String get aliyunConfigDesc;

  /// No description provided for @saveApply.
  ///
  /// In en, this message translates to:
  /// **'Save & Apply'**
  String get saveApply;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading... {percent}%'**
  String downloading(Object percent);

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get preparing;

  /// No description provided for @unzipping.
  ///
  /// In en, this message translates to:
  /// **'Unzipping...'**
  String get unzipping;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @initializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get initializing;

  /// No description provided for @readyTip.
  ///
  /// In en, this message translates to:
  /// **'Hold {key} to speak'**
  String readyTip(Object key);

  /// No description provided for @recording.
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get recording;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @micError.
  ///
  /// In en, this message translates to:
  /// **'Mic Error'**
  String get micError;

  /// No description provided for @noSpeech.
  ///
  /// In en, this message translates to:
  /// **'No Speech Detected'**
  String get noSpeech;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @modelZipformerName.
  ///
  /// In en, this message translates to:
  /// **'Zipformer Bilingual (Recommended)'**
  String get modelZipformerName;

  /// No description provided for @modelZipformerDesc.
  ///
  /// In en, this message translates to:
  /// **'Balanced streaming model (Zh/En). Download: ~490MB'**
  String get modelZipformerDesc;

  /// No description provided for @modelParaformerName.
  ///
  /// In en, this message translates to:
  /// **'Paraformer Bilingual (Streaming)'**
  String get modelParaformerName;

  /// No description provided for @modelParaformerDesc.
  ///
  /// In en, this message translates to:
  /// **'High accuracy Zh/En streaming model with lookahead. ~1GB'**
  String get modelParaformerDesc;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @tabOrganize.
  ///
  /// In en, this message translates to:
  /// **'AI Organize'**
  String get tabOrganize;

  /// No description provided for @organizeEnabled.
  ///
  /// In en, this message translates to:
  /// **'AI Organize'**
  String get organizeEnabled;

  /// No description provided for @organizeHotkey.
  ///
  /// In en, this message translates to:
  /// **'Organize Hotkey'**
  String get organizeHotkey;

  /// No description provided for @organizeHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Select text then press this hotkey'**
  String get organizeHotkeyHint;

  /// No description provided for @organizePrompt.
  ///
  /// In en, this message translates to:
  /// **'Organize Instructions'**
  String get organizePrompt;

  /// No description provided for @organizeResetDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset Default'**
  String get organizeResetDefault;

  /// No description provided for @organizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Select any text and press the hotkey. AI will extract key points, restructure logic, and express professionally while preserving the original meaning.'**
  String get organizeDesc;

  /// No description provided for @organizeLlmHint.
  ///
  /// In en, this message translates to:
  /// **'Uses the LLM provider configured in Work Mode'**
  String get organizeLlmHint;

  /// No description provided for @organizeGoConfig.
  ///
  /// In en, this message translates to:
  /// **'Go to config →'**
  String get organizeGoConfig;

  /// No description provided for @tabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get tabAbout;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Your Local AI Speech Assistant'**
  String get aboutTagline;

  /// No description provided for @aboutSubTagline.
  ///
  /// In en, this message translates to:
  /// **'Secure. Fast. Offline.'**
  String get aboutSubTagline;

  /// No description provided for @aboutPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Powered by'**
  String get aboutPoweredBy;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright © 2026 Leon. All Rights Reserved.'**
  String get aboutCopyright;

  /// No description provided for @diaryMode.
  ///
  /// In en, this message translates to:
  /// **'Flash Note'**
  String get diaryMode;

  /// No description provided for @diaryTrigger.
  ///
  /// In en, this message translates to:
  /// **'Note Hotkey'**
  String get diaryTrigger;

  /// No description provided for @diaryPath.
  ///
  /// In en, this message translates to:
  /// **'Save Directory'**
  String get diaryPath;

  /// No description provided for @createFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get createFolder;

  /// No description provided for @folderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder Created'**
  String get folderCreated;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose File...'**
  String get chooseFile;

  /// No description provided for @diarySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to Note'**
  String get diarySaved;

  /// No description provided for @engineType.
  ///
  /// In en, this message translates to:
  /// **'Engine Type'**
  String get engineType;

  /// No description provided for @punctuationModel.
  ///
  /// In en, this message translates to:
  /// **'Punctuation Model'**
  String get punctuationModel;

  /// No description provided for @punctuationModelDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically adds punctuation to recognized text. This model is required.'**
  String get punctuationModelDesc;

  /// No description provided for @asrModels.
  ///
  /// In en, this message translates to:
  /// **'Speech Recognition Models'**
  String get asrModels;

  /// No description provided for @asrModelsDesc.
  ///
  /// In en, this message translates to:
  /// **'Please download and activate at least one ASR model to use voice input.'**
  String get asrModelsDesc;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @pickOne.
  ///
  /// In en, this message translates to:
  /// **'Pick One'**
  String get pickOne;

  /// No description provided for @llmProvider.
  ///
  /// In en, this message translates to:
  /// **'LLM Provider'**
  String get llmProvider;

  /// No description provided for @llmProviderCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud API'**
  String get llmProviderCloud;

  /// No description provided for @llmProviderOllama.
  ///
  /// In en, this message translates to:
  /// **'Ollama (Local)'**
  String get llmProviderOllama;

  /// No description provided for @ollamaUrl.
  ///
  /// In en, this message translates to:
  /// **'Ollama URL'**
  String get ollamaUrl;

  /// No description provided for @ollamaModel.
  ///
  /// In en, this message translates to:
  /// **'Model Name'**
  String get ollamaModel;

  /// No description provided for @permInputMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Input Monitoring'**
  String get permInputMonitoring;

  /// No description provided for @permInputMonitoringDesc.
  ///
  /// In en, this message translates to:
  /// **'For listening to hotkey triggers'**
  String get permInputMonitoringDesc;

  /// No description provided for @permAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get permAccessibility;

  /// No description provided for @permAccessibilityDesc.
  ///
  /// In en, this message translates to:
  /// **'For typing text into applications'**
  String get permAccessibilityDesc;

  /// No description provided for @streamingModels.
  ///
  /// In en, this message translates to:
  /// **'Streaming Models (Real-time)'**
  String get streamingModels;

  /// No description provided for @streamingModelsDesc.
  ///
  /// In en, this message translates to:
  /// **'Shows text in real-time as you speak. Best for long dictation.'**
  String get streamingModelsDesc;

  /// No description provided for @offlineModels.
  ///
  /// In en, this message translates to:
  /// **'Non-streaming Models (High Accuracy)'**
  String get offlineModels;

  /// No description provided for @offlineModelsDesc.
  ///
  /// In en, this message translates to:
  /// **'Recognizes after recording stops. Higher accuracy, no real-time subtitles.'**
  String get offlineModelsDesc;

  /// No description provided for @switchToOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Non-streaming Model?'**
  String get switchToOfflineTitle;

  /// No description provided for @switchToOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Non-streaming models recognize after you release the key — no real-time subtitles during recording. Accuracy is higher. Continue?'**
  String get switchToOfflineBody;

  /// No description provided for @switchToStreamingTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Streaming Model?'**
  String get switchToStreamingTitle;

  /// No description provided for @switchToStreamingBody.
  ///
  /// In en, this message translates to:
  /// **'Streaming models show text in real-time as you speak. Accuracy may be slightly lower. Continue?'**
  String get switchToStreamingBody;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @modelSenseVoiceName.
  ///
  /// In en, this message translates to:
  /// **'SenseVoice 2024 (Recommended)'**
  String get modelSenseVoiceName;

  /// No description provided for @modelSenseVoiceDesc.
  ///
  /// In en, this message translates to:
  /// **'Alibaba DAMO, Zh/En/Ja/Ko/Yue, built-in punctuation. ~228MB'**
  String get modelSenseVoiceDesc;

  /// No description provided for @modelSenseVoice2025Name.
  ///
  /// In en, this message translates to:
  /// **'SenseVoice 2025'**
  String get modelSenseVoice2025Name;

  /// No description provided for @modelSenseVoice2025Desc.
  ///
  /// In en, this message translates to:
  /// **'Cantonese enhanced, no built-in punctuation. ~158MB'**
  String get modelSenseVoice2025Desc;

  /// No description provided for @modelOfflineParaformerName.
  ///
  /// In en, this message translates to:
  /// **'Paraformer Offline'**
  String get modelOfflineParaformerName;

  /// No description provided for @modelOfflineParaformerDesc.
  ///
  /// In en, this message translates to:
  /// **'Zh/En, mature & stable. ~217MB'**
  String get modelOfflineParaformerDesc;

  /// No description provided for @modelParaformerDialectName.
  ///
  /// In en, this message translates to:
  /// **'Paraformer Dialect 2025'**
  String get modelParaformerDialectName;

  /// No description provided for @modelParaformerDialectDesc.
  ///
  /// In en, this message translates to:
  /// **'Zh/En + Sichuan/Chongqing dialects. ~218MB'**
  String get modelParaformerDialectDesc;

  /// No description provided for @modelWhisperName.
  ///
  /// In en, this message translates to:
  /// **'Whisper Large-v3'**
  String get modelWhisperName;

  /// No description provided for @modelWhisperDesc.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Whisper, great for Zh/En/Ja/Ko/Fr/De/Es/Ru + 90 more languages. ~1.0GB'**
  String get modelWhisperDesc;

  /// No description provided for @modelFireRedName.
  ///
  /// In en, this message translates to:
  /// **'FireRedASR Large'**
  String get modelFireRedName;

  /// No description provided for @modelFireRedDesc.
  ///
  /// In en, this message translates to:
  /// **'Zh/En + dialects, highest capacity. ~1.4GB'**
  String get modelFireRedDesc;

  /// No description provided for @builtInPunctuation.
  ///
  /// In en, this message translates to:
  /// **'Built-in punctuation'**
  String get builtInPunctuation;

  /// No description provided for @needsPunctuationModel.
  ///
  /// In en, this message translates to:
  /// **'Requires punctuation model'**
  String get needsPunctuationModel;

  /// No description provided for @recognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognizing...'**
  String get recognizing;

  /// No description provided for @modeStreaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get modeStreaming;

  /// No description provided for @modeOffline.
  ///
  /// In en, this message translates to:
  /// **'Non-streaming'**
  String get modeOffline;

  /// No description provided for @chooseModel.
  ///
  /// In en, this message translates to:
  /// **'Choose a Voice Model'**
  String get chooseModel;

  /// No description provided for @chooseModelDesc.
  ///
  /// In en, this message translates to:
  /// **'Select a model to download. You can change it later in Settings.'**
  String get chooseModelDesc;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @onboardingWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to SpeakOut'**
  String get onboardingWelcome;

  /// No description provided for @onboardingWelcomeDesc.
  ///
  /// In en, this message translates to:
  /// **'Hold a hotkey to speak, release to auto-type\nSupports multilingual recognition'**
  String get onboardingWelcomeDesc;

  /// No description provided for @onboardingStartSetup.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingStartSetup;

  /// No description provided for @onboardingPermTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions Required'**
  String get onboardingPermTitle;

  /// No description provided for @onboardingPermDesc.
  ///
  /// In en, this message translates to:
  /// **'SpeakOut needs the following permissions to work properly'**
  String get onboardingPermDesc;

  /// No description provided for @permMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permMicrophone;

  /// No description provided for @permMicrophoneDesc.
  ///
  /// In en, this message translates to:
  /// **'For recording voice for recognition'**
  String get permMicrophoneDesc;

  /// No description provided for @permGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get permGrant;

  /// No description provided for @permGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get permGranted;

  /// No description provided for @permRefreshStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh Status'**
  String get permRefreshStatus;

  /// No description provided for @permRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Granted? Restart app for permissions to take effect'**
  String get permRestartHint;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingGrantFirst.
  ///
  /// In en, this message translates to:
  /// **'Please grant permissions first'**
  String get onboardingGrantFirst;

  /// No description provided for @onboardingSetupLater.
  ///
  /// In en, this message translates to:
  /// **'Set up later'**
  String get onboardingSetupLater;

  /// No description provided for @onboardingCustomSelect.
  ///
  /// In en, this message translates to:
  /// **'Custom Selection'**
  String get onboardingCustomSelect;

  /// No description provided for @onboardingBrowseModels.
  ///
  /// In en, this message translates to:
  /// **'Browse all {count} models, including dialects and large models'**
  String onboardingBrowseModels(Object count);

  /// No description provided for @onboardingModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Zh/En/Ja/Ko/Yue, built-in punctuation, ~228MB'**
  String get onboardingModelSubtitle;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Voice Model'**
  String get onboardingDownloadTitle;

  /// No description provided for @onboardingDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}'**
  String onboardingDownloading(Object name);

  /// No description provided for @onboardingPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing download...'**
  String get onboardingPreparing;

  /// No description provided for @onboardingDownloadPunct.
  ///
  /// In en, this message translates to:
  /// **'Downloading punctuation model...'**
  String get onboardingDownloadPunct;

  /// No description provided for @onboardingDownloadPunctPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading punctuation model... {percent}%'**
  String onboardingDownloadPunctPercent(Object percent);

  /// No description provided for @onboardingDownloadASR.
  ///
  /// In en, this message translates to:
  /// **'Downloading ASR model...'**
  String get onboardingDownloadASR;

  /// No description provided for @onboardingDownloadASRPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading ASR model... {percent}%'**
  String onboardingDownloadASRPercent(Object percent);

  /// No description provided for @onboardingActivating.
  ///
  /// In en, this message translates to:
  /// **'Activating model...'**
  String get onboardingActivating;

  /// No description provided for @onboardingDownloadDone.
  ///
  /// In en, this message translates to:
  /// **'Download complete!'**
  String get onboardingDownloadDone;

  /// No description provided for @onboardingDownloadFail.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get onboardingDownloadFail;

  /// No description provided for @onboardingRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get onboardingRetry;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingStartDownload.
  ///
  /// In en, this message translates to:
  /// **'Start Download'**
  String get onboardingStartDownload;

  /// No description provided for @onboardingDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup Complete!'**
  String get onboardingDoneTitle;

  /// No description provided for @onboardingHoldToSpeak.
  ///
  /// In en, this message translates to:
  /// **'Hold to speak'**
  String get onboardingHoldToSpeak;

  /// No description provided for @onboardingDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'Release to auto-type at cursor position'**
  String get onboardingDoneDesc;

  /// No description provided for @onboardingBegin.
  ///
  /// In en, this message translates to:
  /// **'Start Using'**
  String get onboardingBegin;

  /// No description provided for @tabTrigger.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get tabTrigger;

  /// No description provided for @pttMode.
  ///
  /// In en, this message translates to:
  /// **'Hold to Speak (PTT)'**
  String get pttMode;

  /// No description provided for @toggleModeTip.
  ///
  /// In en, this message translates to:
  /// **'Tap to Toggle'**
  String get toggleModeTip;

  /// No description provided for @textInjection.
  ///
  /// In en, this message translates to:
  /// **'Text Input (IME)'**
  String get textInjection;

  /// No description provided for @recordingProtection.
  ///
  /// In en, this message translates to:
  /// **'Recording Protection'**
  String get recordingProtection;

  /// No description provided for @toggleMaxDuration.
  ///
  /// In en, this message translates to:
  /// **'Max Recording Duration'**
  String get toggleMaxDuration;

  /// No description provided for @toggleMaxDurationDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-stop when not manually stopped in tap-to-talk mode'**
  String get toggleMaxDurationDesc;

  /// No description provided for @toggleMaxNone.
  ///
  /// In en, this message translates to:
  /// **'No Limit'**
  String get toggleMaxNone;

  /// No description provided for @toggleMaxMin.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String toggleMaxMin(Object count);

  /// No description provided for @toggleHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to start, tap again to stop. If same key as PTT, hold >1s for PTT mode.'**
  String get toggleHint;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not Set'**
  String get notSet;

  /// No description provided for @importModel.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importModel;

  /// No description provided for @manualDownload.
  ///
  /// In en, this message translates to:
  /// **'Manual Download'**
  String get manualDownload;

  /// No description provided for @importModelDesc.
  ///
  /// In en, this message translates to:
  /// **'Select a downloaded .tar.bz2 model file'**
  String get importModelDesc;

  /// No description provided for @importing.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get importing;

  /// No description provided for @tabWorkMode.
  ///
  /// In en, this message translates to:
  /// **'Work Mode'**
  String get tabWorkMode;

  /// No description provided for @workModeOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode'**
  String get workModeOffline;

  /// No description provided for @workModeOfflineDesc.
  ///
  /// In en, this message translates to:
  /// **'Local Sherpa recognition, fully offline and private'**
  String get workModeOfflineDesc;

  /// No description provided for @workModeOfflineIcon.
  ///
  /// In en, this message translates to:
  /// **'Privacy-first, zero network dependency'**
  String get workModeOfflineIcon;

  /// No description provided for @workModeSmart.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get workModeSmart;

  /// No description provided for @workModeSmartDesc.
  ///
  /// In en, this message translates to:
  /// **'Local recognition + AI polish. Fixes homophones, removes filler words'**
  String get workModeSmartDesc;

  /// No description provided for @workModeCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud Recognition'**
  String get workModeCloud;

  /// No description provided for @workModeCloudDesc.
  ///
  /// In en, this message translates to:
  /// **'Cloud high-accuracy recognition, requires internet'**
  String get workModeCloudDesc;

  /// No description provided for @workModeSmartConfig.
  ///
  /// In en, this message translates to:
  /// **'Smart Polish Config'**
  String get workModeSmartConfig;

  /// No description provided for @workModeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get workModeAdvanced;

  /// No description provided for @tabAiPolish.
  ///
  /// In en, this message translates to:
  /// **'AI Polish'**
  String get tabAiPolish;

  /// No description provided for @aiPolishDesc.
  ///
  /// In en, this message translates to:
  /// **'Use LLM to polish speech results with professional vocabulary context.'**
  String get aiPolishDesc;

  /// No description provided for @vocabEnhancement.
  ///
  /// In en, this message translates to:
  /// **'Professional Vocab'**
  String get vocabEnhancement;

  /// No description provided for @vocabEnhancementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Provide terminology hints to AI for better domain recognition'**
  String get vocabEnhancementSubtitle;

  /// No description provided for @vocabEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Professional Vocab'**
  String get vocabEnabled;

  /// No description provided for @vocabIndustryPresets.
  ///
  /// In en, this message translates to:
  /// **'Industry Preset Dictionaries'**
  String get vocabIndustryPresets;

  /// No description provided for @vocabCustomVocab.
  ///
  /// In en, this message translates to:
  /// **'Personal Dictionary'**
  String get vocabCustomVocab;

  /// No description provided for @vocabCustomEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Personal Dictionary'**
  String get vocabCustomEnabled;

  /// No description provided for @vocabAddEntry.
  ///
  /// In en, this message translates to:
  /// **'Add Entry'**
  String get vocabAddEntry;

  /// No description provided for @vocabWrongForm.
  ///
  /// In en, this message translates to:
  /// **'Wrong form (ASR output)'**
  String get vocabWrongForm;

  /// No description provided for @vocabCorrectForm.
  ///
  /// In en, this message translates to:
  /// **'Correct form'**
  String get vocabCorrectForm;

  /// No description provided for @vocabDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get vocabDelete;

  /// No description provided for @vocabTech.
  ///
  /// In en, this message translates to:
  /// **'Software/IT'**
  String get vocabTech;

  /// No description provided for @vocabMedical.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get vocabMedical;

  /// No description provided for @vocabLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get vocabLegal;

  /// No description provided for @vocabFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get vocabFinance;

  /// No description provided for @vocabEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get vocabEducation;

  /// No description provided for @vocabEnabledNote.
  ///
  /// In en, this message translates to:
  /// **'When enabled, terminology is injected as context hints to AI Polish'**
  String get vocabEnabledNote;

  /// No description provided for @vocabBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get vocabBeta;

  /// No description provided for @vocabBetaNote.
  ///
  /// In en, this message translates to:
  /// **'Experimental — accuracy varies by LLM model, still being tuned'**
  String get vocabBetaNote;

  /// No description provided for @vocabImportTsv.
  ///
  /// In en, this message translates to:
  /// **'Import File'**
  String get vocabImportTsv;

  /// No description provided for @vocabImportTsvDesc.
  ///
  /// In en, this message translates to:
  /// **'TSV or CSV format, one entry per line: wrong<Tab>correct'**
  String get vocabImportTsvDesc;

  /// No description provided for @vocabImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} entries imported'**
  String vocabImportSuccess(Object count);

  /// No description provided for @vocabImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String vocabImportFailed(Object error);

  /// No description provided for @vocabExportTsv.
  ///
  /// In en, this message translates to:
  /// **'Export File'**
  String get vocabExportTsv;

  /// No description provided for @aiPolishWarning.
  ///
  /// In en, this message translates to:
  /// **'AI Polish may alter meaning or introduce errors. Verify important text against the original. With AI off, raw ASR output is used — accuracy depends on the voice model.'**
  String get aiPolishWarning;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version {version} available'**
  String updateAvailable(Object version);

  /// No description provided for @updateAction.
  ///
  /// In en, this message translates to:
  /// **'View Update'**
  String get updateAction;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get updateUpToDate;

  /// No description provided for @llmRewrite.
  ///
  /// In en, this message translates to:
  /// **'LLM Rewrite'**
  String get llmRewrite;

  /// No description provided for @aiPolishMatrix.
  ///
  /// In en, this message translates to:
  /// **'LLM ✓ + Vocab ✓ → Terms injected into LLM for smart correction\nLLM ✓ + Vocab ✗ → Pure LLM polish\nLLM ✗ + Vocab ✓ → Dictionary exact replacement (works offline)\nLLM ✗ + Vocab ✗ → Raw ASR output'**
  String get aiPolishMatrix;

  /// No description provided for @tabCloudAccounts.
  ///
  /// In en, this message translates to:
  /// **'Cloud Accounts'**
  String get tabCloudAccounts;

  /// No description provided for @cloudAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Cloud Accounts'**
  String get cloudAccountsTitle;

  /// No description provided for @cloudAccountAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Provider'**
  String get cloudAccountAdd;

  /// No description provided for @cloudAccountEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get cloudAccountEdit;

  /// No description provided for @cloudAccountDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get cloudAccountDelete;

  /// No description provided for @cloudAccountCapabilityAsr.
  ///
  /// In en, this message translates to:
  /// **'Speech Recognition'**
  String get cloudAccountCapabilityAsr;

  /// No description provided for @cloudAccountCapabilityLlm.
  ///
  /// In en, this message translates to:
  /// **'AI Polish'**
  String get cloudAccountCapabilityLlm;

  /// No description provided for @cloudAccountNone.
  ///
  /// In en, this message translates to:
  /// **'No accounts configured'**
  String get cloudAccountNone;

  /// No description provided for @cloudAccountSelectAsr.
  ///
  /// In en, this message translates to:
  /// **'Select ASR Service'**
  String get cloudAccountSelectAsr;

  /// No description provided for @cloudAccountSelectLlm.
  ///
  /// In en, this message translates to:
  /// **'Select LLM Service'**
  String get cloudAccountSelectLlm;

  /// No description provided for @cloudAccountGoConfig.
  ///
  /// In en, this message translates to:
  /// **'Go to Cloud Accounts'**
  String get cloudAccountGoConfig;

  /// No description provided for @cloudAccountSaved.
  ///
  /// In en, this message translates to:
  /// **'Account saved'**
  String get cloudAccountSaved;

  /// No description provided for @cloudAccountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get cloudAccountDeleted;

  /// No description provided for @cloudAccountDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this account?'**
  String get cloudAccountDeleteConfirm;

  /// No description provided for @cloudAccountProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get cloudAccountProvider;

  /// No description provided for @cloudAccountName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get cloudAccountName;

  /// No description provided for @cloudAccountEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get cloudAccountEnabled;

  /// No description provided for @languageSettings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettings;

  /// No description provided for @translationDisabledReason.
  ///
  /// In en, this message translates to:
  /// **'Translation requires AI polish, only available in Smart Mode'**
  String get translationDisabledReason;

  /// No description provided for @cloudAsrLangUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Current cloud ASR service only supports Chinese and English. Selected language will fall back to Chinese recognition.'**
  String get cloudAsrLangUnsupported;

  /// No description provided for @quickTranslate.
  ///
  /// In en, this message translates to:
  /// **'Quick Translate'**
  String get quickTranslate;

  /// No description provided for @quickTranslateDesc.
  ///
  /// In en, this message translates to:
  /// **'Press hotkey to record, result auto-translates to target language (does not affect normal recording settings)'**
  String get quickTranslateDesc;

  /// No description provided for @translateTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target Language'**
  String get translateTargetLanguage;

  /// No description provided for @translateHotkey.
  ///
  /// In en, this message translates to:
  /// **'Translate Hotkey'**
  String get translateHotkey;

  /// No description provided for @translateNoLlm.
  ///
  /// In en, this message translates to:
  /// **'Quick Translate requires an LLM service. Please add one in Cloud Accounts.'**
  String get translateNoLlm;

  /// No description provided for @settingsV18PreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsV18PreviewTitle;

  /// No description provided for @sidebarSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get sidebarSectionBasic;

  /// No description provided for @sidebarSectionVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get sidebarSectionVoice;

  /// No description provided for @sidebarSectionSuperpower.
  ///
  /// In en, this message translates to:
  /// **'Superpower'**
  String get sidebarSectionSuperpower;

  /// No description provided for @sidebarSectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get sidebarSectionOther;

  /// No description provided for @sidebarOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get sidebarOverview;

  /// No description provided for @sidebarShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get sidebarShortcuts;

  /// No description provided for @sidebarPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get sidebarPermissions;

  /// No description provided for @sidebarRecognition.
  ///
  /// In en, this message translates to:
  /// **'Recognition'**
  String get sidebarRecognition;

  /// No description provided for @sidebarAiPlus.
  ///
  /// In en, this message translates to:
  /// **'AI Plus'**
  String get sidebarAiPlus;

  /// No description provided for @sidebarVocab.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get sidebarVocab;

  /// No description provided for @sidebarCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get sidebarCorrection;

  /// No description provided for @sidebarAiReport.
  ///
  /// In en, this message translates to:
  /// **'AI Debug'**
  String get sidebarAiReport;

  /// No description provided for @sidebarDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get sidebarDeveloper;

  /// No description provided for @showAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get showAdvanced;

  /// No description provided for @shortcutsRecordKey.
  ///
  /// In en, this message translates to:
  /// **'Record Key'**
  String get shortcutsRecordKey;

  /// No description provided for @shortcutsSharedHint.
  ///
  /// In en, this message translates to:
  /// **'Tap = toggle recording, Hold = push-to-talk'**
  String get shortcutsSharedHint;

  /// No description provided for @shortcutsSplitTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Key (PTT / Toggle separately)'**
  String get shortcutsSplitTitle;

  /// No description provided for @shortcutsPttTitle.
  ///
  /// In en, this message translates to:
  /// **'Push-to-Talk (PTT)'**
  String get shortcutsPttTitle;

  /// No description provided for @shortcutsPttHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to record, release to stop'**
  String get shortcutsPttHint;

  /// No description provided for @shortcutsToggleTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to Talk'**
  String get shortcutsToggleTitle;

  /// No description provided for @shortcutsToggleHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to start, tap again to stop'**
  String get shortcutsToggleHint;

  /// No description provided for @shortcutsTip.
  ///
  /// In en, this message translates to:
  /// **'Recommended: Right Option / Fn / F13–F19 — Cmd / Ctrl combos are often taken by system apps.'**
  String get shortcutsTip;

  /// No description provided for @hotkeyModalTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Hotkey'**
  String get hotkeyModalTitle;

  /// No description provided for @hotkeyModalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Press the key or combination you want to set'**
  String get hotkeyModalSubtitle;

  /// No description provided for @hotkeyModalCountdown.
  ///
  /// In en, this message translates to:
  /// **'Cancels in {seconds}s · Press ESC to exit'**
  String hotkeyModalCountdown(int seconds);

  /// No description provided for @hotkeyModalRecommend.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get hotkeyModalRecommend;

  /// No description provided for @hotkeyModalAvoid.
  ///
  /// In en, this message translates to:
  /// **'Avoid Cmd / Ctrl combinations (often taken by system apps)'**
  String get hotkeyModalAvoid;

  /// No description provided for @hotkeyInUseTitle.
  ///
  /// In en, this message translates to:
  /// **'{keyName} is already used by \"{feature}\"'**
  String hotkeyInUseTitle(String keyName, String feature);

  /// No description provided for @hotkeyInUseMessage.
  ///
  /// In en, this message translates to:
  /// **'That key is taken. Please choose another.'**
  String get hotkeyInUseMessage;

  /// No description provided for @hotkeyInUseOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get hotkeyInUseOk;

  /// No description provided for @hotkeyRecordDiary.
  ///
  /// In en, this message translates to:
  /// **'Record Flash Note Key'**
  String get hotkeyRecordDiary;

  /// No description provided for @hotkeyRecordDiaryHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to start recording a note'**
  String get hotkeyRecordDiaryHint;

  /// No description provided for @hotkeyRecordToggleDiary.
  ///
  /// In en, this message translates to:
  /// **'Record Note Toggle Key'**
  String get hotkeyRecordToggleDiary;

  /// No description provided for @hotkeyRecordToggleDiaryHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to start, tap again to stop'**
  String get hotkeyRecordToggleDiaryHint;

  /// No description provided for @hotkeyRecordOrganize.
  ///
  /// In en, this message translates to:
  /// **'Record AI Organize Key'**
  String get hotkeyRecordOrganize;

  /// No description provided for @hotkeyRecordOrganizeHint.
  ///
  /// In en, this message translates to:
  /// **'After selecting text, press to reorganize'**
  String get hotkeyRecordOrganizeHint;

  /// No description provided for @hotkeyRecordTranslate.
  ///
  /// In en, this message translates to:
  /// **'Record Quick Translate Key'**
  String get hotkeyRecordTranslate;

  /// No description provided for @hotkeyRecordTranslateHint.
  ///
  /// In en, this message translates to:
  /// **'After selecting text, press to translate'**
  String get hotkeyRecordTranslateHint;

  /// No description provided for @hotkeyRecordCorrection.
  ///
  /// In en, this message translates to:
  /// **'Record Correction Key'**
  String get hotkeyRecordCorrection;

  /// No description provided for @hotkeyRecordCorrectionHint.
  ///
  /// In en, this message translates to:
  /// **'After selecting text, press to submit correction'**
  String get hotkeyRecordCorrectionHint;

  /// No description provided for @hotkeyRecordAiReport.
  ///
  /// In en, this message translates to:
  /// **'Record AI Debug Base Key'**
  String get hotkeyRecordAiReport;

  /// No description provided for @hotkeyRecordAiReportHint.
  ///
  /// In en, this message translates to:
  /// **'Hold + digit 1-5 to activate'**
  String get hotkeyRecordAiReportHint;

  /// No description provided for @overviewWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to SpeakOut'**
  String get overviewWelcome;

  /// No description provided for @overviewTagline.
  ///
  /// In en, this message translates to:
  /// **'macOS offline-first AI dictation · Private · Free & Open'**
  String get overviewTagline;

  /// No description provided for @overviewGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get overviewGetStarted;

  /// No description provided for @featureOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline Recognition'**
  String get featureOfflineTitle;

  /// No description provided for @featureOfflineDesc.
  ///
  /// In en, this message translates to:
  /// **'Local Sherpa-ONNX ASR, on-device; accuracy rivals cloud'**
  String get featureOfflineDesc;

  /// No description provided for @featureAiPolishTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Polish'**
  String get featureAiPolishTitle;

  /// No description provided for @featureAiPolishDesc.
  ///
  /// In en, this message translates to:
  /// **'Cloud LLM fixes homophones, punctuation, and grammar'**
  String get featureAiPolishDesc;

  /// No description provided for @featureSuperpowerTitle.
  ///
  /// In en, this message translates to:
  /// **'Superpower'**
  String get featureSuperpowerTitle;

  /// No description provided for @featureSuperpowerDesc.
  ///
  /// In en, this message translates to:
  /// **'Flash Note / AI Organize / Quick Translate / Correction / AI Debug'**
  String get featureSuperpowerDesc;

  /// No description provided for @featureVocabTitle.
  ///
  /// In en, this message translates to:
  /// **'Professional Vocab'**
  String get featureVocabTitle;

  /// No description provided for @featureVocabDesc.
  ///
  /// In en, this message translates to:
  /// **'Custom terms injected into LLM prompt; medical / legal / finance packs'**
  String get featureVocabDesc;

  /// No description provided for @overviewHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get overviewHelpTitle;

  /// No description provided for @linkWikiFaq.
  ///
  /// In en, this message translates to:
  /// **'Wiki · FAQ'**
  String get linkWikiFaq;

  /// No description provided for @linkChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get linkChangelog;

  /// No description provided for @linkXHandle.
  ///
  /// In en, this message translates to:
  /// **'X · @4over7'**
  String get linkXHandle;

  /// No description provided for @linkFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback · 4over7@gmail.com'**
  String get linkFeedback;

  /// No description provided for @linkGithubIssues.
  ///
  /// In en, this message translates to:
  /// **'GitHub Issues'**
  String get linkGithubIssues;

  /// No description provided for @smartNeedsAiPlusConfig.
  ///
  /// In en, this message translates to:
  /// **'Smart mode needs LLM configured in \"AI Plus\" (provider / model / API key), otherwise AI polish won\'t apply.'**
  String get smartNeedsAiPlusConfig;

  /// No description provided for @gotoAiPlus.
  ///
  /// In en, this message translates to:
  /// **'Go to AI Plus'**
  String get gotoAiPlus;

  /// No description provided for @aiPlusNotActive.
  ///
  /// In en, this message translates to:
  /// **'AI Polish is not active: switch work mode to Smart (offline + cloud AI) in \"Recognition\". You can still edit LLM config here.'**
  String get aiPlusNotActive;

  /// No description provided for @aboutModelsDir.
  ///
  /// In en, this message translates to:
  /// **'Models Directory'**
  String get aboutModelsDir;

  /// No description provided for @aboutSystemLog.
  ///
  /// In en, this message translates to:
  /// **'Export Log Bundle'**
  String get aboutSystemLog;

  /// No description provided for @aboutSystemLogDesc.
  ///
  /// In en, this message translates to:
  /// **'Bundle last 10min system logs + app verbose logs + diagnostics into a zip (attach when reporting bugs)'**
  String get aboutSystemLogDesc;

  /// No description provided for @aboutSystemLogExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get aboutSystemLogExport;

  /// No description provided for @aboutSystemLogFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Log Bundle'**
  String get aboutSystemLogFileTitle;

  /// No description provided for @aboutSystemLogSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String aboutSystemLogSuccess(String path);

  /// No description provided for @diaryBullet1.
  ///
  /// In en, this message translates to:
  /// **'Tap shortcut to start, release to auto-save — no flow break'**
  String get diaryBullet1;

  /// No description provided for @diaryBullet2.
  ///
  /// In en, this message translates to:
  /// **'Notes named by date, saved as Markdown files for easy search'**
  String get diaryBullet2;

  /// No description provided for @diaryBullet3.
  ///
  /// In en, this message translates to:
  /// **'Pure local storage, syncs with Obsidian / Notion / iCloud'**
  String get diaryBullet3;

  /// No description provided for @organizeBullet1.
  ///
  /// In en, this message translates to:
  /// **'Select messy text, press key, LLM restructures it'**
  String get organizeBullet1;

  /// No description provided for @organizeBullet2.
  ///
  /// In en, this message translates to:
  /// **'Result appended below original, never overwrites'**
  String get organizeBullet2;

  /// No description provided for @organizeBullet3.
  ///
  /// In en, this message translates to:
  /// **'Uses the same LLM configured in AI Plus — no duplicate setup'**
  String get organizeBullet3;

  /// No description provided for @translateBullet1.
  ///
  /// In en, this message translates to:
  /// **'Press key to record, auto-translate to target language'**
  String get translateBullet1;

  /// No description provided for @translateBullet2.
  ///
  /// In en, this message translates to:
  /// **'Result injected into current text field, no copy-paste needed'**
  String get translateBullet2;

  /// No description provided for @translateBullet3.
  ///
  /// In en, this message translates to:
  /// **'Supports 11 languages incl. Chinese, English, Japanese, Korean'**
  String get translateBullet3;

  /// No description provided for @correctionBullet1.
  ///
  /// In en, this message translates to:
  /// **'Select corrected text, submit once — ASR learns your wording'**
  String get correctionBullet1;

  /// No description provided for @correctionBullet2.
  ///
  /// In en, this message translates to:
  /// **'LLM extracts word-level diffs, auto-adds to personal vocab'**
  String get correctionBullet2;

  /// No description provided for @correctionBullet3.
  ///
  /// In en, this message translates to:
  /// **'No manual dictionary editing — recognition improves over time'**
  String get correctionBullet3;

  /// No description provided for @aiReportBullet1.
  ///
  /// In en, this message translates to:
  /// **'Screenshot + voice description, one-tap to AI coding assistants'**
  String get aiReportBullet1;

  /// No description provided for @aiReportBullet2.
  ///
  /// In en, this message translates to:
  /// **'Bind multiple target windows (Claude Code / Cursor / ChatGPT)'**
  String get aiReportBullet2;

  /// No description provided for @aiReportBullet3.
  ///
  /// In en, this message translates to:
  /// **'Hold base key + digit to switch target window quickly'**
  String get aiReportBullet3;

  /// No description provided for @aboutSystemLogFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {err}'**
  String aboutSystemLogFailed(String err);

  /// No description provided for @aboutDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get aboutDiagnostics;

  /// No description provided for @aboutDiagnosticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Copy version / config / paths to clipboard (paste when reporting bugs)'**
  String get aboutDiagnosticsDesc;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get actionCopied;

  /// No description provided for @permissionsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'System Permissions'**
  String get permissionsSectionTitle;

  /// No description provided for @permissionsReauthTip.
  ///
  /// In en, this message translates to:
  /// **'If shortcuts stop working after a code-signing change, re-grant each permission below.'**
  String get permissionsReauthTip;

  /// No description provided for @permissionsAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get permissionsAccessibility;

  /// No description provided for @permissionsAccessibilityDesc.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts + text injection'**
  String get permissionsAccessibilityDesc;

  /// No description provided for @permissionsInputMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Input Monitoring'**
  String get permissionsInputMonitoring;

  /// No description provided for @permissionsInputMonitoringDesc.
  ///
  /// In en, this message translates to:
  /// **'Keyboard-triggered recording'**
  String get permissionsInputMonitoringDesc;

  /// No description provided for @permissionsMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permissionsMicrophone;

  /// No description provided for @permissionsMicrophoneDesc.
  ///
  /// In en, this message translates to:
  /// **'Audio capture'**
  String get permissionsMicrophoneDesc;

  /// No description provided for @permissionsOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get permissionsOpen;

  /// No description provided for @aboutDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get aboutDeveloper;

  /// No description provided for @aboutVerboseLogging.
  ///
  /// In en, this message translates to:
  /// **'Verbose Logging'**
  String get aboutVerboseLogging;

  /// No description provided for @aboutLogDir.
  ///
  /// In en, this message translates to:
  /// **'Log Directory'**
  String get aboutLogDir;

  /// No description provided for @aboutLogDirUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set (console only)'**
  String get aboutLogDirUnset;

  /// No description provided for @aboutLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get aboutLoading;

  /// No description provided for @aboutConfigBackup.
  ///
  /// In en, this message translates to:
  /// **'Config Backup'**
  String get aboutConfigBackup;

  /// No description provided for @aboutExportConfig.
  ///
  /// In en, this message translates to:
  /// **'Export Config'**
  String get aboutExportConfig;

  /// No description provided for @aboutExportConfigDesc.
  ///
  /// In en, this message translates to:
  /// **'Export all settings and credentials to file (plaintext keys included, store safely)'**
  String get aboutExportConfigDesc;

  /// No description provided for @aboutExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get aboutExportAction;

  /// No description provided for @aboutExportFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Config File'**
  String get aboutExportFileTitle;

  /// No description provided for @aboutImportConfig.
  ///
  /// In en, this message translates to:
  /// **'Import Config'**
  String get aboutImportConfig;

  /// No description provided for @aboutImportConfigDesc.
  ///
  /// In en, this message translates to:
  /// **'Restore all settings from a backup file, takes effect immediately'**
  String get aboutImportConfigDesc;

  /// No description provided for @aboutImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get aboutImportAction;

  /// No description provided for @aboutImportFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Config File'**
  String get aboutImportFileTitle;

  /// No description provided for @aboutExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported: {msg}'**
  String aboutExportSuccess(String msg);

  /// No description provided for @aboutExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {err}'**
  String aboutExportFailed(String err);

  /// No description provided for @aboutImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'{msg}, config applied'**
  String aboutImportSuccess(String msg);

  /// No description provided for @aboutImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {err}'**
  String aboutImportFailed(String err);

  /// No description provided for @audioDeviceCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: {name}'**
  String audioDeviceCurrent(String name);

  /// No description provided for @bluetoothMicWarning.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth mic may reduce quality'**
  String get bluetoothMicWarning;

  /// No description provided for @switchToBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Switch to built-in'**
  String get switchToBuiltin;

  /// No description provided for @autoOptimizeAudio.
  ///
  /// In en, this message translates to:
  /// **'Auto-optimize audio'**
  String get autoOptimizeAudio;

  /// No description provided for @autoOptimizeAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-switch to higher-quality mic when Bluetooth headset is connected'**
  String get autoOptimizeAudioDesc;

  /// No description provided for @hotkeyConflictTaken.
  ///
  /// In en, this message translates to:
  /// **'That key is taken. Please choose another.'**
  String get hotkeyConflictTaken;

  /// No description provided for @hotkeyConflictAutoClearTitle.
  ///
  /// In en, this message translates to:
  /// **'{keyName} is taken by \"{feature}\"'**
  String hotkeyConflictAutoClearTitle(String keyName, String feature);

  /// No description provided for @hotkeyConflictAutoClearMsg.
  ///
  /// In en, this message translates to:
  /// **'The hotkey has been cleared. Please set a new one.'**
  String get hotkeyConflictAutoClearMsg;

  /// No description provided for @modelActivateFailed.
  ///
  /// In en, this message translates to:
  /// **'Model activation failed: {err}'**
  String modelActivateFailed(String err);

  /// No description provided for @punctAutoLoaded.
  ///
  /// In en, this message translates to:
  /// **'Punctuation model auto-loaded'**
  String get punctAutoLoaded;

  /// No description provided for @punctMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'This model has no punctuation'**
  String get punctMissingTitle;

  /// No description provided for @punctMissingMsg.
  ///
  /// In en, this message translates to:
  /// **'This model outputs text without punctuation. Consider downloading the punctuation model for better readability.\n\nDownload now?'**
  String get punctMissingMsg;

  /// No description provided for @punctDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get punctDownload;

  /// No description provided for @punctSkip.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get punctSkip;

  /// No description provided for @offlineDataLocal.
  ///
  /// In en, this message translates to:
  /// **'All data is processed locally; nothing is uploaded'**
  String get offlineDataLocal;

  /// No description provided for @asrModel.
  ///
  /// In en, this message translates to:
  /// **'ASR Model'**
  String get asrModel;

  /// No description provided for @manageCloudAccounts.
  ///
  /// In en, this message translates to:
  /// **'Manage Cloud Accounts'**
  String get manageCloudAccounts;

  /// No description provided for @typewriterEffect.
  ///
  /// In en, this message translates to:
  /// **'Typewriter Effect'**
  String get typewriterEffect;

  /// No description provided for @ollamaServerRequired.
  ///
  /// In en, this message translates to:
  /// **'Make sure Ollama is running (ollama serve)'**
  String get ollamaServerRequired;

  /// No description provided for @manageModels.
  ///
  /// In en, this message translates to:
  /// **'Manage Models'**
  String get manageModels;

  /// No description provided for @llmRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get llmRecommendations;

  /// No description provided for @llmTagFastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get llmTagFastest;

  /// No description provided for @llmTagStable.
  ///
  /// In en, this message translates to:
  /// **'Stable Pick'**
  String get llmTagStable;

  /// No description provided for @llmTagFastestNote.
  ///
  /// In en, this message translates to:
  /// **'May fluctuate at peak'**
  String get llmTagFastestNote;

  /// No description provided for @llmTagStableNote.
  ///
  /// In en, this message translates to:
  /// **'Least fluctuation, stable quality'**
  String get llmTagStableNote;

  /// No description provided for @llmDataSource.
  ///
  /// In en, this message translates to:
  /// **'Source: 2026-03-21 benchmark, non-streaming API, China Mainland network'**
  String get llmDataSource;

  /// No description provided for @llmModelField.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get llmModelField;

  /// No description provided for @llmModelCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom...'**
  String get llmModelCustom;

  /// No description provided for @llmModelNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get llmModelNamePlaceholder;

  /// No description provided for @diaryDirNotSet.
  ///
  /// In en, this message translates to:
  /// **'No save directory set'**
  String get diaryDirNotSet;

  /// No description provided for @diaryDirCannotWrite.
  ///
  /// In en, this message translates to:
  /// **'Cannot write to this directory, please reselect (macOS requires re-authorization)'**
  String get diaryDirCannotWrite;

  /// No description provided for @diaryDirPick.
  ///
  /// In en, this message translates to:
  /// **'Please select a save directory to grant access'**
  String get diaryDirPick;

  /// No description provided for @diaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Record ideas anywhere with voice, auto-saved as Markdown diary.'**
  String get diaryDesc;

  /// No description provided for @organizeCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get organizeCollapse;

  /// No description provided for @organizeEditInstruction.
  ///
  /// In en, this message translates to:
  /// **'Edit Prompt'**
  String get organizeEditInstruction;

  /// No description provided for @correctionHotkey.
  ///
  /// In en, this message translates to:
  /// **'Correction Hotkey'**
  String get correctionHotkey;

  /// No description provided for @correctionExportDialog.
  ///
  /// In en, this message translates to:
  /// **'Export Correction Data'**
  String get correctionExportDialog;

  /// No description provided for @correctionImportDialog.
  ///
  /// In en, this message translates to:
  /// **'Import Correction Data'**
  String get correctionImportDialog;

  /// No description provided for @correctionExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get correctionExportSuccess;

  /// No description provided for @correctionExportFailedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Export failed: no data'**
  String get correctionExportFailedEmpty;

  /// No description provided for @correctionImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} entries (vocab synced)'**
  String correctionImportSuccess(int count);

  /// No description provided for @correctionExportBtn.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get correctionExportBtn;

  /// No description provided for @correctionImportBtn.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get correctionImportBtn;

  /// No description provided for @correctionDesc.
  ///
  /// In en, this message translates to:
  /// **'Select the corrected text and submit. ASR learns your wording over time.'**
  String get correctionDesc;

  /// No description provided for @aiReportBaseKey.
  ///
  /// In en, this message translates to:
  /// **'Base Key'**
  String get aiReportBaseKey;

  /// No description provided for @aiReportBaseKeyDesc.
  ///
  /// In en, this message translates to:
  /// **'Hold {baseKeyName} + digit (1–{slotCount}) to pick target window'**
  String aiReportBaseKeyDesc(String baseKeyName, int slotCount);

  /// No description provided for @aiReportAddFirstWindow.
  ///
  /// In en, this message translates to:
  /// **'Add First Window'**
  String get aiReportAddFirstWindow;

  /// No description provided for @aiReportAddWindow.
  ///
  /// In en, this message translates to:
  /// **'Add Window'**
  String get aiReportAddWindow;

  /// No description provided for @aiReportDescShort.
  ///
  /// In en, this message translates to:
  /// **'Built for AI Coding — screenshot + voice auto-sent to bound window'**
  String get aiReportDescShort;

  /// No description provided for @aiReportDescLong.
  ///
  /// In en, this message translates to:
  /// **'Built for AI Coding — screenshot + voice description, one-tap send to Claude Code / Cursor.'**
  String get aiReportDescLong;

  /// No description provided for @aiReportSwitchWindow.
  ///
  /// In en, this message translates to:
  /// **'Switch to target window...'**
  String get aiReportSwitchWindow;

  /// No description provided for @aiReportUnbound.
  ///
  /// In en, this message translates to:
  /// **'Unbound'**
  String get aiReportUnbound;

  /// No description provided for @aiReportBindTitle.
  ///
  /// In en, this message translates to:
  /// **'Bind AI Tool Window'**
  String get aiReportBindTitle;

  /// No description provided for @aiReportBindMsg.
  ///
  /// In en, this message translates to:
  /// **'After clicking \"Start\", you have 3 seconds to switch to the target window.'**
  String get aiReportBindMsg;

  /// No description provided for @aiReportStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get aiReportStart;

  /// No description provided for @aiReportCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get aiReportCancel;

  /// No description provided for @activeHotkeys.
  ///
  /// In en, this message translates to:
  /// **'Active Hotkeys'**
  String get activeHotkeys;

  /// No description provided for @appProductName.
  ///
  /// In en, this message translates to:
  /// **'SpeakOut · 子曰'**
  String get appProductName;

  /// No description provided for @aboutVersionCopyTip.
  ///
  /// In en, this message translates to:
  /// **'Double-click to copy version'**
  String get aboutVersionCopyTip;

  /// No description provided for @aboutVersionCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get aboutVersionCopied;

  /// No description provided for @aboutUpdateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download Update'**
  String get aboutUpdateDownload;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @clearHotkey.
  ///
  /// In en, this message translates to:
  /// **'Clear hotkey'**
  String get clearHotkey;

  /// No description provided for @featureCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get featureCorrection;

  /// No description provided for @featureAiReport.
  ///
  /// In en, this message translates to:
  /// **'AI Debug'**
  String get featureAiReport;

  /// No description provided for @shortcutsAndDuration.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts & Duration'**
  String get shortcutsAndDuration;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
