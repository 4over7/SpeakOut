
import { Hono } from 'hono';

const app = new Hono();

// ═══════════════════════════════════════════════════════════
// 套餐定义
// ═══════════════════════════════════════════════════════════
const PLANS = {
  free:  { id: 'free',  seconds: 1800,  priceCny: 0,    priceUsd: 0,    name: '免费体验',  nameEn: 'Free' },
  basic: { id: 'basic', seconds: 18000, priceCny: 990,  priceUsd: 199,  name: '基础版',    nameEn: 'Basic' },
  pro:   { id: 'pro',   seconds: 72000, priceCny: 2990, priceUsd: 499,  name: '专业版',    nameEn: 'Pro' },
};

// ═══════════════════════════════════════════════════════════
// CORS & 预检
// ═══════════════════════════════════════════════════════════
app.use('*', async (c, next) => {
    await next();
});
app.options('*', (c) => c.body(null, 204));

// ═══════════════════════════════════════════════════════════
// 0. 版本检查
// ═══════════════════════════════════════════════════════════
app.get('/version', async (c) => {
    // 记录客户端版本统计（fire-and-forget）
    const clientVersion = c.req.query('v') || 'unknown';
    const clientBuild = c.req.query('b') || '0';
    try {
        const key = `stats:version:${clientVersion}`;
        const current = parseInt(await c.env.SPEAKOUT_DB.get(key) || '0');
        await c.env.SPEAKOUT_DB.put(key, String(current + 1));
        // 记录最近活跃（按天）
        const today = new Date().toISOString().split('T')[0];
        const dailyKey = `stats:daily:${today}`;
        const daily = parseInt(await c.env.SPEAKOUT_DB.get(dailyKey) || '0');
        await c.env.SPEAKOUT_DB.put(dailyKey, String(daily + 1), { expirationTtl: 90 * 86400 });
    } catch (_) {}

    return c.json({
        version: '1.7.0',
        build: 208,
        download_url: 'https://github.com/4over7/SpeakOut/releases/latest',
        dmg_url: 'https://github.com/4over7/SpeakOut/releases/download/v1.6.1/SpeakOut.dmg',
        release_notes: '',
    });
});

// ═══════════════════════════════════════════════════════════
// 0.5 版本统计查询
// ═══════════════════════════════════════════════════════════
app.get('/stats', async (c) => {
    const versions = {};
    const list = await c.env.SPEAKOUT_DB.list({ prefix: 'stats:version:' });
    for (const key of list.keys) {
        const v = key.name.replace('stats:version:', '');
        versions[v] = parseInt(await c.env.SPEAKOUT_DB.get(key.name) || '0');
    }
    const daily = {};
    const dList = await c.env.SPEAKOUT_DB.list({ prefix: 'stats:daily:' });
    for (const key of dList.keys) {
        const d = key.name.replace('stats:daily:', '');
        daily[d] = parseInt(await c.env.SPEAKOUT_DB.get(key.name) || '0');
    }
    return c.json({ versions, daily });
});

// ═══════════════════════════════════════════════════════════
// Helper: 提取 Authorization
// ═══════════════════════════════════════════════════════════
function extractAuth(c) {
    const authHeader = c.req.header('Authorization');
    if (!authHeader) return null;
    return authHeader.replace('Bearer ', '').trim() || null;
}

// ═══════════════════════════════════════════════════════════
// 1. 验证许可证 (Legacy — 保留向后兼容)
// ═══════════════════════════════════════════════════════════
app.post('/verify', async (c) => {
    const licenseKey = extractAuth(c);
    if (!licenseKey) return c.json({ error: 'Missing key' }, 401);
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Invalid License Key' }, 403);
    if (userData.expiry && new Date(userData.expiry) < new Date()) {
        return c.json({ error: 'License Expired' }, 403);
    }
    return c.json({ valid: true, type: userData.type, balance: userData.balance || 999999 });
});

