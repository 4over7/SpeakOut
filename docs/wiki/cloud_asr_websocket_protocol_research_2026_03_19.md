# 云端 ASR WebSocket 协议调研报告

> 日期: 2026-03-19
> 目的: 为实现 VolcEngine / XFYun / Tencent 三家 ASRProvider 收集完整协议细节

---

## 一、火山引擎 Seed-ASR (volcengine)

### 1.1 概述

火山引擎提供两个版本的流式 ASR WebSocket API:

| 版本 | 端点 | 鉴权方式 | 特点 |
|------|------|---------|------|
| **V2** | `wss://openspeech.bytedance.com/api/v2/asr` | URL 参数: `appid`, `token`, `cluster` | 旧版，二进制协议 |
| **V3 (推荐)** | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel` | HTTP Headers | 新版大模型 ASR，二进制协议 |

**建议实现 V3 协议** — 精度更高 (Seed-ASR 大模型)，鉴权更规范。

### 1.2 WebSocket 端点 & 鉴权

#### V3 鉴权 (Header 方式)

```
URL: wss://openspeech.bytedance.com/api/v3/sauc/bigmodel

Headers:
  X-Api-App-Key: <app_id>
  X-Api-Access-Key: <access_token>
  X-Api-Resource-Id: volc.bigasr.sauc.duration
  X-Api-Connect-Id: <uuid>       // 可选，用于追踪
```

#### V2 鉴权 (URL 参数方式)

```
URL: wss://openspeech.bytedance.com/api/v2/asr?appid={app_id}&token={access_token}&cluster={cluster}
```

凭证来源: 火山引擎控制台 → 语音技术 → 创建应用获取 app_id + access_token，cluster 从控制台获取 (如 `volcengine_streaming_common`)。

### 1.3 二进制协议格式

**所有消息 (客户端/服务端) 都使用自定义二进制帧格式**，不是纯 JSON/文本。

#### 帧结构: 4 字节 Header + 4 字节 Payload Size + Payload

```
Byte 0: [Protocol Version (4 bits) | Header Size (4 bits)]
Byte 1: [Message Type (4 bits)     | Type Flags (4 bits)]
Byte 2: [Serialization (4 bits)    | Compression (4 bits)]
Byte 3: [Reserved (8 bits)]
Bytes 4-7: Payload Size (big-endian uint32)
Bytes 8+: Payload (JSON bytes 或 raw audio)
```

#### 字段值定义

| 字段 | 值 | 含义 |
|------|-----|------|
| Protocol Version | `0b0001` | 版本 1 |
| Header Size | `0b0001` | 4 字节 (1 个 4 字节单元) |
| **Message Type** | | |
| | `0b0001` (0x1) | Full Client Request (初始请求，JSON) |
| | `0b0010` (0x2) | Audio-Only Request (音频数据) |
| | `0b1001` (0x9) | Full Server Response (服务端结果) |
| | `0b1111` (0xF) | Error Message |
| **Type Flags** | | |
| | `0b0000` | 非最后一包 |
| | `0b0010` | 最后一包 (last packet) |
| **Serialization** | | |
| | `0b0000` | 无 (raw binary) |
| | `0b0001` | JSON |
| **Compression** | | |
| | `0b0000` | 无压缩 |
| | `0b0001` | Gzip |

### 1.4 消息流程

#### Step 1: 发送 Full Client Request

```python
# Header: version=1, headerSize=1, msgType=0x1(fullReq), flags=0, serial=JSON(1), compress=0, reserved=0
header = struct.pack(">BBBB", 0x11, 0x10, 0x10, 0x00)
payload = json.dumps(request_json).encode('utf-8')
payload_size = struct.pack(">I", len(payload))
ws.send_bytes(header + payload_size + payload)
```

**Header 字节解析:**
- `0x11` = version(0001) + headerSize(0001)
- `0x10` = msgType(0001=fullReq) + flags(0000)
- `0x10` = serialization(0001=JSON) + compression(0000=none)
- `0x00` = reserved

#### Step 2: 发送音频 (循环)

```python
# Header: version=1, headerSize=1, msgType=0x2(audioOnly), flags=0, serial=none, compress=0
flags = 0b0000  # 非最后一包
msg_type_flags = (0b0010 << 4) | flags  # = 0x20
header = struct.pack(">BBBB", 0x11, msg_type_flags, 0x00, 0x00)
payload_size = struct.pack(">I", len(audio_chunk))
ws.send_bytes(header + payload_size + audio_chunk)
```

#### Step 3: 发送最后一包 (End of Stream)

```python
# 最后一包: flags=0b0010, payload 可以为空
flags = 0b0010
msg_type_flags = (0b0010 << 4) | flags  # = 0x22
header = struct.pack(">BBBB", 0x11, msg_type_flags, 0x00, 0x00)
payload_size = struct.pack(">I", 0)  # 空 payload
ws.send_bytes(header + payload_size)
```

#### Step 4: 接收服务端响应 (二进制帧)

```python
resp_header = data[0:4]
resp_payload_size = struct.unpack(">I", data[4:8])[0]
resp_payload = data[8:8+resp_payload_size]

