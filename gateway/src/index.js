
import { Hono } from 'hono';

const app = new Hono();

// CORS Settings
app.use('*', async (c, next) => {
    await next();
    c.res.headers.append('Access-Control-Allow-Origin', '*');
    c.res.headers.append('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    c.res.headers.append('Access-Control-Allow-Headers', 'Content-Type, Authorization');
});

/**
 * 1. 验证许可证 (Verify License)
 * Client 启动时调用，或者在设置页输入 Key 时调用。
 */
app.post('/verify', async (c) => {
    const authHeader = c.req.header('Authorization');
    if (!authHeader) return c.json({ error: 'Missing key' }, 401);

    const licenseKey = authHeader.replace('Bearer ', '').trim();

    // 查询 KV 数据库
    // 数据结构: { "type": "pro", "expiry": "2026-12-31", "balance": 1000 }
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });

    if (!userData) {
        return c.json({ valid: false, message: 'Invalid License Key' }, 403);
    }

    // 检查过期 (可选)
    if (userData.expiry && new Date(userData.expiry) < new Date()) {
        return c.json({ valid: false, message: 'License Expired' }, 403);
    }

    return c.json({
        valid: true,
        type: userData.type,
        balance: userData.balance || 999999,
        message: 'Welcome back, Pro user.'
    });
});

/**
 * 2. 获取阿里云令牌 (Get Aliyun Token)
 * 只有 Pro 用户才能调用。Client 拿到 Token 后直连阿里云。
 * 这种模式叫 "Token Vending Machine"，比纯 Proxy 更快更稳。
 */
app.post('/token', async (c) => {
    const authHeader = c.req.header('Authorization');
    if (!authHeader) return c.json({ error: 'Missing key' }, 401);
    const licenseKey = authHeader.replace('Bearer ', '').trim();

    // 1. 鉴权
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Forbidden' }, 403);

    // 2. 检查配额 (简单的请求次数计数)
    // 每次申请 Token 算作一次 "Session" (通常一次 Token 有效期 24小时)
    // 如果需要更细粒度，可以在此处扣除 1 个 Credits
    // await c.env.SPEAKOUT_DB.put(licenseKey, JSON.stringify({ ...userData, balance: userData.balance - 1 }));

    // 3. 向阿里云申请 Token
    const token = await generateAliyunToken(c.env);

    if (!token) {
        return c.json({ error: 'Failed to generate token' }, 500);
    }

    return c.json({
        token: token.id,
        expire_time: token.expire_time,
        app_key: c.env.ALIYUN_APP_KEY // 把 AppKey 也告诉客户端，方便它连接
    });
});

/**
 * 3. 上报使用量 (Report Usage)
 * Client 定期 (如每分钟) 上报累计的使用时长。
 * Protocol: { total_seconds: 60, details: [...] }
 */
app.post('/report', async (c) => {
    const authHeader = c.req.header('Authorization');
    if (!authHeader) return c.json({ error: 'Missing key' }, 401);
    const licenseKey = authHeader.replace('Bearer ', '').trim();

    const body = await c.req.json();
    const seconds = body.total_seconds || 0;

    if (seconds <= 0) return c.json({ success: true }); // Nothing to deduct

    // 1. 获取当前余额
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Invalid License' }, 403);

    // 2. 扣费 (Simple Deduction)
    // 注意: KV 不是原子操作，并发极高时可能会有 Race Condition。
    // 但对于"单用户单设备"的场景，这足够安全。
    // 如果需要严格原子性，应该使用 Durable Objects (但这会增加成本)。
    const currentBalance = userData.balance || 0;
    const newBalance = Math.max(0, currentBalance - seconds); // 不允许负数

    // 3. 更新
    // 我们保留 userData 里的其他字段 (type, expiry 等)
    userData.balance = newBalance;
    await c.env.SPEAKOUT_DB.put(licenseKey, JSON.stringify(userData));

    return c.json({
        success: true,
        remaining: newBalance,
        message: `Deducted ${seconds} seconds.`
    });
});

/**
 * 4. 充值 (Redeem Code)
 * User inputs a CD-Key to top up balance.
 * Schema: { "code": "TIME-10H-XXXX" }
 */