// ═══════════════════════════════════════════════════════════
// 2. 卡密充值 (Legacy — 保留向后兼容)
// ═══════════════════════════════════════════════════════════
app.post('/redeem', async (c) => {
    const licenseKey = extractAuth(c);
    if (!licenseKey) return c.json({ error: 'Missing key' }, 401);
    const { code } = await c.req.json();
    if (!code || typeof code !== 'string') return c.json({ error: 'Missing code' }, 400);
    const codeKey = `CODE:${code}`;
    const codeData = await c.env.SPEAKOUT_DB.get(codeKey, { type: 'json' });
    if (!codeData) return c.json({ error: 'Invalid Code' }, 400);
    if (codeData.used) return c.json({ error: 'Code Already Used' }, 409);
    codeData.used = true;
    codeData.usedBy = licenseKey;
    codeData.usedAt = new Date().toISOString();
    await c.env.SPEAKOUT_DB.put(codeKey, JSON.stringify(codeData));
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Invalid License' }, 403);
    const amount = codeData.value || 0;
    userData.balance = (userData.balance || 0) + amount;
    await c.env.SPEAKOUT_DB.put(licenseKey, JSON.stringify(userData));
    return c.json({ success: true, added: amount, new_balance: userData.balance });
});

// ═══════════════════════════════════════════════════════════
// 3. 管理员: 生成卡密
// ═══════════════════════════════════════════════════════════
app.post('/admin/generate', async (c) => {
    const adminKey = c.req.header('Admin-Key');
    if (adminKey !== c.env.ADMIN_SECRET) return c.json({ error: 'Unauthorized' }, 401);
    const { amount, count, prefix } = await c.req.json();
    if (typeof amount !== 'number' || amount <= 0) return c.json({ error: 'Invalid amount' }, 400);
    if (typeof count !== 'number' || count <= 0 || count > 100) return c.json({ error: 'Invalid count (1-100)' }, 400);
    if (typeof prefix !== 'string' || !prefix) return c.json({ error: 'Invalid prefix' }, 400);
    const generatedCodes = [];
    for (let i = 0; i < count; i++) {
        const bytes = new Uint8Array(8);
        crypto.getRandomValues(bytes);
        const randomSuffix = Array.from(bytes).map(b => b.toString(36)).join('').substring(0, 8).toUpperCase();
        const code = `${prefix}-${randomSuffix}`;
        await c.env.SPEAKOUT_DB.put(`CODE:${code}`, JSON.stringify({
            type: 'recharge_code', value: amount, used: false, createdAt: new Date().toISOString()
        }));
        generatedCodes.push(code);
    }
    return c.json({ success: true, codes: generatedCodes });
});

// ═══════════════════════════════════════════════════════════
// 4. 设备注册
// ═══════════════════════════════════════════════════════════
app.post('/device/register', async (c) => {
    const { deviceId } = await c.req.json();
    if (!deviceId) return c.json({ error: 'Missing deviceId' }, 400);

    const key = `device:${deviceId}`;
    let device = await c.env.SPEAKOUT_DB.get(key, { type: 'json' });

    if (!device) {
        const now = new Date();
        device = {
            createdAt: now.toISOString(),
            planId: 'free',
            periodStart: now.toISOString().split('T')[0],
            periodEnd: addDays(now, 30).toISOString().split('T')[0],
            secondsUsed: 0,
            secondsLimit: PLANS.free.seconds,
            totalPaid: 0,
        };
        await c.env.SPEAKOUT_DB.put(key, JSON.stringify(device));
    }

    lazyReset(device);
    return c.json({
        planId: device.planId,
        secondsUsed: device.secondsUsed,
        secondsLimit: device.secondsLimit,
        periodEnd: device.periodEnd,
        secondsRemaining: Math.max(0, device.secondsLimit - device.secondsUsed),
    });
});