msg_type = (resp_header[1] >> 4) & 0x0F

if msg_type == 0b1001:  # Full Server Response
    # payload 可能有非 JSON 前缀，需查找 '{' 起始位置
    json_start = resp_payload.find(b'{')
    if json_start > 0:
        resp_payload = resp_payload[json_start:]
    result = json.loads(resp_payload)

elif msg_type == 0b1111:  # Error
    error_msg = resp_payload.decode('utf-8', errors='ignore')
```

### 1.5 请求 JSON 结构 (Full Client Request)

```json
{
  "user": {
    "uid": "device_or_user_id"
  },
  "audio": {
    "format": "pcm",
    "rate": 16000,
    "bits": 16,
    "channel": 1,
    "codec": "raw"
  },
  "request": {
    "model_name": "bigmodel",
    "language": "zh",
    "enable_itn": true,
    "enable_punc": true,
    "result_type": "single",
    "show_utterances": false,
    "vad": {
      "vad_enable": true,
      "end_window_size": 800,
      "force_to_speech_time": 0
    }
  }
}
```

**关键参数:**
- `result_type`: `"single"` = 增量结果 (每次只返回当前句) / `"full"` = 全量结果
- `enable_itn`: 逆文本正则化 (数字、日期等)
- `enable_punc`: 标点预测
- `language`: `"zh"` 中文, `"en"` 英文, `"ja"` 日文等
- `model_name`: `"bigmodel"` (Seed-ASR 大模型)
- `show_utterances`: 是否返回 utterance 级别详情

V2 协议的 JSON 结构略有不同:
```json
{
  "app": {"appid": "", "token": "", "cluster": ""},
  "user": {"uid": ""},
  "audio": {"format": "raw", "rate": 16000, "bits": 16, "channel": 1, "language": "zh-CN"},
  "request": {
    "reqid": "uuid",
    "workflow": "audio_in,resample,partition,vad,fe,decode,nlu_punctuate",
    "sequence": 1,
    "show_utterances": true
  }
}
```

### 1.6 响应 JSON 结构

#### V3 响应:

```json
{
  "type": "final",
  "result": [
    {"text": "识别出的完整文本"}
  ]
}
```

- `type`: `"interim"` (中间结果) / `"final"` (最终结果)
- `result`: 数组，每个元素包含 `text` 字段

#### V2 响应:

```json
{
  "reqid": "request_uuid",
  "code": 1000,
  "message": "Success",
  "sequence": -1,
  "result": [
    {
      "text": "完整识别文本",
      "utterances": [
        {
          "definite": true,
          "text": "分句文本",
          "start_time": 0,
          "end_time": 1705,
          "words": [
            {"text": "字", "start_time": 1020, "end_time": 1200}
          ]
        }
      ]
    }
  ]
}
```

- `definite`: `false` = 中间结果, `true` = 最终结果
- `code`: `1000` = 成功

### 1.7 音频要求

- **格式**: PCM (raw), 也支持 WAV/MP3/OGG
- **采样率**: 16000 Hz
- **位深**: 16-bit (Little-Endian)
- **声道**: 单声道 (Mono)
- **每包建议大小**: 100-200ms 音频 (16kHz×16bit×100ms = 3200 bytes)

### 1.8 其他特性

| 特性 | 支持情况 |
|------|---------|
| 中英混合识别 | 支持 (language="zh" 时可识别英文) |
| 标点 | 支持 (enable_punc=true) |
| VAD | 支持 (可配置静默检测窗口) |
| ITN | 支持 (数字/日期/时间正则化) |
| 错误码 | 1000=成功, 1002=权限, 1003=QPS超限, 1013=静音 |
| 并发限制 | 按 appid QPS 限制，需在控制台配置 |

---

## 二、讯飞 实时语音听写 (xfyun/iFlytek)

### 2.1 概述

讯飞语音听写（流式版）使用 **WebSocket + JSON 文本帧** 协议，音频通过 Base64 编码嵌入 JSON。鉴权通过 URL 中的 HMAC-SHA256 签名实现。

### 2.2 WebSocket 端点 & 鉴权

#### 端点 URL

```
wss://iat-api.xfyun.cn/v2/iat     (推荐)
wss://ws-api.xfyun.cn/v2/iat      (备用)
```

小语种: `wss://iat-niche-api.xfyun.cn/v2/iat`

