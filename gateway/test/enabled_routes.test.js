import assert from 'node:assert/strict';
import test from 'node:test';

import app from '../src/index.js';

class FakeKv {
    constructor(entries = {}, pageSize = 1000, requireBulkCounterReads = false) {
        this.values = new Map(Object.entries(entries));
        this.pageSize = pageSize;
        this.requireBulkCounterReads = requireBulkCounterReads;
        this.bulkGetCalls = 0;
    }

    async get(key, options) {
        if (Array.isArray(key)) {
            if (key.length > 100) throw new Error('KV bulk get exceeds 100 keys');
            this.bulkGetCalls++;
            return new Map(key.flatMap((name) => {
                const value = this.values.get(name);
                return value === undefined ? [] : [[name, value]];
            }));
        }
        if (this.requireBulkCounterReads && /^stats:(version|daily):/.test(key)) {
            throw new Error('Counter values must use KV bulk get');
        }
        const value = this.values.get(key) ?? null;
        if (value === null || options?.type !== 'json') return value;
        return JSON.parse(value);
    }

    async put(key, value) {
        this.values.set(key, value);
    }

    async list({ prefix = '', cursor } = {}) {
        const keys = [...this.values.keys()]
            .filter((key) => key.startsWith(prefix))
            .sort();
        const offset = cursor ? Number(cursor) : 0;
        const page = keys.slice(offset, offset + this.pageSize);
        const nextOffset = offset + page.length;
        return {
            keys: page.map((name) => ({ name })),
            list_complete: nextOffset >= keys.length,
            cursor: nextOffset >= keys.length ? undefined : String(nextOffset),
        };
    }
}

test('/version 在固定统计记录中保留合法 SemVer，其余输入聚合到 unknown', async () => {
    const kv = new FakeKv();
    const env = { SPEAKOUT_DB: kv };

    await app.request('/version?v=1.10.0-RC1&b=241', {}, env);
    for (let i = 0; i < 20; i++) {
        await app.request(`/version?v=${encodeURIComponent(`garbage-${i}`)}&b=0`, {}, env);
    }

    assert.deepEqual(JSON.parse(kv.values.get('stats:versions')), {
        '1.10.0-RC1': 1,
        unknown: 20,
    });
    assert.equal(
        [...kv.values.keys()].filter((key) => key.startsWith('stats:version')).length,
        1,
    );
});

test('/version 对合法但任意的版本号也限制统计基数', async () => {
    const kv = new FakeKv();
    const env = { SPEAKOUT_DB: kv };

    for (let i = 0; i < 140; i++) {
        await app.request(`/version?v=2.${i}.0&b=0`, {}, env);
    }

    const counters = JSON.parse(kv.values.get('stats:versions'));
    assert.equal(Object.keys(counters).length, 129);
    assert.equal(counters.other, 12);
    assert.equal(
        [...kv.values.keys()].filter((key) => key.startsWith('stats:version')).length,
        1,
    );
});

test('/stats 翻页读取全部统计 key', async () => {
    const kv = new FakeKv({
        'stats:version:1.8.6': '3',
        'stats:version:1.9.1': '4',
        'stats:version:1.10.0': '5',
        'stats:daily:2026-08-17': '6',
        'stats:daily:2026-08-18': '7',
        'stats:versions': JSON.stringify({ '1.10.0': 8, '1.11.0': 9 }),
    }, 1);
    const env = { SPEAKOUT_DB: kv, ADMIN_SECRET: 'secret' };

    const response = await app.request('/stats', {
        headers: { 'Admin-Key': 'secret' },
    }, env);

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
        versions: { '1.10.0': 13, '1.11.0': 9, '1.8.6': 3, '1.9.1': 4 },
        daily: { '2026-08-17': 6, '2026-08-18': 7 },
    });
});

test('/stats 每批最多读取 100 个统计值', async () => {
    const entries = Object.fromEntries(Array.from(
        { length: 205 },
        (_, i) => [`stats:version:1.${i}.0`, String(i)],
    ));
    const kv = new FakeKv(entries, 1000, true);
    const env = { SPEAKOUT_DB: kv, ADMIN_SECRET: 'secret' };

    const response = await app.request('/stats', {
        headers: { 'Admin-Key': 'secret' },
    }, env);

    assert.equal(response.status, 200);
    assert.equal(Object.keys((await response.json()).versions).length, 205);
    assert.equal(kv.bulkGetCalls, 3);
});

test('/stats 在管理员 secret 缺失时 fail-closed', async () => {
    const response = await app.request('/stats', {
        headers: { 'Admin-Key': 'anything' },
    }, { SPEAKOUT_DB: new FakeKv() });

    assert.equal(response.status, 401);
});