// ═══════════════════════════════════════════════════════════
// 5. 查询配额
// ═══════════════════════════════════════════════════════════
app.get('/billing/status', async (c) => {
    const deviceId = extractAuth(c);
    if (!deviceId) return c.json({ error: 'Missing deviceId' }, 401);

    const key = `device:${deviceId}`;
    const device = await c.env.SPEAKOUT_DB.get(key, { type: 'json' });
    if (!device) return c.json({ error: 'Device not registered' }, 404);

    if (lazyReset(device)) {
        await c.env.SPEAKOUT_DB.put(key, JSON.stringify(device));
    }

    return c.json({
        planId: device.planId,
        secondsUsed: device.secondsUsed,
        secondsLimit: device.secondsLimit,
        periodStart: device.periodStart,
        periodEnd: device.periodEnd,
        secondsRemaining: Math.max(0, device.secondsLimit - device.secondsUsed),
    });
});

// ═══════════════════════════════════════════════════════════
// 6. 上报使用量
// ═══════════════════════════════════════════════════════════
app.post('/billing/usage', async (c) => {
    const deviceId = extractAuth(c);
    if (!deviceId) return c.json({ error: 'Missing deviceId' }, 401);

    const { seconds } = await c.req.json();
    if (typeof seconds !== 'number' || seconds <= 0) return c.json({ success: true, secondsRemaining: 0 });

    const key = `device:${deviceId}`;
    const device = await c.env.SPEAKOUT_DB.get(key, { type: 'json' });
    if (!device) return c.json({ error: 'Device not registered' }, 404);

    lazyReset(device);
    device.secondsUsed += seconds;
    await c.env.SPEAKOUT_DB.put(key, JSON.stringify(device));

    return c.json({
        success: true,
        secondsRemaining: Math.max(0, device.secondsLimit - device.secondsUsed),
    });
});

// ═══════════════════════════════════════════════════════════
// 7. 创建订单
// ═══════════════════════════════════════════════════════════
app.post('/billing/order', async (c) => {
    const deviceId = extractAuth(c);
    if (!deviceId) return c.json({ error: 'Missing deviceId' }, 401);

    const { planId, channel } = await c.req.json();
    const plan = PLANS[planId];
    if (!plan || plan.id === 'free') return c.json({ error: 'Invalid plan' }, 400);
    if (!['alipay', 'stripe'].includes(channel)) return c.json({ error: 'Invalid channel' }, 400);

    // 验证设备存在
    const deviceKey = `device:${deviceId}`;
    const device = await c.env.SPEAKOUT_DB.get(deviceKey, { type: 'json' });
    if (!device) return c.json({ error: 'Device not registered' }, 404);

    // 生成订单号
    const now = new Date();
    const dateStr = now.toISOString().split('T')[0].replace(/-/g, '');
    const randBytes = new Uint8Array(4);
    crypto.getRandomValues(randBytes);
    const randStr = Array.from(randBytes).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    const orderId = `SO-${dateStr}-${randStr}`;

    const order = {
        orderId,
        deviceId,
        planId: plan.id,
        amount: channel === 'alipay' ? plan.priceCny : plan.priceUsd,
        currency: channel === 'alipay' ? 'CNY' : 'USD',
        channel,
        status: 'pending',
        createdAt: now.toISOString(),
        paidAt: null,
        externalTradeNo: null,
        secondsToAdd: plan.seconds,
    };

    await c.env.SPEAKOUT_DB.put(`order:${orderId}`, JSON.stringify(order));

    // 调支付 API
    if (channel === 'alipay') {
        try {
            const qrCode = await alipayPrecreate(c.env, order);
            return c.json({ orderId, qrCode, expiresIn: 900 });
        } catch (e) {
            return c.json({ error: `Alipay error: ${e.message}` }, 500);
        }
    } else {
        try {
            const checkoutUrl = await stripeCreateCheckout(c.env, order);
            return c.json({ orderId, checkoutUrl });
        } catch (e) {
            return c.json({ error: `Stripe error: ${e.message}` }, 500);
        }
    }
});

