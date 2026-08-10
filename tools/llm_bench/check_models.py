#!/usr/bin/env python3
"""对账：代码里写死的模型清单 vs 各家 /models 接口返回的真实可用模型。

目的是发现「代码里的模型已被服务商下线」——DeepSeek 那次 deepseek-chat 停用
导致润色整个失效，就是这类问题。
"""
import json, re, subprocess, urllib.request, urllib.error, os

PLIST = os.path.expanduser("~/Library/Preferences/com.speakout.speakout.plist")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def plist_str(key):
    out = subprocess.run(["plutil", "-p", PLIST], capture_output=True, text=True).stdout
    m = re.search(r'"%s"\s*=>\s*"(.*)"\s*$' % re.escape(key), out, re.M)
    return m.group(1) if m else None

accounts = json.loads(plist_str("flutter.cloud_accounts").replace('\\"', '"'))
acct_by_pid = {a["providerId"]: a for a in accounts}

# 从 Dart 源码解析：providerId -> (baseUrl, defaultModel, [声明的模型])
src = open(f"{REPO}/lib/config/cloud_providers.dart").read()
declared = {}
for b in re.split(r'CloudProvider\(', src)[1:]:
    pid = re.search(r"id:\s*'([^']+)'", b)
    url = re.search(r"llmBaseUrl:\s*'([^']+)'", b)
    dm  = re.search(r"llmDefaultModel:\s*'([^']+)'", b)
    models = re.findall(r"CloudLLMModel\(\s*id:\s*'([^']+)'", b)
    if pid and url:
        declared[pid.group(1)] = dict(base=url.group(1),
                                      default=dm.group(1) if dm else None,
                                      models=models)

def list_models(base, key):
    req = urllib.request.Request(f"{base}/models",
                                 headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    items = data.get("data", data if isinstance(data, list) else [])
    return sorted(str(m.get("id", m)) for m in items)

for pid, info in declared.items():
    acc = acct_by_pid.get(pid)
    if not acc or not acc.get("credentialKeys"):
        continue
    key = plist_str(f"flutter.cloud_cred_{acc['id']}_api_key")
    if not key:
        continue
    print(f"\n{'='*72}\n{pid}   代码默认: {info['default']}")
    try:
        live = list_models(info["base"], key)
    except urllib.error.HTTPError as e:
        print(f"  /models 不可用 (HTTP {e.code})，跳过对账")
        continue
    except Exception as e:
        print(f"  /models 失败: {type(e).__name__}")
        continue

    print(f"  线上共 {len(live)} 个模型")
    # 1) 代码里声明的模型，线上还在不在
    missing = [m for m in info["models"] if m not in live]
    if missing:
        print(f"  ⚠️  代码里声明但线上已无: {', '.join(missing)}")
    else:
        print(f"  ✅ 代码声明的 {len(info['models'])} 个模型线上都在")
    if info["default"] and info["default"] not in live:
        print(f"  🚨 默认模型 {info['default']} 线上不存在！")

    # 2) 线上有、代码里没有的（可能是新出的）
    known = set(info["models"])
    extra = [m for m in live if m not in known]
    if extra:
        show = extra[:25]
        print(f"  线上未收录进代码的（前 {len(show)}/{len(extra)}）:")
        for i in range(0, len(show), 3):
            print("     " + "  ".join(f"{m:<34}" for m in show[i:i+3]))