#### 签名生成流程

```python
import hmac, hashlib, base64
from urllib.parse import urlencode
from wsgiref.handlers import format_date_time
from datetime import datetime
from time import mktime

def create_url(api_key, api_secret):
    host = 'iat-api.xfyun.cn'
    path = '/v2/iat'
    now = datetime.now()
    date = format_date_time(mktime(now.timetuple()))  # RFC1123 格式

    # 1. 构造签名原文 (注意 \n 换行, ':' 后有空格)
    signature_origin = f"host: {host}\ndate: {date}\nGET {path} HTTP/1.1"

    # 2. HMAC-SHA256 签名
    signature_sha = hmac.new(
        api_secret.encode('utf-8'),
        signature_origin.encode('utf-8'),
        digestmod=hashlib.sha256
    ).digest()
    signature = base64.b64encode(signature_sha).decode('utf-8')

    # 3. 构造 authorization (先拼接再整体 Base64)
    authorization_origin = (
        f'api_key="{api_key}", algorithm="hmac-sha256", '
        f'headers="host date request-line", signature="{signature}"'
    )
    authorization = base64.b64encode(
        authorization_origin.encode('utf-8')
    ).decode('utf-8')

    # 4. 拼接最终 URL
    params = {
        'authorization': authorization,
        'date': date,
        'host': host,
    }
    return f"wss://{host}{path}?{urlencode(params)}"
```

**关键点:**
- `date` 必须是 RFC1123 格式 UTC 时间，容差 300 秒 (5 分钟)
- `signature_origin` 三行: `host: xxx`, `date: xxx`, `GET /v2/iat HTTP/1.1`
- 签名使用 `api_secret`，authorization 中包含 `api_key`
- `app_id` 不参与签名，而是放在消息体的 `common.app_id` 中

### 2.3 消息协议 (纯 JSON 文本帧)

#### 第一帧 (status=0): 携带配置 + 首段音频

```json
{
  "common": {
    "app_id": "YOUR_APP_ID"
  },
  "business": {
    "language": "zh_cn",
    "domain": "iat",
    "accent": "mandarin",
    "dwa": "wpgs",
    "ptt": 1,
    "vad_eos": 3000
  },
  "data": {
    "status": 0,
    "format": "audio/L16;rate=16000",
    "encoding": "raw",
    "audio": "<base64_encoded_pcm>"
  }
}
```