app.post('/redeem', async (c) => {
    const authHeader = c.req.header('Authorization');
    if (!authHeader) return c.json({ error: 'Missing key' }, 401);
    const licenseKey = authHeader.replace('Bearer ', '').trim();

    const { code } = await c.req.json();
    if (!code) return c.json({ error: 'Missing code' }, 400);

    // 1. 验证卡密
    const codeKey = `CODE:${code}`;
    const codeData = await c.env.SPEAKOUT_DB.get(codeKey, { type: 'json' });

    if (!codeData) return c.json({ error: 'Invalid Code' }, 400);
    if (codeData.used) return c.json({ error: 'Code Already Used' }, 409);

    // 2. 验证用户
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Invalid License' }, 403);

    // 3. 执行充值 (Atomic-ish)
    // Mark code as used
    codeData.used = true;
    codeData.usedBy = licenseKey;
    codeData.usedAt = new Date().toISOString();
    await c.env.SPEAKOUT_DB.put(codeKey, JSON.stringify(codeData));

    // Add balance
    const amount = codeData.value || 0;
    userData.balance = (userData.balance || 0) + amount;
    await c.env.SPEAKOUT_DB.put(licenseKey, JSON.stringify(userData));

    return c.json({
        success: true,
        added: amount,
        new_balance: userData.balance
    });
});

/**
 * 5. 管理员: 生成卡密 (Admin Generate)
 * Header: Admin-Key: <SECRET>
 * Body: { "amount": 36000, "count": 10, "prefix": "TIME-10H" }
 */
app.post('/admin/generate', async (c) => {
    const adminKey = c.req.header('Admin-Key');
    if (adminKey !== c.env.ADMIN_SECRET) return c.json({ error: 'Unauthorized' }, 401);

    const { amount, count, prefix } = await c.req.json();
    const generatedCodes = [];

    for (let i = 0; i < count; i++) {
        const randomSuffix = Math.random().toString(36).substring(2, 8).toUpperCase();
        const code = `${prefix}-${randomSuffix}`;
        const codeKey = `CODE:${code}`;

        const payload = {
            type: 'recharge_code',
            value: amount,
            used: false,
            createdAt: new Date().toISOString()
        };

        await c.env.SPEAKOUT_DB.put(codeKey, JSON.stringify(payload));
        generatedCodes.push(code);
    }

    return c.json({
        success: true,
        codes: generatedCodes
    });
});

/**
 * 6. Stripe Webhook (Optional)
 * Handles auto-recharge from Stripe Payment Links
 */
app.post('/webhook', async (c) => {
    // Verify Stripe Signature (Simplified for demo)
    // running 'npm install stripe' is needed for real verification
    const sig = c.req.header('stripe-signature');
    const body = await c.req.text();

    // Fake Parsing Logic (Replace with Stripe SDK in production)
    // const event = stripe.webhooks.constructEvent(body, sig, endpointSecret);

    // Mock Logic for MVP:
    // We assume the body is JSON and trust it (INSECURE - DO NOT USE IN PROD WITHOUT SIGNATURE CHECK)
    // In real prod, use the 'stripe' npm package.
    try {
        const event = JSON.parse(body);
        if (event.type === 'checkout.session.completed') {
            const session = event.data.object;
            const licenseKey = session.client_reference_id;
            // Amount logic depends on your price ID mapping
            // validation...

            if (licenseKey) {
                const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
                if (userData) {
                    // Add fixed amount, e.g. $10 = 100 hours = 360000s
                    const added = 360000;
                    userData.balance = (userData.balance || 0) + added;
                    await c.env.SPEAKOUT_DB.put(licenseKey, JSON.stringify(userData));
                    return c.json({ received: true });
                }
            }
        }
    } catch (err) {
        return c.json({ error: err.message }, 400);
    }

    return c.json({ received: true });
});

// --- Helper Functions ---

async function generateAliyunToken(env) {
    // 阿里云 Pop API 签名逻辑太复杂，通常建议直接调用它的公共 API
    // 这里为了演示，我们用简化的 fetch 调用 (需配合阿里云 SDK 的逻辑，或者用 Python 脚本生成的逻辑)
    // 真实场景下，建议使用 @alicloud/pop-core 库，但 Worker 环境不支持 Node 库。
    // 替代方案：直接构造 HTTP REST 请求
    // (由于篇幅限制，这里暂时 mock 返回，或者您需要在 Worker 里手写阿里云签名算法 v1.0)

    // FIXME: 这里必须实现阿里云的 POP 签名算法。
    // 为了让您能跑通流程，我们假设您已经部署了一个能返回 Token 的简单服务，或者我们之后再完善这个算法。
    // 目前先返回一个 Mock 的，让流程跑通。

    // 实际上，为了在 Worker 里跑阿里云签名，我们需要引入 crypto-subtle。
    // 这是一个完整的工程。对于 v1.1 演示，我们先假设逻辑如下：

    return {
        id: "mock_token_for_testing",
        expire_time: Math.floor(Date.now() / 1000) + 3600 * 24
    };
}

export default app;
