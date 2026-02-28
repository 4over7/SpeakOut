// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '子曰 · SpeakOut';

  @override
  String get tabGeneral => '通用';

  @override
  String get tabModels => '语音模型';

  @override
  String get language => '语言 (Language)';

  @override
  String get langSystem => '跟随系统 (System Default)';

  @override
  String get audioInput => '音频输入设备 (Audio Input)';

  @override
  String get systemDefault => '系统默认 (System Default)';

  @override
  String get aiCorrection => 'AI 智能纠错 (Beta)';

  @override
  String get aiCorrectionDesc => '使用大模型自动去除口水词、润色文本。';

  @override
  String get enabled => '已启用';

  @override
  String get disabled => '已禁用';

  @override
  String get apiConfig => 'API 配置 (兼容 OpenAI 格式)';

  @override
  String get systemPrompt => '系统提示词 (System Prompt)';

  @override
  String get resetDefault => '重置默认';

  @override
  String get triggerKey => '触发按键 (PTT)';

  @override
  String get triggerKeyDesc => '支持所有按键 (包括 FN)。按住键录音，松开后自动输入。';

  @override
  String get pressAnyKey => '按任意键...';

  @override
  String get activeEngine => '选择生效的语音引擎 (Active Engine)';

  @override
  String get engineLocal => '🔒 本地离线模型 (Local Privacy)';

  @override
  String get engineLocalDesc => '完全离线，保护隐私，无需联网。推荐日常使用。';

  @override
  String get engineCloud => '☁️ 阿里云智能语音 (Aliyun Cloud)';

  @override
  String get engineCloudDesc => '更高精度，支持云端识别。需要配置 API Key。';

  @override
  String get aliyunConfig => '阿里云智能语音配置';

  @override
  String get aliyunConfigDesc => '请前往阿里云 NLS 控制台获取 AccessKey 和 AppKey。';

  @override
  String get saveApply => '保存并应用 (Save & Apply)';

  @override
  String get download => '下载';

  @override
  String downloading(Object percent) {
    return '下载中... $percent%';
  }

  @override
  String get preparing => '准备中...';

  @override
  String get unzipping => '解压中...';

  @override
  String get activate => '激活';

  @override
  String get active => '使用中';

  @override
  String get settings => '设置';

  @override
  String get initializing => '初始化中...';

  @override
  String readyTip(Object key) {
    return '按住 $key 键开始说话';
  }

  @override
  String get recording => '正在录音...';

  @override
  String get processing => '处理中...';

  @override
  String get error => '错误';

  @override
  String get micError => '麦克风错误';

  @override
  String get noSpeech => '未检测到语音';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get modelZipformerName => 'Zipformer 双语模型 (推荐)';

  @override
  String get modelZipformerDesc => '平衡流式模型 (中英). 下载: ~490MB';

  @override
  String get modelParaformerName => 'Paraformer 双语模型 (高精)';

  @override
  String get modelParaformerDesc => '高精度前瞻流式模型 (中英). ~1GB';

  @override
  String get change => '更改';

  @override
  String get tabAbout => '关于';

  @override
  String get aboutTagline => '您的全能离线语音助手';

  @override
  String get aboutSubTagline => '隐私安全 · 极速响应 · 完全离线';

  @override
  String get aboutPoweredBy => '技术驱动';

  @override
  String get aboutCopyright => 'Copyright © 2026 Leon. 版权所有.';

  @override
  String get diaryMode => '闪念笔记';

  @override
  String get diaryTrigger => '笔记热键';

  @override
  String get diaryPath => '保存目录';

  @override
  String get createFolder => '新建文件夹';

  @override
  String get folderCreated => '文件夹已创建';

  @override
  String get chooseFile => '选择文件...';

  @override
  String get diarySaved => '已保存到笔记';

  @override
  String get engineType => '引擎类型';

  @override
  String get punctuationModel => '标点符号模型';

  @override
  String get punctuationModelDesc => '为识别结果自动添加标点符号。此模型是必需的。';

  @override
  String get asrModels => '语音识别模型';

  @override
  String get asrModelsDesc => '请下载并激活至少一个语音识别模型才能使用语音输入功能。';

  @override
  String get required => '必需';

  @override
  String get pickOne => '二选一';

  @override
  String get llmProvider => 'LLM 提供方';

  @override
  String get llmProviderCloud => '云端 API';

  @override
  String get llmProviderOllama => 'Ollama (本地)';

  @override
  String get ollamaUrl => 'Ollama 地址';

  @override
  String get ollamaModel => '模型名称';

  @override
  String get permInputMonitoring => '输入监控';

  @override
  String get permInputMonitoringDesc => '用于监听快捷键触发录音';

  @override
  String get permAccessibility => '辅助功能';

  @override
  String get permAccessibilityDesc => '用于将文字输入到应用程序';

  @override
  String get streamingModels => '流式模型（实时显示）';

  @override
  String get streamingModelsDesc => '边说边出字，适合长段听写。';

  @override
  String get offlineModels => '离线模型（高精度）';

  @override
  String get offlineModelsDesc => '松开按键后一次性识别，精度更高，录音时无实时字幕。';

  @override
  String get switchToOfflineTitle => '切换到离线模式？';

  @override
  String get switchToOfflineBody =>
      '离线模型在松开按键后才开始识别，录音过程中不会显示实时字幕，但识别精度更高。是否继续？';

  @override
  String get switchToStreamingTitle => '切换到流式模式？';

  @override
  String get switchToStreamingBody => '流式模型会在说话时实时显示文字，精度可能略低。是否继续？';

  @override
  String get confirm => '确认';

  @override
  String get modelSenseVoiceName => 'SenseVoice 2024（推荐）';

  @override
  String get modelSenseVoiceDesc => '阿里达摩院，中英日韩粤，自带标点。~228MB';

  @override
  String get modelSenseVoice2025Name => 'SenseVoice 2025';

  @override
  String get modelSenseVoice2025Desc => '粤语增强版，无内置标点。~158MB';

  @override
  String get modelOfflineParaformerName => 'Paraformer 离线版';

  @override
  String get modelOfflineParaformerDesc => '中英双语，成熟稳定。~217MB';

  @override
  String get modelParaformerDialectName => 'Paraformer 方言 2025';

  @override
  String get modelParaformerDialectDesc => '中英+四川话/重庆话方言。~218MB';

  @override
  String get modelWhisperName => 'Whisper Large-v3';

  @override
  String get modelWhisperDesc =>
      'OpenAI Whisper，中英日韩法德西俄等主流语言优秀，共 99 种语言。~1.0GB';

  @override
  String get modelFireRedName => 'FireRedASR Large';

  @override
  String get modelFireRedDesc => '中英+方言，最大容量。~1.4GB';

  @override
  String get builtInPunctuation => '自带标点';

  @override
  String get needsPunctuationModel => '需要标点模型';

  @override
  String get recognizing => '识别中...';

  @override
  String get modeStreaming => '流式';

  @override
  String get modeOffline => '离线';

  @override
  String get chooseModel => '选择语音模型';

  @override
  String get chooseModelDesc => '选择要下载的模型，之后可在设置中更改。';

  @override
  String get recommended => '推荐';

  @override
  String get onboardingWelcome => '欢迎使用子曰';

  @override
  String get onboardingWelcomeDesc => '按住快捷键说话，松开后自动输入文字\n支持中英文混合识别';

  @override
  String get onboardingStartSetup => '开始设置';

  @override
  String get onboardingPermTitle => '需要授权权限';

  @override
  String get onboardingPermDesc => '为了正常工作，子曰需要以下权限';

  @override
  String get permMicrophone => '麦克风';

  @override
  String get permMicrophoneDesc => '用于录制语音进行识别';

  @override
  String get permGrant => '授权';

  @override
  String get permGranted => '已授权';

  @override
  String get permRefreshStatus => '刷新状态';

  @override
  String get permRestartHint => '已授权？请重启应用使权限生效';

  @override
  String get onboardingContinue => '继续';

  @override
  String get onboardingGrantFirst => '请先授权';

  @override
  String get onboardingSetupLater => '稍后设置';

  @override
  String get onboardingCustomSelect => '自定义选择';

  @override
  String onboardingBrowseModels(Object count) {
    return '浏览全部 $count 个模型，包含方言和大容量模型';
  }

  @override
  String get onboardingModelSubtitle => '中英日韩粤 · 自带标点 · ~228MB';

  @override
  String get onboardingBack => '返回';

  @override
  String get onboardingDownloadTitle => '下载语音模型';

  @override
  String onboardingDownloading(Object name) {
    return '正在下载 $name';
  }

  @override
  String get onboardingPreparing => '准备下载...';

  @override
  String get onboardingDownloadPunct => '下载标点模型...';

  @override
  String onboardingDownloadPunctPercent(Object percent) {
    return '下载标点模型... $percent%';
  }

  @override
  String get onboardingDownloadASR => '下载语音识别模型...';

  @override
  String onboardingDownloadASRPercent(Object percent) {
    return '下载语音识别模型... $percent%';
  }

  @override
  String get onboardingActivating => '激活模型...';

  @override
  String get onboardingDownloadDone => '下载完成!';

  @override
  String get onboardingDownloadFail => '下载失败';

  @override
  String get onboardingRetry => '重试';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingStartDownload => '开始下载';

  @override
  String get onboardingDoneTitle => '设置完成!';

  @override
  String get onboardingHoldToSpeak => '按住说话';

  @override
  String get onboardingDoneDesc => '松开后自动输入到当前光标位置';

  @override
  String get onboardingBegin => '开始使用';

  @override
  String get tabTrigger => '触发方式';

  @override
  String get pttMode => '长按说话 (PTT)';

  @override
  String get toggleModeTip => '单击切换 (Toggle)';

  @override
  String get textInjection => '文本注入';

  @override
  String get recordingProtection => '录音保护';

  @override
  String get toggleMaxDuration => '最大录音时长';

  @override
  String get toggleMaxNone => '不限制';

  @override
  String toggleMaxMin(Object count) {
    return '$count 分钟';
  }

  @override
  String get toggleHint => '单击开始录音，再次单击结束。若与 PTT 同键，按住超过 1 秒为长按模式。';

  @override
  String get notSet => '未设置';
}