#### 中间帧 (status=1): 仅音频数据

```json
{
  "data": {
    "status": 1,
    "format": "audio/L16;rate=16000",
    "encoding": "raw",
    "audio": "<base64_encoded_pcm>"
  }
}
```

#### 最后一帧 (status=2): 结束信号

```json
{
  "data": {
    "status": 2,
    "format": "audio/L16;rate=16000",
    "encoding": "raw",
    "audio": "<base64_encoded_last_chunk_or_empty>"
  }
}
```

### 2.4 business 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `language` | string | `zh_cn` 中文(支持简单英文混合), `en_us` 英文, `ja_jp` 日文等 |
| `domain` | string | `iat` (日常用语), `medical` (医疗) 等 |
| `accent` | string | `mandarin` 普通话, `cantonese` 粤语等 (202种方言) |
| `dwa` | string | `wpgs` 开启动态修正 (仅中文支持，**推荐开启**) |
| `ptt` | int | `1` 开启标点 (默认), `0` 关闭 |
| `vad_eos` | int | 后端静默检测 (ms), 范围 [0, 10000], 默认不设 |
| `eos` | int | 后端超时 (ms), 默认 2000 |

### 2.5 音频要求

- **格式**: PCM (raw) — 在 `format` 字段指定 `audio/L16;rate=16000`
- **编码**: `raw` (PCM), 也支持 `speex`, `speex-wb`, `lame`
- **采样率**: 16000 Hz (推荐) 或 8000 Hz
- **位深**: 16-bit
- **声道**: 单声道
- **传输方式**: **Base64 编码后放入 JSON 的 `data.audio` 字段**
- **每帧大小**: PCM 16kHz 建议 1280 bytes (40ms), 即每 40ms 发送一帧
- **发送间隔**: 40ms

### 2.6 响应消息结构

#### 基础响应 (无动态修正):

```json
{
  "code": 0,
  "message": "success",
  "sid": "iat000xxxxx",
  "data": {
    "status": 2,
    "result": {
      "sn": 1,
      "ls": false,
      "bg": 0,
      "ed": 0,
      "ws": [
        {
          "bg": 0,
          "cw": [
            {"w": "今天", "sc": 0.98}
          ]
        },
        {
          "bg": 20,
          "cw": [
            {"w": "天气", "sc": 0.95}
          ]
        }
      ]
    }
  }
}
```

**字段说明:**
- `code`: 0 = 成功, 非 0 = 错误
- `data.status`: 0 = 第一个结果, 1 = 中间结果, 2 = 最后一个结果
- `result.sn`: 句序号 (从 1 开始)
- `result.ls`: 是否最后一句
- `result.ws[]`: 词序列
  - `ws[].bg`: 词起始时间 (帧偏移)
  - `ws[].cw[]`: 候选词列表
    - `cw[].w`: 词文本
    - `cw[].sc`: 置信度分数

#### 文本拼接方法 (无动态修正):

```dart
String assembleText(List<dynamic> wsList) {
  final buf = StringBuffer();
  for (final ws in wsList) {
    final cw = ws['cw'] as List;
    if (cw.isNotEmpty) {
      buf.write(cw[0]['w']); // 取第一个候选
    }
  }
  return buf.toString();
}
```

每次响应的 `result` 是对之前结果的 **追加**，按 `sn` 顺序拼接即可。

#### 动态修正响应 (dwa=wpgs):

```json
{
  "data": {
    "result": {
      "sn": 3,
      "ls": false,
      "pgs": "rpl",
      "rg": [2, 3],
      "ws": [
        {"bg": 0, "cw": [{"w": "修正后文本", "sc": 0}]}
      ]
    }
  }
}
```

**动态修正字段:**
- `pgs`: `"apd"` = 追加 (append), `"rpl"` = 替换 (replace)
- `rg`: 替换范围 `[start_sn, end_sn]`，当 `pgs="rpl"` 时有效

**动态修正拼接逻辑:**

