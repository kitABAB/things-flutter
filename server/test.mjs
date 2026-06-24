// 端到端测试：登录 → 设备A push → 设备B pull → 冲突(LWW) → 删除墓碑。
const BASE = process.env.BASE || 'http://127.0.0.1:4000';

let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) { pass++; console.log('  ✓', name); }
  else { fail++; console.error('  ✗ FAIL:', name); }
}
async function post(path, body, token) {
  const res = await fetch(BASE + path, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: 'Bearer ' + token } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

const iso = (d) => new Date(d).toISOString();

(async () => {
  console.log('1) 健康检查 & 登录');
  const health = await fetch(BASE + '/health').then(r => r.json());
  check('health ok', health.ok === true);
  const auth = await post('/auth', { email: 'tester@example.com' });
  check('auth 返回 userId/token', !!auth.json.userId && !!auth.json.token);
  const token = auth.json.token;
  const auth2 = await post('/auth', { email: 'TESTER@example.com ' });
  check('同邮箱(大小写/空格) → 同 userId', auth2.json.userId === auth.json.userId);

  console.log('2) 设备A push 两条 items');
  const t1 = iso(Date.now() - 10000);
  const pushA = await post('/sync', {
    lastSeq: 0,
    changes: [{
      table: 'items',
      rows: [
        { id: 'a1', user_id: auth.json.userId, title: '买牛奶', updated_at: t1, status: 'open' },
        { id: 'a2', user_id: auth.json.userId, title: '写代码', updated_at: t1, status: 'open' },
      ],
    }],
    deletions: [],
  }, token);
  check('push 成功返回 seq', typeof pushA.json.seq === 'number' && pushA.json.seq >= 2);
  const seqAfterA = pushA.json.seq;

  console.log('3) 设备B 从 0 pull → 拿到 2 条');
  const pullB = await post('/sync', { lastSeq: 0, changes: [], deletions: [] }, token);
  const itemsB = (pullB.json.changes.find(c => c.table === 'items') || {}).rows || [];
  check('设备B 拉到 2 条', itemsB.length === 2);
  check('内容正确', itemsB.some(r => r.id === 'a1' && r.title === '买牛奶'));

  console.log('4) 增量：B 用 seq 再 pull → 无新增');
  const pullB2 = await post('/sync', { lastSeq: pullB.json.seq, changes: [], deletions: [] }, token);
  check('增量 pull 无变化', (pullB2.json.changes.length === 0) && (pullB2.json.deletions.length === 0));

  console.log('5) LWW：旧时间戳写 a1 应被拒，新时间戳应覆盖');
  const tOld = iso(Date.now() - 999999);
  await post('/sync', { lastSeq: 0, changes: [{ table: 'items', rows: [{ id: 'a1', user_id: auth.json.userId, title: '旧标题(应被拒)', updated_at: tOld }] }], deletions: [] }, token);
  const tNew = iso(Date.now());
  await post('/sync', { lastSeq: 0, changes: [{ table: 'items', rows: [{ id: 'a1', user_id: auth.json.userId, title: '新标题(应生效)', updated_at: tNew }] }], deletions: [] }, token);
  const pullCheck = await post('/sync', { lastSeq: 0, changes: [], deletions: [] }, token);
  const a1 = ((pullCheck.json.changes.find(c => c.table === 'items') || {}).rows || []).find(r => r.id === 'a1');
  check('LWW：保留新标题', a1 && a1.title === '新标题(应生效)');

  console.log('6) 删除墓碑：删 a2 → B 增量拉到 deletion');
  const beforeDelSeq = pullCheck.json.seq;
  await post('/sync', { lastSeq: 0, changes: [], deletions: [{ table: 'items', id: 'a2', updated_at: iso(Date.now()) }] }, token);
  const pullDel = await post('/sync', { lastSeq: beforeDelSeq, changes: [], deletions: [] }, token);
  check('增量拉到 a2 的删除', pullDel.json.deletions.some(d => d.table === 'items' && d.id === 'a2'));

  console.log('7) 鉴权：无 token 应 401');
  const noAuth = await post('/sync', { lastSeq: 0 }, null);
  check('无 token → 401', noAuth.status === 401);

  console.log('8) 多表：areas / tags / item_tags');
  await post('/sync', {
    lastSeq: 0,
    changes: [
      { table: 'areas', rows: [{ id: 'ar1', user_id: auth.json.userId, title: '工作', updated_at: iso(Date.now()) }] },
      { table: 'tags', rows: [{ id: 'tg1', user_id: auth.json.userId, title: '等待中', updated_at: iso(Date.now()) }] },
      { table: 'item_tags', rows: [{ id: 'a1|tg1', user_id: auth.json.userId, item_id: 'a1', tag_id: 'tg1', updated_at: iso(Date.now()) }] },
    ],
    deletions: [],
  }, token);
  const pullMulti = await post('/sync', { lastSeq: 0, changes: [], deletions: [] }, token);
  const tables = pullMulti.json.changes.map(c => c.table);
  check('areas/tags/item_tags 均可同步', ['areas', 'tags', 'item_tags'].every(t => tables.includes(t)));

  console.log(`\n结果：${pass} 通过, ${fail} 失败`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error(e); process.exit(1); });