// ═══════════════════════════════════════════════════════════
// 8. 查询订单状态
// ═══════════════════════════════════════════════════════════
app.get('/billing/order/:orderId', async (c) => {
    const deviceId = extractAuth(c);
    if (!deviceId) return c.json({ error: 'Missing deviceId' }, 401);

    const orderId = c.req.param('orderId');
    const order = await c.env.SPEAKOUT_DB.get(`order:${orderId}`, { type: 'json' });
    if (!order) return c.json({ error: 'Order not found' }, 404);
    if (order.deviceId !== deviceId) return c.json({ error: 'Unauthorized' }, 403);

    return c.json({ orderId: order.orderId, status: order.status, planId: order.planId });
});

// ═══════════════════════════════════════════════════════════
// 9. 支付宝异步通知
// ═══════════════════════════════════════════════════════════
app.post('/payment/alipay', async (c) => {
    const body = await c.req.text();
    const params = Object.fromEntries(new URLSearchParams(body));

    // 验签
    const verified = await alipayVerifyNotify(c.env, params);
    if (!verified) return c.text('fail');

    if (params.trade_status !== 'TRADE_SUCCESS' && params.trade_status !== 'TRADE_FINISHED') {
        return c.text('success');
    }

    const orderId = params.out_trade_no;
    const order = await c.env.SPEAKOUT_DB.get(`order:${orderId}`, { type: 'json' });
    if (!order) return c.text('fail');

    // 幂等: 已处理的订单直接返回
    if (order.status === 'paid') return c.text('success');

    // 验证金额一致
    const paidAmount = Math.round(parseFloat(params.total_amount) * 100);
    if (paidAmount !== order.amount) {
        console.error(`Amount mismatch: expected ${order.amount}, got ${paidAmount}`);
        return c.text('fail');
    }

    // 更新订单
    order.status = 'paid';
    order.paidAt = new Date().toISOString();
    order.externalTradeNo = params.trade_no;
    await c.env.SPEAKOUT_DB.put(`order:${orderId}`, JSON.stringify(order));

    // 充值额度
    await topUpQuota(c.env, order.deviceId, order.secondsToAdd, order.planId, order.amount);

    return c.text('success');
});

// ═══════════════════════════════════════════════════════════
// 10. Stripe Webhook
// ═══════════════════════════════════════════════════════════
app.post('/payment/stripe', async (c) => {
    const signature = c.req.header('Stripe-Signature');
    if (!signature) return c.json({ error: 'Missing signature' }, 400);

    const body = await c.req.text();
    const verified = await stripeVerifyWebhook(c.env, body, signature);
    if (!verified) return c.json({ error: 'Invalid signature' }, 400);

    const event = JSON.parse(body);
    if (event.type !== 'checkout.session.completed') return c.json({ received: true });

    const session = event.data.object;
    const orderId = session.metadata?.orderId;
    if (!orderId) return c.json({ received: true });

    const order = await c.env.SPEAKOUT_DB.get(`order:${orderId}`, { type: 'json' });
    if (!order) return c.json({ received: true });

    // 幂等
    if (order.status === 'paid') return c.json({ received: true });

    order.status = 'paid';
    order.paidAt = new Date().toISOString();
    order.externalTradeNo = session.payment_intent || session.id;
    await c.env.SPEAKOUT_DB.put(`order:${orderId}`, JSON.stringify(order));

    await topUpQuota(c.env, order.deviceId, order.secondsToAdd, order.planId, order.amount);

    return c.json({ received: true });
});

// ═══════════════════════════════════════════════════════════
// 套餐列表 (客户端获取可用套餐)
// ═══════════════════════════════════════════════════════════
app.get('/billing/plans', (c) => {
    return c.json({ plans: Object.values(PLANS) });
});

// ═══════════════════════════════════════════════════════════
// Helper Functions
// ═══════════════════════════════════════════════════════════