```dart
Map<int, String> resultMap = {};  // sn -> text

void handleResult(Map<String, dynamic> result) {
  final sn = result['sn'] as int;
  final pgs = result['pgs'] as String?;
  final text = assembleText(result['ws']);

  if (pgs == 'rpl') {
    // 替换: 删除 rg 范围内的旧结果，用当前结果替换
    final rg = result['rg'] as List;
    for (int i = rg[0]; i <= rg[1]; i++) {
      resultMap.remove(i);
    }
    resultMap[rg[0]] = text;
  } else {
    // 追加 (apd 或无 pgs)
    resultMap[sn] = text;
  }

  // 按 sn 排序拼接完整文本
  final sortedKeys = resultMap.keys.toList()..sort();
  final fullText = sortedKeys.map((k) => resultMap[k]).join('');
}
```

### 2.7 其他特性

| 特性 | 支持情况 |
|------|---------|
| 中英混合识别 | 支持 (`language=zh_cn` 下支持简单英文) |
| 标点 | 支持 (`ptt=1`) |
| 动态修正 | 支持 (`dwa=wpgs`，仅中文，效果更流畅) |
| 方言 | 支持 (202 种方言，通过 `accent` 参数) |
| 并发限制 | 默认 50 路 |
| 单次时长限制 | **最长 60 秒** |
| 空闲超时 | 10 秒无数据断连 |
| 签名有效期 | 5 分钟时钟容差 |

**重要限制: 单次识别最长 60 秒!** 这意味着对于持续语音输入场景，需要在 60 秒内完成一次会话。对于 SpeakOut 的按键说话模式通常够用，但需要注意。

---

## 三、腾讯云 实时语音识别 (tencent)

### 3.1 概述

腾讯云使用 **WebSocket + 二进制音频帧** 协议，音频直接以 binary 帧发送（不需要 Base64），鉴权通过 URL 中的 HMAC-SHA1 签名。

### 3.2 WebSocket 端点 & 鉴权

#### 端点 URL 格式

```
wss://asr.cloud.tencent.com/asr/v2/{appid}?{签名参数}
```

`appid` 从腾讯云控制台 API 密钥管理页面获取。

#### URL 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `secretid` | 是 | 密钥 SecretId |
| `timestamp` | 是 | 当前 UNIX 时间戳 (秒) |
| `expired` | 是 | 签名过期时间戳 (> timestamp，差值 < 90 天) |
| `nonce` | 是 | 随机正整数 (最长 10 位) |
| `engine_model_type` | 是 | 引擎模型，如 `16k_zh` |
| `voice_id` | 是 | 音频流唯一标识 (如 UUID) |
| `voice_format` | 是 | 音频编码: `1`=PCM, `4`=Speex, `6`=Silk, `8`=MP3, `10`=Opus, `12`=WAV |
| `needvad` | 否 | `1`=开启 VAD (推荐) |
| `filter_dirty` | 否 | `0`=不过滤, `1`=过滤脏词, `2`=替换为* |
| `filter_modal` | 否 | `0`=不过滤, `1`=部分过滤, `2`=严格过滤语气词 |
| `filter_punc` | 否 | `0`=不过滤句末句号 (默认), `1`=过滤 |
| `word_info` | 否 | `1`=返回词级别时间戳 |
| `signature` | 是 | 生成的签名值 |

#### 引擎模型类型

| engine_model_type | 说明 |
|-------------------|------|
| `16k_zh` | 中文普通话 (默认) |
| `16k_zh_en` | 中英粤 + 9 种方言大模型 |
| `16k_en` | 英文 |
| `16k_zh_dialect` | 多方言 |
| `8k_zh` | 电话通讯场景 |

#### 签名生成算法

