# Things 克隆版 · 自托管同步服务

零原生依赖、单文件的同步后端。基于 **时间戳「最后写入获胜」(LWW)** + **服务器单调 seq 增量拉取** + **删除墓碑**，数据持久化到本地 `data.json`。适合单用户多端的轻量同步。

## 运行

```bash
cd server
npm install
npm start          # 默认监听 0.0.0.0:4000，可用 PORT 环境变量覆盖
```

启动后客户端 App 在「云同步」页填入 `http://<电脑局域网IP>:4000` 与邮箱即可。
同一邮箱在任意设备登录都视为**同一账号**，从而实现多端同步。

> 手机与电脑需在同一局域网；若连不上，检查电脑防火墙是否放行 TCP 4000。

## 测试

```bash
npm test           # 端到端：登录 / 推送 / 拉取 / 增量 / LWW / 删除墓碑 / 鉴权 / 多表
```

## 协议

- `GET  /health` → `{ ok, seq }`
- `POST /auth` `{ email }` → `{ userId, token }`（开发级：邮箱稳定映射到 userId）
- `POST /sync`（需 `Authorization: Bearer <token>`）
  - 请求：`{ lastSeq, changes:[{table, rows:[{id, updated_at, ...}]}], deletions:[{table, id, updated_at}] }`
  - 响应：`{ seq, changes:[{table, rows}], deletions:[{table, id}] }`

客户端策略：每次同步全量推送本地各表行 + 待删除墓碑，再按 `lastSeq` 拉取服务器增量并应用。
服务器对相等时间戳的重复推送幂等跳过（不 bump seq），因此不会产生同步回环。

## 说明

- 鉴权为开发级（token 即 `tok_<userId>`），仅用于局域网自托管。如需公网部署请替换为正式的签名 token / 密码校验。
- 同步表白名单：`items / areas / checklist_items / tags / item_tags`，与客户端 schema 对齐。
