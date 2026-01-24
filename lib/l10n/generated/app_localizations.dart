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
  /// **'Balanced streaming model (Zh/En). ~85MB'**
  String get modelZipformerDesc;

  /// No description provided for @modelParaformerName.
  ///
  /// In en, this message translates to:
  /// **'Paraformer Bilingual (Streaming)'**
  String get modelParaformerName;

  /// No description provided for @modelParaformerDesc.
  ///
  /// In en, this message translates to:
  /// **'High accuracy Zh/En streaming model. ~230MB'**
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
