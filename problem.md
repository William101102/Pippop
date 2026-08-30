# Pinpop — 代码审查问题清单

> 2026 年审查记录。这些问题**暂缓处理**，当前优先级是把未完成的 feature 做实。
> 修完 feature 后按优先级逐项回来解决。

## P1 — 高优先级（影响正确性 / 资源）

### 1. Ghost Mode = frozen 时真实坐标仍在数据库中
- 文件：`src/hooks/useGeolocation.ts`、`src/services/profiles.ts`
- 现象：`frozen` 模式下前端只是"停止上传新坐标"，但此前上报的真实位置仍在 `locations` 表里。
- 修复方向：`setGhostMode` 已接收 frozen 坐标，应让它同时 upsert `locations` 为冻结点（或删除真实坐标）；另外 `useEffect` 依赖 `ghostMode` 导致每次切档重开 `watchPosition`，建议 watch 回调里用 ref 读 ghostMode。

### 2. 位置上报无节流
- 文件：`src/hooks/useGeolocation.ts`
- 现象：`watchPosition` 每次回调都 upsert Supabase 并触发 Realtime 广播给所有好友，移动端烧电+流量。
- 修复方向：加最小距离（约 50m）或最小时间间隔（约 30s）阈值。

### 3. `searchProfiles` 的 `ilike` 未转义用户输入
- 文件：`src/services/profiles.ts`（第 44 行）
- 现象：`%${query}%` 没转义 `%` / `_` 通配符，特殊字符还可能破坏 `.or()` 语法。
- 修复方向：对 `%`、`_`、逗号做转义。

## P2 — 中优先级（体验 / 代码质量）

### 4. toast 计时器未清理
- 文件：`src/App.tsx`（`notify`，第 52–55 行）
- 现象：连续 toast 互相覆盖闪烁；组件卸载时 timeout 未清理。

### 5. world 面板 / places 面板仍是占位符
- 文件：`src/App.tsx`（第 192–204 行）
- 现象："本周探索 — km" 是硬编码占位。
- 备注：**此项属于下一步要做的 feature，见下方"feature 路线"，不算待修 bug。**

### 6. preview 逻辑依赖渲染顺序略脆
- 文件：`src/App.tsx`（第 44 行）
- 现象：`me = preview || !auth.profile ? demoMe : auth.profile`，登录未补全资料时理论上会闪 demoMe，靠前面的 `needsProfile` 拦截兜底。

### 7. 消息无未读/已读状态
- 文件：`src/hooks/useMessages.ts`、schema
- 修复方向：`messages` 表加 `read_at` 列 + badge。

## P3 — 低优先级（工程化）

### 8. 完全没有测试
- `haversineKm`、`nextStatus`、`loadFriendsBundle` 分支逻辑都是好的单测对象。
- 引入 Vitest + Testing Library。

### 9. backend/README 中承诺但未做的事项
- Edge Function 限流（好友请求 / 消息）
- 头像 Storage 私有桶
- dev/prod 双 Supabase 项目、邮箱验证、redirect 白名单

### 10. PWA 未真正可用
- 已有 `public/manifest.webmanifest`，缺 service worker / 离线缓存。

---

# Feature 路线（当前工作重点）

## ① World 面板（本周足迹）做实
- 新增 `location_history` 表（每次节流后的上报同时写历史）。
- RLS：只有本人可读。
- 用 `haversineKm` 累计当日/本周里程，替换 "— km" 占位。
- 顺带实现 places 面板的"打卡"功能（存个人地点标记）。

## ② 未读消息 badge
- `messages` 加 `read_at`；BottomDock 消息 tab 显示未读数。

## ③ Places / 附近地点
- 决定是否接外部 POI API；或先做基于 `location_history` 的"朋友常去的地方"。

## ④ PWA 离线
- service worker 缓存瓦片与静态资源。

## ⑤ 之后的移动端
- React Native/Expo 复用同一套表 + RLS（见 backend/README）。
