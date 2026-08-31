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

## P4 — 2026-08 git pull 后新增风险（记录备查，暂缓处理）

### 11. DB 迁移双份且已漂移
- `supabase/` 与 `backend/supabase/` 下同名 migration 内容不一致（如 `202608300004` 60 行 vs 55 行），且新增 1343 行的 `setup.sql` 巨型脚本。
- 风险：在生产库上执行 `setup.sql` 或两套 migration 可能产生重复 policy/表或漏列。先在 staging Supabase 项目验证。

### 12. 隐私回归风险（本项目最核心风险）
- 新增 background geolocation、overnight places、Zenlands zones、ghost mode 修复等多条涉及"谁能看到谁的位置"的代码路径。
- 仓库里已经出现 4 个 `fix-*privacy*.sql` 热修，说明位置 upsert / RLS 曾出过问题。任何回归都可能泄露用户真实位置。

### 13. iOS 原生打包权限风险
- Capacitor 打包依赖 `ios-setup/Info.plist.additions.xml` 中的权限声明；缺失会导致 App Store 审核被拒或后台定位静默失效。Android 后台存活/耗电未测。

### 14. 已删除 `src/hooks/useGeolocation.ts`
- 未合并的分支若仍 import 它会直接编译失败；旧的 preview 模式 GPS 泄露修复需确认已迁移到新的 `src/lib/location.ts`。

### 15. send-push Edge Function 密钥与鉴权
- 需要在 Supabase 配置 APNs/FCM 密钥；push token 表若 RLS 不严可被未授权调用读取或滥发。

### 16. 依赖面扩大 / 已知漏洞
- `package-lock.json` 增加约 1800 行；`npm audit` 有报告漏洞，上线前需处理。

### 17. App.tsx 大规模重写（+1271 行）
- 核心 shell 在单个文件里重构，现有单测只覆盖 `cluster/geo/geofence/places`，UI 回归（pin 渲染、拖拽 sheet）缺乏测试保障。

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
