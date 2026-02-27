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
  /// **'Language'**
  String get language;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get langSystem;

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
  /// **'AI Smart Correction (Beta)'**
  String get aiCorrection;

  /// No description provided for @aiCorrectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Use LLM to remove filler words and polish text.'**
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
  /// **'Offline Models (High Accuracy)'**
  String get offlineModels;

  /// No description provided for @offlineModelsDesc.
  ///
  /// In en, this message translates to:
  /// **'Recognizes after recording stops. Higher accuracy, no real-time subtitles.'**
  String get offlineModelsDesc;

  /// No description provided for @switchToOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Offline Mode?'**
  String get switchToOfflineTitle;

  /// No description provided for @switchToOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Offline models recognize after you release the key — no real-time subtitles during recording. Accuracy is higher. Continue?'**
  String get switchToOfflineBody;

  /// No description provided for @switchToStreamingTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Streaming Mode?'**
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
  /// **'Offline'**
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