```python
import hmac, hashlib, base64, time, random, uuid
from urllib.parse import quote

def generate_signed_url(secret_id, secret_key, appid, engine_model_type='16k_zh'):
    timestamp = int(time.time())
    expired = timestamp + 86400  # 24小时过期
    nonce = random.randint(10000, 99999)
    voice_id = str(uuid.uuid4())

    # 1. 按字典序排列参数 (不含 signature)
    params = {
        'engine_model_type': engine_model_type,
        'expired': expired,
        'needvad': 1,
        'nonce': nonce,
        'secretid': secret_id,
        'timestamp': timestamp,
        'voice_format': 1,  # PCM
        'voice_id': voice_id,
    }

    # 2. 拼接签名原文 (域名路径 + 参数)
    #    注意: 不含 wss:// 协议部分
    param_str = '&'.join(f'{k}={v}' for k, v in sorted(params.items()))
    sign_str = f"asr.cloud.tencent.com/asr/v2/{appid}?{param_str}"

    # 3. HMAC-SHA1 + Base64
    signature = hmac.new(
        secret_key.encode('utf-8'),
        sign_str.encode('utf-8'),
        hashlib.sha1
    ).digest()
    signature_b64 = base64.b64encode(signature).decode('utf-8')

    # 4. URL 编码签名 (必须编码 +, = 等特殊字符)
    signature_encoded = quote(signature_b64, safe='')

    # 5. 拼接最终 URL
    url = f"wss://asr.cloud.tencent.com/asr/v2/{appid}?{param_str}&signature={signature_encoded}"
    return url
```

### 3.3 消息协议

#### 握手阶段

WebSocket 连接建立后，服务端自动验证 URL 签名参数，返回:

```json
{
  "code": 0,
  "message": "success",
  "voice_id": "RnKu9FODFHK5FPpsrN"
}
```

`code` 非 0 表示握手失败。

#### 音频发送

**直接发送二进制帧** (WebSocket binary message)，不需要 JSON 包装或 Base64:

```dart
// 每 200ms 发送 200ms 的音频数据
// 16kHz × 16bit × 200ms = 6400 bytes
ws.send(binaryAudioChunk);  // Uint8List
```

**发送节奏:**
- 建议 200ms 间隔发送 200ms 音频 (1:1 实时率)
- 16kHz: 每包 6400 bytes
- 8kHz: 每包 3200 bytes
- **不能超过 1:1 实时率**
- **包间隔不能超过 6 秒**
- **15 秒无数据自动断连**

#### 结束信号

音频发送完毕后，发送 **文本帧**:

```json
{"type": "end"}
```

#### 接收识别结果

服务端持续返回 JSON 文本帧:

```json
{
  "code": 0,
  "message": "success",
  "voice_id": "CzhjnqBkv8lk5pRUxhpX",
  "message_id": "CzhjnqBkv8lk5pRUxhpX_11_0",
  "result": {
    "slice_type": 1,
    "index": 3,
    "start_time": 1500,
    "end_time": 3200,
    "voice_text_str": "今天天气",
    "word_size": 2,
    "word_list": [
      {
        "word": "今天",
        "start_time": 1500,
        "end_time": 2100,
        "stable_flag": 1
      },
      {
        "word": "天气",
        "start_time": 2100,
        "end_time": 3200,
        "stable_flag": 0
      }
    ]
  },
  "final": 0
}
```

#### 最终结束消息

```json
{
  "code": 0,
  "message": "success",
  "voice_id": "CzhjnqBkv8lk5pRUxhpX",
  "message_id": "CzhjnqBkv8lk5pRUxhpX_241",
  "final": 1
}
```

### 3.4 result 字段说明

| 字段 | 说明 |
|------|------|
| `slice_type` | **0** = 一段话开始, **1** = 识别中 (不稳定), **2** = 一段话结束 (稳定) |
| `index` | 当前结果序号 |
| `start_time` | 起始时间 (ms) |
| `end_time` | 结束时间 (ms) |
| `voice_text_str` | **当前段识别文本** |
| `word_list[]` | 词级别详情 (需开启 `word_info=1`) |
| `word_list[].stable_flag` | `1` = 稳定词 (不再变化), `0` = 不稳定 |

