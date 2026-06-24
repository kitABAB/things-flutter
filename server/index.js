// 自托管同步后端：时间戳「最后写入获胜」(LWW) + 服务器单调 seq 增量拉取 + 删除墓碑。
//
// 不绑定具体表结构：每条记录以 (table_name, id) 为键，整行数据存为对象。
// 客户端推送变更与删除，按服务器分配的 seq 拉取增量（与客户端时钟无关）。
// 持久化采用零依赖的 JSON 文件（data.json），适合单用户多端的轻量场景。
import express from 'express';
import cors from 'cors';
import crypto from 'crypto';
import fs from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT || 4000;
const DATA_FILE = path.join(__dirname, 'data.json');

// 允许同步的表白名单（与客户端 schema 对齐）。
const TABLES = new Set(['items', 'areas', 'checklist_items', 'tags', 'item_tags']);

// ---------------- 持久化存储 ----------------
let state = { users: {}, records: {}, seq: 0 };
try {
  if (fs.existsSync(DATA_FILE)) {
    state = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    state.users ||= {};
    state.records ||= {};
    state.seq ||= 0;
  }
} catch (e) {
  console.error('加载 data.json 失败，使用空库：', e.message);
}
let saveTimer = null;
function save() {
  // 轻量去抖落盘，避免高频写。
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    fs.writeFile(DATA_FILE, JSON.stringify(state), (err) => {
      if (err) console.error('写 data.json 失败：', err.message);
    });
  }, 50);
}
const nextSeq = () => (state.seq += 1);
const key = (table, id) => table + '|' + id;
const userIdForEmail = (email) =>
  'u_' + crypto.createHash('sha1').update(email.trim().toLowerCase()).digest('hex').slice(0, 16);

const app = express();
app.use(cors());
app.use(express.json({ limit: '20mb' }));

app.get('/health', (_req, res) => res.json({ ok: true, seq: state.seq }));

// 邮箱登录（开发级）：同一邮箱稳定映射到同一 userId，支持多端同账号。
app.post('/auth', (req, res) => {
  const email = ((req.body && req.body.email) || '').trim();
  if (!email) return res.status(400).json({ error: 'email required' });
  const userId = userIdForEmail(email);
  const token = 'tok_' + userId;
  if (!state.users[userId]) {
    state.users[userId] = { email: email.toLowerCase(), token };
    save();
  }
  res.json({ userId, token });
});

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token.startsWith('tok_')) return res.status(401).json({ error: 'unauthorized' });
  const userId = token.slice(4);
  if (!state.users[userId]) return res.status(401).json({ error: 'unknown user' });
  req.userId = userId;
  next();
}

// 增量同步。
// 请求: { lastSeq, changes: [{table, rows:[{id, updated_at, ...cols}]}], deletions: [{table, id, updated_at}] }
// 响应: { seq, changes: [{table, rows:[...]}], deletions: [{table, id}] }
app.post('/sync', auth, (req, res) => {
  const userId = req.userId;
  const lastSeq = Number(req.body.lastSeq || 0);
  const incomingChanges = Array.isArray(req.body.changes) ? req.body.changes : [];
  const incomingDeletions = Array.isArray(req.body.deletions) ? req.body.deletions : [];

  // 1) upsert 普通变更（LWW：仅当 incoming.updated_at >= 现有 才覆盖）
  for (const group of incomingChanges) {
    const table = group.table;
    if (!TABLES.has(table)) continue;
    for (const row of group.rows || []) {
      if (!row || row.id == null) continue;
      const k = key(table, row.id);
      const existing = state.records[k];
      const incomingTs = row.updated_at || '';
      // LWW：仅当严格更新才覆盖；相等视为重复推送（幂等，不 bump seq，避免回环）。
      if (existing && (existing.updated_at || '') >= incomingTs) continue;
      state.records[k] = {
        table_name: table,
        id: String(row.id),
        user_id: userId,
        updated_at: incomingTs,
        deleted: 0,
        data: row,
        seq: nextSeq(),
      };
    }
  }
  // 2) 删除墓碑
  for (const d of incomingDeletions) {
    if (!d || !TABLES.has(d.table) || d.id == null) continue;
    const k = key(d.table, d.id);
    const existing = state.records[k];
    const incomingTs = d.updated_at || new Date().toISOString();
    if (existing && (existing.updated_at || '') > incomingTs) continue;
    state.records[k] = {
      table_name: d.table,
      id: String(d.id),
      user_id: userId,
      updated_at: incomingTs,
      deleted: 1,
      data: null,
      seq: nextSeq(),
    };
  }
  save();

  // 3) 拉取自 lastSeq 以来本用户的增量
  const changesByTable = {};
  const deletions = [];
  let maxSeq = lastSeq;
  const all = Object.values(state.records).filter((r) => r.user_id === userId && r.seq > lastSeq);
  all.sort((a, b) => a.seq - b.seq);
  for (const r of all) {
    if (r.seq > maxSeq) maxSeq = r.seq;
    if (r.deleted) deletions.push({ table: r.table_name, id: r.id });
    else (changesByTable[r.table_name] ||= []).push(r.data);
  }
  const changes = Object.entries(changesByTable).map(([table, rows]) => ({ table, rows }));
  res.json({ seq: maxSeq, changes, deletions });
});

app.listen(PORT, () => {
  console.log(`[things-sync] listening on http://0.0.0.0:${PORT} (seq=${state.seq})`);
});