function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

/** 懒重置：如果当前周期已过期，重置 secondsUsed 并顺延周期 */
function lazyReset(device) {
    const now = new Date();
    const end = new Date(device.periodEnd + 'T23:59:59Z');
    if (now <= end) return false;

    device.secondsUsed = 0;
    const newStart = now.toISOString().split('T')[0];
    device.periodStart = newStart;
    device.periodEnd = addDays(now, 30).toISOString().split('T')[0];

    // 非免费用户过期后降级为免费
    // (如果是订阅制，到期不续费应该降级)
    if (device.planId !== 'free') {
        device.planId = 'free';
        device.secondsLimit = PLANS.free.seconds;
    }
    return true;
}

/** 充值额度 */
async function topUpQuota(env, deviceId, secondsToAdd, planId, amountPaid) {
    const key = `device:${deviceId}`;
    const device = await env.SPEAKOUT_DB.get(key, { type: 'json' });
    if (!device) return;

    lazyReset(device);

    const plan = PLANS[planId];
    if (plan) {
        // 升级或续费：设置新套餐额度
        device.planId = planId;
        device.secondsLimit = plan.seconds;
        device.secondsUsed = 0;
        const now = new Date();
        device.periodStart = now.toISOString().split('T')[0];
        device.periodEnd = addDays(now, 30).toISOString().split('T')[0];
    } else {
        // 未知套餐：直接叠加时长
        device.secondsLimit += secondsToAdd;
    }
    device.totalPaid = (device.totalPaid || 0) + (amountPaid || 0);

    await env.SPEAKOUT_DB.put(key, JSON.stringify(device));
}

// ═══════════════════════════════════════════════════════════
// 支付宝当面付 (Web Crypto API — 零依赖)
// ═══════════════════════════════════════════════════════════

/** 预下单：生成付款二维码 */
async function alipayPrecreate(env, order) {
    const appId = env.ALIPAY_APP_ID;
    const privateKeyPem = env.ALIPAY_PRIVATE_KEY;
    const notifyUrl = env.ALIPAY_NOTIFY_URL || `${env.GATEWAY_URL || 'https://speakout-gateway.4over7.workers.dev'}/payment/alipay`;

    const plan = PLANS[order.planId];
    const amountYuan = (order.amount / 100).toFixed(2);

    const bizContent = JSON.stringify({
        out_trade_no: order.orderId,
        total_amount: amountYuan,
        subject: `子曰 SpeakOut ${plan?.name || order.planId}`,
    });

    const params = {
        app_id: appId,
        method: 'alipay.trade.precreate',
        charset: 'utf-8',
        sign_type: 'RSA2',
        timestamp: formatAlipayTime(new Date()),
        version: '1.0',
        notify_url: notifyUrl,
        biz_content: bizContent,
    };

    // 签名
    const sign = await alipaySign(privateKeyPem, params);
    params.sign = sign;

    // 发送请求
    const formBody = Object.entries(params)
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
        .join('&');

    const resp = await fetch('https://openapi.alipay.com/gateway.do', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8' },
        body: formBody,
    });

    const result = await resp.json();
    const precreateResp = result.alipay_trade_precreate_response;

    if (!precreateResp || precreateResp.code !== '10000') {
        throw new Error(precreateResp?.sub_msg || precreateResp?.msg || 'Precreate failed');
    }

    return precreateResp.qr_code;
}

/** RSA2 签名 */
async function alipaySign(privateKeyPem, params) {
    const sorted = Object.keys(params).sort();
    const signStr = sorted.map(k => `${k}=${params[k]}`).join('&');

    const key = await importPkcs8Key(privateKeyPem);
    const data = new TextEncoder().encode(signStr);
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, data);
    return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

