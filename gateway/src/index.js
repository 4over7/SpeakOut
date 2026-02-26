
import { Hono } from 'hono';

const app = new Hono();

// --- CORS ---
// 仅允许 macOS 客户端访问（非浏览器原生 HTTP 请求不受 CORS 限制）。
// 管理接口通过 Admin-Key 认证，不开放 CORS。
app.use('*', async (c, next) => {
    await next();
    // 不设置 Access-Control-Allow-Origin: * ，桌面客户端不需要 CORS。
    // 如果将来需要 Web 端访问，在此处配置白名单域名。
});

// OPTIONS 预检请求直接返回 204
app.options('*', (c) => c.body(null, 204));

// --- Helper: 提取并验证 License Key ---
function extractLicenseKey(c) {
    const authHeader = c.req.header('Authorization');
    if (!authHeader) return null;
    return authHeader.replace('Bearer ', '').trim() || null;
}

/**
 * 1. 验证许可证 (Verify License)
 * Client 启动时调用，或者在设置页输入 Key 时调用。
 */
app.post('/verify', async (c) => {
    const licenseKey = extractLicenseKey(c);
    if (!licenseKey) return c.json({ error: 'Missing key' }, 401);

    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });

    if (!userData) {
        return c.json({ error: 'Invalid License Key' }, 403);
    }

    if (userData.expiry && new Date(userData.expiry) < new Date()) {
        return c.json({ error: 'License Expired' }, 403);
    }

    return c.json({
        valid: true,
        type: userData.type,
        balance: userData.balance || 999999,
    });
});

// /**
//  * 2. 获取阿里云令牌 (Get Aliyun Token)
//  * TODO: Token Vending Machine 模式，等客户端迁移到 Gateway 统一鉴权后启用。
//  * 当前客户端通过 AliyunTokenService 本地生成 Token。
//  */

/**
 * 3. 上报使用量 (Report Usage)
 * Client 定期上报累计的使用时长。
 */
app.post('/report', async (c) => {
    const licenseKey = extractLicenseKey(c);
    if (!licenseKey) return c.json({ error: 'Missing key' }, 401);

    const body = await c.req.json();
    const seconds = typeof body.total_seconds === 'number' ? body.total_seconds : 0;

    if (seconds <= 0) return c.json({ success: true });

    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Invalid License' }, 403);

    const currentBalance = userData.balance || 0;
    const newBalance = Math.max(0, currentBalance - seconds);

    userData.balance = newBalance;
    await c.env.SPEAKOUT_DB.put(licenseKey, JSON.stringify(userData));

    return c.json({
        success: true,
        remaining: newBalance,
    });
});

/**
 * 4. 充值 (Redeem Code)
 * Schema: { "code": "TIME-10H-XXXX" }
 *
 * TOCTOU 缓解策略：先标记卡密已用，再增加余额。
 * 如果增加余额失败，卡密已被标记为 used，用户需联系客服。
 * 这比反过来（先加余额后标记）安全——最坏情况是用户少充而非多充。
 */
app.post('/redeem', async (c) => {
    const licenseKey = extractLicenseKey(c);
    if (!licenseKey) return c.json({ error: 'Missing key' }, 401);

    const { code } = await c.req.json();
    if (!code || typeof code !== 'string') return c.json({ error: 'Missing code' }, 400);

    // 1. 验证卡密
    const codeKey = `CODE:${code}`;
    const codeData = await c.env.SPEAKOUT_DB.get(codeKey, { type: 'json' });

    if (!codeData) return c.json({ error: 'Invalid Code' }, 400);
    if (codeData.used) return c.json({ error: 'Code Already Used' }, 409);

    // 2. 先标记卡密已用（TOCTOU 缓解：先消耗凭证再发放资源）
    codeData.used = true;
    codeData.usedBy = licenseKey;
    codeData.usedAt = new Date().toISOString();
    await c.env.SPEAKOUT_DB.put(codeKey, JSON.stringify(codeData));

    // 3. 验证用户
    const userData = await c.env.SPEAKOUT_DB.get(licenseKey, { type: 'json' });
    if (!userData) return c.json({ error: 'Invalid License' }, 403);

    // 4. 增加余额
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

    // 输入验证
    if (typeof amount !== 'number' || amount <= 0) return c.json({ error: 'Invalid amount' }, 400);
    if (typeof count !== 'number' || count <= 0 || count > 100) return c.json({ error: 'Invalid count (1-100)' }, 400);
    if (typeof prefix !== 'string' || !prefix) return c.json({ error: 'Invalid prefix' }, 400);

    const generatedCodes = [];

    for (let i = 0; i < count; i++) {
        // 使用 crypto.getRandomValues 替代 Math.random
        const bytes = new Uint8Array(8);
        crypto.getRandomValues(bytes);
        const randomSuffix = Array.from(bytes).map(b => b.toString(36)).join('').substring(0, 8).toUpperCase();
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

// /**
//  * 6. Stripe Webhook (Optional)
//  * TODO: Implement with proper Stripe signature verification when payment module is ready.
//  * Disabled for now — payment module is planned for a future release.
//  */

export default app;
