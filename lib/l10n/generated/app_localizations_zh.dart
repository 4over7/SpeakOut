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
  String get language => '界面语言';

  @override
  String get langSystem => '跟随系统';

  @override
  String get inputLanguage => '输入语言';

  @override
  String get inputLanguageDesc => '你说什么语言';

  @override
  String get outputLanguage => '输出语言';

  @override
  String get outputLanguageDesc => '文字输出的语言，不同于输入语言时自动翻译';

  @override
  String get langAutoDetect => '自动检测';

  @override
  String get langFollowInput => '跟随输入语言';

  @override
  String get langZh => '中文';

  @override
  String get langZhHans => '简体中文';

  @override
  String get langZhHant => '繁體中文';

  @override
  String get langEn => 'English';

  @override
  String get langJa => '日本語';

  @override
  String get langKo => '한국어';

  @override
  String get langYue => '粤语';

  @override
  String get langEs => 'Español';

  @override
  String get langFr => 'Français';

  @override
  String get langDe => 'Deutsch';

  @override
  String get langRu => 'Русский';

  @override
  String get langPt => 'Português';

  @override
  String get translationModeHint => '口译模式';

  @override
  String get translationNeedsSmartMode =>
      '口译需要 AI 润色，当前为离线/云端模式。请切换到「智能模式」以启用翻译。';

  @override
  String get translationCloudLimited => '云端模式不含 AI 润色，口译效果有限。推荐切换到「智能模式」。';

  @override
  String inputLangModelHint(Object lang) {
    return '当前模型对$lang的支持有限，建议切换到 Whisper Large-v3 以获得更好的识别效果。';
  }

  @override
  String get audioInput => '音频输入设备';

  @override
  String get systemDefault => '系统默认';

  @override
  String get aiCorrection => 'AI 润色';

  @override
  String get aiCorrectionDesc => '使用大模型自动润色语音识别结果，修复同音字、去除口水词。';

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
  String get tabOrganize => 'AI 梳理';

  @override
  String get organizeEnabled => 'AI 梳理';

  @override
  String get organizeHotkey => '梳理快捷键';

  @override
  String get organizeHotkeyHint => '选中文字后按此快捷键触发';

  @override
  String get organizePrompt => '梳理指令';

  @override
  String get organizeResetDefault => '恢复默认';

  @override
  String get organizeDesc => '选中任意文字后按快捷键，AI 将提取核心观点、重组逻辑结构、专业化表达，但不改变原意。';

  @override
  String get organizeLlmHint => '使用「工作模式」中配置的 LLM 服务商';

  @override
  String get organizeGoConfig => '前往配置 →';

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
  String get offlineModels => '非流式模型（高精度）';

  @override
  String get offlineModelsDesc => '松开按键后一次性识别，精度更高，录音时无实时字幕。';

  @override
  String get switchToOfflineTitle => '切换到非流式模型？';

  @override
  String get switchToOfflineBody =>
      '非流式模型在松开按键后才开始识别，录音过程中不会显示实时字幕，但识别精度更高。是否继续？';

  @override
  String get switchToStreamingTitle => '切换到流式模型？';

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
  String get modeOffline => '非流式';

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
  String get textInjection => '文本注入（输入法）';

  @override
  String get recordingProtection => '录音保护';

  @override
  String get toggleMaxDuration => '最大录音时长';

  @override
  String get toggleMaxDurationDesc => '单击说话模式下，未主动停止时自动结束';

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

  @override
  String get importModel => '导入';

  @override
  String get manualDownload => '手动下载';

  @override
  String get importModelDesc => '选择已下载的 .tar.bz2 模型文件';

  @override
  String get importing => '导入中...';

  @override
  String get tabWorkMode => '工作模式';

  @override
  String get workModeOffline => '纯离线模式';

  @override
  String get workModeOfflineDesc => 'Sherpa 本地识别，完全离线，保护隐私';

  @override
  String get workModeOfflineIcon => '隐私优先，零网络依赖';

  @override
  String get workModeSmart => '智能模式';

  @override
  String get workModeSmartDesc => '本地识别 + AI 纠错润色，修复同音字、去除口水词';

  @override
  String get workModeCloud => '云端识别模式';

  @override
  String get workModeCloudDesc => '云端高精度识别，需联网';

  @override
  String get workModeSmartConfig => '智能润色配置';

  @override
  String get workModeAdvanced => '高级设置';

  @override
  String get tabAiPolish => 'AI 润色';

  @override
  String get aiPolishDesc => '使用大模型自动润色语音识别结果，结合专业词典智能纠正。';

  @override
  String get vocabEnhancement => '专业词汇';

  @override
  String get vocabEnhancementSubtitle => '为 AI 提供专业术语提示，提高领域词汇识别准确率';

  @override
  String get vocabEnabled => '启用专业词汇';

  @override
  String get vocabIndustryPresets => '行业预设词典';

  @override
  String get vocabCustomVocab => '个人词库';

  @override
  String get vocabCustomEnabled => '启用个人词库';

  @override
  String get vocabAddEntry => '添加词条';

  @override
  String get vocabWrongForm => '错误形式（ASR 识别结果）';

  @override
  String get vocabCorrectForm => '正确形式';

  @override
  String get vocabDelete => '删除';

  @override
  String get vocabTech => '软件/IT';

  @override
  String get vocabMedical => '医疗';

  @override
  String get vocabLegal => '法律';

  @override
  String get vocabFinance => '金融';

  @override
  String get vocabEducation => '教育';

  @override
  String get permissionsScreenRecording => '屏幕录制';

  @override
  String get permissionsScreenRecordingDesc =>
      'AI 调试截屏 + 读取其他 App 窗口标题（macOS 10.15+ 必需）';

  @override
  String get aiReportScreenRecordingWarning =>
      'AI 调试需要屏幕录制权限，否则无法读取窗口标题（绑定的目标窗口只显示 App 名）';

  @override
  String get aiReportOpenSettings => '打开系统设置';

  @override
  String get vocabEnabledNote => '开启后，专业术语将作为上下文提示注入 AI 润色';

  @override
  String get vocabBeta => 'Beta';

  @override
  String get vocabBetaNote => '试验性功能，准确率因 LLM 模型而异，正在持续优化';

  @override
  String get vocabImportTsv => '导入文件';

  @override
  String get vocabImportTsvDesc => '支持 TSV 或 CSV 格式，每行一条：错误形式<Tab>正确形式';

  @override
  String vocabImportSuccess(Object count) {
    return '成功导入 $count 条词条';
  }

  @override
  String vocabImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String get vocabExportTsv => '导出文件';

  @override
  String get aiPolishWarning =>
      'AI 润色可能会修改原意或引入错误，建议在重要场景下对比确认原文。离线模式（AI 关闭）下输出原始识别结果，准确性由语音模型决定。';

  @override
  String updateAvailable(Object version) {
    return '发现新版本 $version';
  }

  @override
  String get updateAction => '查看更新';

  @override
  String get updateUpToDate => '已是最新版本';

  @override
  String get updateDownload => '下载更新';

  @override
  String updateDownloading(Object pct) {
    return '下载中 $pct%';
  }

  @override
  String get updateInstallRestart => '安装并重启';

  @override
  String get updateInstalling => '正在安装...';

  @override
  String get updateRetry => '重试';

  @override
  String get updateFailed => '下载失败';

  @override
  String get updateManualDownload => '去下载页';

  @override
  String get llmRewrite => 'LLM 智能改写';

  @override
  String get aiPolishMatrix =>
      'LLM 改写 ✓ + 词典 ✓ → 术语注入 LLM，智能纠错\nLLM 改写 ✓ + 词典 ✗ → 纯 LLM 润色\nLLM 改写 ✗ + 词典 ✓ → 词典精确替换（离线可用）\nLLM 改写 ✗ + 词典 ✗ → 原始 ASR 输出';

  @override
  String get tabCloudAccounts => '云服务账户';

  @override
  String get cloudAccountsTitle => '管理云服务账户';

  @override
  String get cloudAccountAdd => '添加服务商';

  @override
  String get cloudAccountEdit => '编辑';

  @override
  String get cloudAccountDelete => '删除';

  @override
  String get cloudAccountCapabilityAsr => '语音识别';

  @override
  String get cloudAccountCapabilityLlm => 'AI 润色';

  @override
  String get cloudAccountNone => '暂无配置，请添加云服务账户';

  @override
  String get cloudAccountSelectAsr => '选择 ASR 服务';

  @override
  String get cloudAccountSelectLlm => '选择 LLM 服务';

  @override
  String get cloudAccountGoConfig => '前往账户中心配置';

  @override
  String get cloudAccountSaved => '账户已保存';

  @override
  String get cloudAccountDeleted => '账户已删除';

  @override
  String get cloudAccountDeleteConfirm => '确定删除此账户？';

  @override
  String get cloudAccountProvider => '服务商';

  @override
  String get cloudAccountName => '显示名称';

  @override
  String get cloudAccountEnabled => '启用';

  @override
  String get languageSettings => '语言设置';

  @override
  String get translationDisabledReason => '口译模式需要 AI 润色，仅智能模式可用';

  @override
  String get cloudAsrLangUnsupported => '当前云端 ASR 服务仅支持中文和英文，已选语言将回退到中文识别。';

  @override
  String get quickTranslate => '即时翻译';

  @override
  String get quickTranslateDesc => '按下快捷键录音，结果自动翻译为目标语言（不影响正常录音设置）';

  @override
  String get translateTargetLanguage => '翻译目标语言';

  @override
  String get translateHotkey => '翻译快捷键';

  @override
  String get translateNoLlm => '即时翻译需要配置 LLM 服务。请在「云服务账户」中添加 LLM 服务商。';

  @override
  String get settingsV18PreviewTitle => '设置';

  @override
  String get sidebarSectionBasic => '基础';

  @override
  String get sidebarSectionVoice => '语音';

  @override
  String get sidebarSectionSuperpower => '超能力';

  @override
  String get sidebarSectionOther => '其他';

  @override
  String get sidebarOverview => '概览';

  @override
  String get sidebarShortcuts => '快捷键';

  @override
  String get sidebarPermissions => '权限';

  @override
  String get sidebarRecognition => '识别引擎';

  @override
  String get sidebarAiPlus => 'AI Plus';

  @override
  String get sidebarVocab => '词典';

  @override
  String get sidebarCorrection => '纠错反馈';

  @override
  String get sidebarAiReport => 'AI 调试';

  @override
  String get sidebarDeveloper => '开发者选项';

  @override
  String get showAdvanced => '显示高级';

  @override
  String get shortcutsRecordKey => '录音键';

  @override
  String get shortcutsSharedHint => '短按 = 切换录音，长按 = 说话松开停';

  @override
  String get shortcutsSplitTitle => '录音键（PTT / Toggle 分键）';

  @override
  String get shortcutsPttTitle => '长按说话 (PTT)';

  @override
  String get shortcutsPttHint => '长按该键录音，松开停止';

  @override
  String get shortcutsToggleTitle => '单击说话';

  @override
  String get shortcutsToggleHint => '点一下开录、再点一下停';

  @override
  String get shortcutsTip =>
      '推荐 Right Option / Fn / F13–F19 — Cmd / Ctrl 等组合键常被系统应用占用。';

  @override
  String get hotkeyModalTitle => '录制快捷键';

  @override
  String get hotkeyModalSubtitle => '请按下您想要设置的按键或组合键';

  @override
  String hotkeyModalCountdown(int seconds) {
    return '$seconds 秒后自动取消 · 按 ESC 立即退出';
  }

  @override
  String get hotkeyModalRecommend => '推荐';

  @override
  String get hotkeyModalAvoid => '避开 Cmd / Ctrl 等常被系统应用占用的组合键';

  @override
  String hotkeyInUseTitle(String keyName, String feature) {
    return '$keyName 已被「$feature」使用';
  }

  @override
  String get hotkeyInUseMessage => '该按键已被占用，请选择其他按键。';

  @override
  String get hotkeyInUseOk => '好的';

  @override
  String get hotkeyRecordDiary => '录制闪念笔记快捷键';

  @override
  String get hotkeyRecordDiaryHint => '长按该键开始记录笔记';

  @override
  String get hotkeyRecordToggleDiary => '录制笔记 Toggle 快捷键';

  @override
  String get hotkeyRecordToggleDiaryHint => '点一下开录、再点一下停';

  @override
  String get hotkeyRecordOrganize => '录制 AI 梳理快捷键';

  @override
  String get hotkeyRecordOrganizeHint => '选中文字后按此键重组';

  @override
  String get hotkeyRecordTranslate => '录制即时翻译快捷键';

  @override
  String get hotkeyRecordTranslateHint => '选中文字后按此键翻译';

  @override
  String get hotkeyRecordCorrection => '录制纠错反馈快捷键';

  @override
  String get hotkeyRecordCorrectionHint => '选中文字后按此键提交纠错';

  @override
  String get hotkeyRecordAiReport => '录制 AI 调试基础键';

  @override
  String get hotkeyRecordAiReportHint => '长按此键 + 数字 1-5 激活';

  @override
  String get overviewWelcome => '欢迎使用 SpeakOut';

  @override
  String get overviewTagline => 'macOS 离线优先 AI 语音输入 · 隐私安全 · 免费开源';

  @override
  String get overviewGetStarted => '开始配置';

  @override
  String get featureOfflineTitle => '离线识别';

  @override
  String get featureOfflineDesc => '本地 Sherpa-ONNX ASR，中英识别媲美云端，音频不出设备';

  @override
  String get featureAiPolishTitle => 'AI 润色';

  @override
  String get featureAiPolishDesc => '云端 LLM 智能纠错，修复同音字、标点、语法';

  @override
  String get featureSuperpowerTitle => '超能力';

  @override
  String get featureSuperpowerDesc => '闪念笔记 / AI 梳理 / 即时翻译 / 纠错反馈 / AI 调试';

  @override
  String get featureVocabTitle => '专业词典';

  @override
  String get featureVocabDesc => '自定义术语注入 LLM prompt，医疗 / 法律 / 金融等包';

  @override
  String get overviewHelpTitle => '帮助与支持';

  @override
  String get linkWikiFaq => 'Wiki · FAQ';

  @override
  String get linkChangelog => '更新日志';

  @override
  String get linkXHandle => 'X · @4over7';

  @override
  String get linkFeedback => '反馈 · 4over7@gmail.com';

  @override
  String get linkGithubIssues => 'GitHub Issues';

  @override
  String get smartNeedsAiPlusConfig =>
      'Smart 模式需在「AI Plus」页配置 LLM（服务商 / 模型 / API Key），否则 AI 润色不生效。';

  @override
  String get gotoAiPlus => '前往 AI Plus';

  @override
  String get aiPlusNotActive =>
      'AI 润色当前不生效：需在「识别引擎」页把工作模式切为 Smart（离线 + 云端 AI）。LLM 配置仍可在此编辑。';

  @override
  String get aboutModelsDir => '模型目录';

  @override
  String get aboutSystemLog => '导出日志包';

  @override
  String get aboutSystemLogDesc =>
      '打包最近 10 分钟系统日志 + 应用详细日志 + 诊断信息为 zip（报 bug 时发给我）';

  @override
  String get aboutSystemLogExport => '导出';

  @override
  String get aboutSystemLogFileTitle => '导出日志包';

  @override
  String aboutSystemLogSuccess(String path) {
    return '已导出到 $path';
  }

  @override
  String get diaryBullet1 => '按快捷键一键开始，松开自动保存，不打断思考流';

  @override
  String get diaryBullet2 => '笔记按日期命名，生成 Markdown 文件，便于检索';

  @override
  String get diaryBullet3 => '纯本地存储，可与 Obsidian / Notion / iCloud 等同步';

  @override
  String get organizeBullet1 => '选中一段凌乱的文字后按键，LLM 重新组织结构';

  @override
  String get organizeBullet2 => '结果追加在原文下一行，不覆盖原稿';

  @override
  String get organizeBullet3 => '使用「AI Plus」配置的 LLM 服务，无需重复填密钥';

  @override
  String get translateBullet1 => '按键录音，语音识别后自动翻译到目标语言';

  @override
  String get translateBullet2 => '结果直接注入当前输入框，无需复制粘贴';

  @override
  String get translateBullet3 => '支持中文、英文、日文、韩文等 11 种语言互译';

  @override
  String get correctionBullet1 => '选中修正后的文字一键提交，ASR 学习你的用词习惯';

  @override
  String get correctionBullet2 => 'LLM 提取词级差异，自动加入专属词典';

  @override
  String get correctionBullet3 => '无需手动编辑词典，日常使用中持续优化识别';

  @override
  String get aiReportBullet1 => '截屏 + 语音描述，一键发送到 AI 编程助手';

  @override
  String get aiReportBullet2 => '支持绑定多个目标窗口（Claude Code / Cursor / ChatGPT）';

  @override
  String get aiReportBullet3 => '按基础键 + 数字键快速切换目标窗口';

  @override
  String aboutSystemLogFailed(String err) {
    return '导出失败：$err';
  }

  @override
  String get aboutDiagnostics => '诊断信息';

  @override
  String get aboutDiagnosticsDesc => '复制版本 / 配置 / 路径信息到剪贴板（报错时发给我）';

  @override
  String get actionCopy => '复制';

  @override
  String get actionCopied => '已复制';

  @override
  String get permissionsSectionTitle => '系统权限';

  @override
  String get permissionsReauthTip => '更换签名证书后如快捷键失效，请逐项重新授权。';

  @override
  String get permissionsAccessibility => '辅助功能';

  @override
  String get permissionsAccessibilityDesc => '快捷键+文本注入';

  @override
  String get permissionsInputMonitoring => '输入监控';

  @override
  String get permissionsInputMonitoringDesc => '键盘触发录音';

  @override
  String get permissionsMicrophone => '麦克风';

  @override
  String get permissionsMicrophoneDesc => '语音采集';

  @override
  String get permissionsOpen => '打开';

  @override
  String get aboutDeveloper => '开发者';

  @override
  String get aboutVerboseLogging => '详细日志';

  @override
  String get aboutLogDir => '日志输出目录';

  @override
  String get aboutLogDirUnset => '未设置（仅输出到控制台）';

  @override
  String get aboutLoading => '加载中…';

  @override
  String get aboutConfigBackup => '配置备份';

  @override
  String get aboutExportConfig => '导出配置';

  @override
  String get aboutExportConfigDesc => '将所有设置和凭证导出为文件（含明文密钥，请妥善保管）';

  @override
  String get aboutExportAction => '导出';

  @override
  String get aboutExportFileTitle => '导出配置文件';

  @override
  String get aboutImportConfig => '导入配置';

  @override
  String get aboutImportConfigDesc => '从备份文件恢复所有设置，立即生效';

  @override
  String get aboutImportAction => '导入';

  @override
  String get aboutImportFileTitle => '选择配置文件';

  @override
  String aboutExportSuccess(String msg) {
    return '已导出：$msg';
  }

  @override
  String aboutExportFailed(String err) {
    return '导出失败：$err';
  }

  @override
  String aboutImportSuccess(String msg) {
    return '$msg，配置已生效';
  }

  @override
  String aboutImportFailed(String err) {
    return '导入失败：$err';
  }

  @override
  String audioDeviceCurrent(String name) {
    return '当前：$name';
  }

  @override
  String get bluetoothMicWarning => '蓝牙麦克风可能降低质量';

  @override
  String get switchToBuiltin => '切换到内置';

  @override
  String get autoOptimizeAudio => '自动优化音频';

  @override
  String get autoOptimizeAudioDesc => '蓝牙耳机时自动切换到高质量麦克风';

  @override
  String get hotkeyConflictTaken => '该按键已被占用，请选择其他按键。';

  @override
  String hotkeyConflictAutoClearTitle(String keyName, String feature) {
    return '$keyName 已被「$feature」占用';
  }

  @override
  String get hotkeyConflictAutoClearMsg => '快捷键已自动清除，请重新设置。';

  @override
  String modelActivateFailed(String err) {
    return '模型激活失败：$err';
  }

  @override
  String get punctAutoLoaded => '已自动加载标点模型';

  @override
  String get punctMissingTitle => '该模型不含标点符号';

  @override
  String get punctMissingMsg => '此模型输出的文字没有标点。建议下载标点模型以获得更好的阅读体验。\n\n是否前往下载？';

  @override
  String get punctDownload => '去下载';

  @override
  String get punctSkip => '暂不需要';

  @override
  String get offlineDataLocal => '所有数据在本地处理，不上传任何信息';

  @override
  String get asrModel => '识别模型';

  @override
  String get manageCloudAccounts => '管理云服务账户';

  @override
  String get typewriterEffect => '打字机效果';

  @override
  String get ollamaServerRequired => '确保 Ollama 已启动（ollama serve）';

  @override
  String get manageModels => '管理模型';

  @override
  String get llmRecommendations => '选型参考';

  @override
  String get llmTagFastest => '极致速度';

  @override
  String get llmTagStable => '稳定首选';

  @override
  String get llmTagFastestNote => '高峰期可能波动';

  @override
  String get llmTagStableNote => '波动最小，质量稳定';

  @override
  String get llmDataSource => '数据来源：2026-03-21 实测，非流式 API，中国大陆网络';

  @override
  String get llmModelField => '模型';

  @override
  String get llmModelCustom => '自定义...';

  @override
  String get llmModelNamePlaceholder => '模型名称';

  @override
  String get diaryDirNotSet => '未设置保存目录';

  @override
  String get diaryDirCannotWrite => '无法写入目录，请重新选择（macOS 需重新授权）';

  @override
  String get diaryDirPick => '请选择保存目录以授权访问';

  @override
  String get diaryDesc => '随时随地语音记录灵感，自动保存为 Markdown 日记。';

  @override
  String get organizeCollapse => '收起';

  @override
  String get organizeEditInstruction => '编辑指令';

  @override
  String get correctionHotkey => '纠错快捷键';

  @override
  String get correctionExportDialog => '导出纠错数据';

  @override
  String get correctionImportDialog => '导入纠错数据';

  @override
  String get correctionExportSuccess => '导出成功';

  @override
  String get correctionExportFailedEmpty => '导出失败：无数据';

  @override
  String correctionImportSuccess(int count) {
    return '导入 $count 条记录（词汇已同步）';
  }

  @override
  String get correctionExportBtn => '导出';

  @override
  String get correctionImportBtn => '导入';

  @override
  String get correctionDesc => '选中修正后的文字，一键提交纠错。ASR 自动学习你的用词习惯。';

  @override
  String get aiReportBaseKey => '基础按键';

  @override
  String aiReportBaseKeyDesc(String baseKeyName, int slotCount) {
    return '按住 $baseKeyName + 数字键（1–$slotCount）选择目标窗口';
  }

  @override
  String get aiReportAddFirstWindow => '添加第一个窗口';

  @override
  String get aiReportAddWindow => '添加窗口';

  @override
  String get aiReportDescShort => '为 AI Coding 而生 — 截屏+语音自动发送到绑定窗口';

  @override
  String get aiReportDescLong =>
      '为 AI Coding 而生 — 截屏+语音描述，一键发送到 Claude Code / Cursor。';

  @override
  String get aiReportSwitchWindow => '请切换到目标窗口...';

  @override
  String get aiReportUnbound => '未绑定';

  @override
  String get aiReportBindTitle => '绑定 AI 工具窗口';

  @override
  String get aiReportBindMsg => '点击「开始」后，你有 3 秒时间切换到目标窗口。';

  @override
  String get aiReportStart => '开始';

  @override
  String get aiReportCancel => '取消';

  @override
  String get activeHotkeys => '已启用的快捷键';

  @override
  String get appProductName => '子曰 SpeakOut';

  @override
  String get aboutVersionCopyTip => '双击复制版本号';

  @override
  String get aboutVersionCopied => '已复制';

  @override
  String get aboutUpdateDownload => '下载更新';

  @override
  String get aboutPrivacyPolicy => '隐私政策';

  @override
  String get clearHotkey => '清除快捷键';

  @override
  String get featureCorrection => '纠错反馈';

  @override
  String get featureAiReport => 'AI 一键调试';

  @override
  String get shortcutsAndDuration => '快捷键与时长';
}