**`final`**: `1` = 识别彻底完成 (收到 `{"type":"end"}` 后的确认)

### 3.5 结果拼接逻辑

```dart
String committedText = '';
String currentSegment = '';

void handleResult(Map<String, dynamic> result) {
  final sliceType = result['slice_type'] as int;
  final text = result['voice_text_str'] as String;

  switch (sliceType) {
    case 0:  // 新段开始
      currentSegment = text;
      break;
    case 1:  // 识别中 (可能变化)
      currentSegment = text;
      break;
    case 2:  // 段结束 (稳定)
      committedText += text;
      currentSegment = '';
      break;
  }

  // 实时显示: committedText + currentSegment
  emit(committedText + currentSegment);
}
```

### 3.6 音频要求

- **格式**: PCM (推荐), 也支持 WAV/Opus/Speex/Silk/MP3/M4A/AAC
- **采样率**: 16000 Hz (推荐) 或 8000 Hz
- **位深**: 16-bit
- **声道**: 单声道
- **传输方式**: **直接 binary 帧** (不需要 Base64)
- **每包大小**: 200ms 音频 = 6400 bytes (16kHz)

### 3.7 其他特性

| 特性 | 支持情况 |
|------|---------|
| 中英混合识别 | 支持 (`16k_zh_en` 引擎) |
| 标点 | 默认包含, `filter_punc=1` 可过滤句末句号 |
| 语气词过滤 | 支持 (`filter_modal`) |
| 脏词过滤 | 支持 (`filter_dirty`) |
| 词级别时间戳 | 支持 (`word_info=1`) |
| VAD | 支持 (`needvad=1`) |
| 并发限制 | 默认 200 路 |
| 时长限制 | 超 60 秒建议开启 VAD，无硬性上限 |

---

## 四、对比总结

| 特性 | 火山引擎 (V3) | 讯飞 | 腾讯云 |
|------|--------------|------|-------|
| **协议** | 自定义二进制帧 | JSON 文本帧 | 二进制音频 + JSON 响应 |
| **音频传输** | Binary (原始 PCM) | Base64 in JSON | Binary (原始 PCM) |
| **鉴权** | HTTP Headers | URL 签名 (HMAC-SHA256) | URL 签名 (HMAC-SHA1) |
| **结束信号** | 最后一包 flag=0b0010 | `{"data":{"status":2}}` | `{"type":"end"}` |
| **中间/最终结果** | type=interim/final | pgs=apd/rpl + sn 拼接 | slice_type=0/1/2 |
| **中英混合** | 支持 | 支持 (简单英文) | 支持 (16k_zh_en) |
| **标点** | 支持 | 支持 | 支持 |
| **最大时长** | 无硬性限制 | **60 秒** | 无硬性限制 (开启 VAD) |
| **并发** | QPS 限制 | 50 路 | 200 路 |
| **实现复杂度** | 高 (二进制帧解析) | 中 (签名复杂，但 JSON 简单) | 低 (签名简单，binary+JSON) |
| **凭证** | app_id + access_token + resource_id | app_id + api_key + api_secret | secret_id + secret_key + appid |

### 实现优先级建议

1. **腾讯云** — 协议最简单 (binary audio + JSON response)，签名算法简单 (HMAC-SHA1)
2. **讯飞** — JSON 文本帧较直观，但签名复杂 (HMAC-SHA256 + 多层 Base64)，60 秒限制需注意
3. **火山引擎** — 自定义二进制帧协议最复杂，但精度最高 (Seed-ASR)

---

## 五、与现有 DashScope Provider 的对比

现有 `DashScopeASRProvider` 的协议特点:
- JSON 文本帧 + Binary 音频帧 (混合)
- `run-task` / `finish-task` 指令
- sentence 级别的中间/最终结果 (`end_time >= 0` 判断)
- Bearer token 鉴权 (HTTP Header)

三家新 Provider 的实现模式各不相同，建议为每家创建独立的 Provider 类，不适合抽象出通用的 "CloudASRProvider" 基类。