/** 验证支付宝异步通知签名 */
async function alipayVerifyNotify(env, params) {
    const sign = params.sign;
    const signType = params.sign_type;
    if (!sign || signType !== 'RSA2') return false;

    // 排除 sign 和 sign_type，按 key 排序拼接
    const sorted = Object.keys(params)
        .filter(k => k !== 'sign' && k !== 'sign_type')
        .sort();
    const signStr = sorted.map(k => `${k}=${params[k]}`).join('&');

    const publicKeyPem = env.ALIPAY_PUBLIC_KEY;
    const key = await importSpkiKey(publicKeyPem);
    const data = new TextEncoder().encode(signStr);
    const sigBytes = Uint8Array.from(atob(sign), c => c.charCodeAt(0));

    return crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sigBytes, data);
}

/** 导入 PKCS#8 私钥 */
async function importPkcs8Key(pem) {
    const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
    const binary = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    return crypto.subtle.importKey('pkcs8', binary, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

/** 导入 SPKI 公钥 */
async function importSpkiKey(pem) {
    const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
    const binary = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    return crypto.subtle.importKey('spki', binary, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
}

function formatAlipayTime(date) {
    const pad = n => n.toString().padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

// ═══════════════════════════════════════════════════════════
// Stripe Checkout (fetch API — 零依赖)
// ═══════════════════════════════════════════════════════════

/** 创建 Stripe Checkout Session */
async function stripeCreateCheckout(env, order) {
    const plan = PLANS[order.planId];
    const params = new URLSearchParams({
        'payment_method_types[]': 'card',
        'mode': 'payment',
        'success_url': `${env.GATEWAY_URL || 'https://speakout-gateway.4over7.workers.dev'}/payment/stripe/success?order=${order.orderId}`,
        'cancel_url': `${env.GATEWAY_URL || 'https://speakout-gateway.4over7.workers.dev'}/payment/stripe/cancel`,
        'line_items[0][price_data][currency]': 'usd',
        'line_items[0][price_data][unit_amount]': order.amount.toString(),
        'line_items[0][price_data][product_data][name]': `SpeakOut ${plan?.nameEn || order.planId}`,
        'line_items[0][quantity]': '1',
        'metadata[orderId]': order.orderId,
        'metadata[deviceId]': order.deviceId,
    });

    const resp = await fetch('https://api.stripe.com/v1/checkout/sessions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${env.STRIPE_SECRET_KEY}`,
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
    });

    const session = await resp.json();
    if (session.error) throw new Error(session.error.message);
    return session.url;
}

/** 验证 Stripe Webhook 签名 (HMAC-SHA256) */
async function stripeVerifyWebhook(env, body, signatureHeader) {
    const secret = env.STRIPE_WEBHOOK_SECRET;
    if (!secret) return false;

    // Parse Stripe-Signature: t=xxx,v1=xxx
    const parts = Object.fromEntries(
        signatureHeader.split(',').map(p => {
            const [k, v] = p.split('=');
            return [k.trim(), v];
        })
    );
    const timestamp = parts.t;
    const expectedSig = parts.v1;
    if (!timestamp || !expectedSig) return false;

    // 防重放: 300秒内
    const age = Math.floor(Date.now() / 1000) - parseInt(timestamp);
    if (age > 300) return false;

    const payload = `${timestamp}.${body}`;
    const key = await crypto.subtle.importKey(
        'raw',
        new TextEncoder().encode(secret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
    );
    const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
    const computed = Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');

    return computed === expectedSig;
}

// Stripe 支付成功/取消页面（用户浏览器跳转后看到的）
app.get('/payment/stripe/success', (c) => {
    return c.html('<html><body style="text-align:center;padding:60px;font-family:sans-serif"><h2>Payment Successful!</h2><p>Your quota has been updated. You can close this page.</p></body></html>');
});
app.get('/payment/stripe/cancel', (c) => {
    return c.html('<html><body style="text-align:center;padding:60px;font-family:sans-serif"><h2>Payment Cancelled</h2><p>No charges were made. You can close this page.</p></body></html>');
});

export default app;
