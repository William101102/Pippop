# 近旁

一个仿 [Zenly](https://en.wikipedia.org/wiki/Zenly) 的好友实时位置地图 App，纯前端 + [Supabase](https://supabase.com) 后端，单个 HTML 文件就能跑，没有任何假数据 —— 账号、好友关系、位置、聊天全部是真实读写数据库。

## 界面

- 主界面：真实地图 + 好友头像气泡 + 可上滑的好友列表
- 点击好友头像弹出详情卡片，可以聊天或打招呼
- 点自己的头像可以切换状态（在家 / 工作中 / 吃饭中 / 放松中 / 散步中）
- 登录 / 注册页支持邮箱账号

## 在线体验

开启 GitHub Pages 后，直接用手机或电脑浏览器打开：

**https://william101102.github.io/zenly-app/**

（如果打开是 404，说明 Pages 刚开启还在构建，等 1 分钟刷新一下就行；开启方法见下面「部署到 GitHub Pages」）

## 功能

- 邮箱注册 / 登录(Supabase Auth)
- 地图上实时显示自己和好友的位置(浏览器 Geolocation API + Supabase Realtime，好友移动几秒内会同步过来)
- 按 ID 或昵称搜索、添加好友，对方需要接受请求才成为好友
- 好友之间才能看到彼此位置 —— 由数据库的 Row Level Security 规则保证，不是前端隐藏
- 自己可切换状态(🏠 在家 / 💼 工作中 / 🍔 吃饭中 / 🎧 放松中 / 🚶 散步中)，好友会看到
- 好友间一对一聊天、快捷"打招呼"
- 底部好友列表可以像原生 App 一样用手指上滑拉出、松手自动吸附

## 技术栈

| 部分 | 用的什么 | 为什么 |
|---|---|---|
| 界面 | 原生 HTML / CSS / JavaScript，无框架 | 单文件、零构建、打开就能跑 |
| 地图 | [Leaflet](https://leafletjs.com) + OpenStreetMap 瓦片 | 免费、不需要注册任何 API Key |
| 账号 / 数据库 / 实时同步 | [Supabase](https://supabase.com)(Postgres + Auth + Realtime) | 免费额度够用，比 Firebase 按操作计费更可控 |
| 定位 | 浏览器 Geolocation API | 不需要额外权限申请，手机浏览器直接弹权限框 |

全部代码在一个文件 `index.html` 里，好处是部署简单；如果要继续扩展，建议后续再拆分。

## 本地跑起来 / 部署到自己的 Supabase

1. **建一个 Supabase 项目**：去 [supabase.com](https://supabase.com) 免费注册，New Project。
2. **建表**：把 [`schema.sql`](./schema.sql) 的内容粘贴到 Supabase 后台的 SQL Editor，点 Run。会建好 4 张表(用户资料 / 好友关系 / 位置 / 消息)并配好权限规则。
3. **关掉邮箱确认(方便自测)**：Supabase 后台 → Authentication → Providers → Email → 关掉 "Confirm email"。不关的话，注册后要去邮箱点确认链接才能登录。
4. **填入你的项目信息**：打开 `index.html`，找到接近顶部的这两行：
   ```js
   const SUPABASE_URL = "https://xxxx.supabase.co";
   const SUPABASE_ANON_KEY = "eyJ...";
   ```
   换成你自己项目 Settings → API 里的 **Project URL** 和 **anon public** key(这个 key 本来就是设计成可以公开的，不是密码)。
5. **打开它**：双击 `index.html` 直接用浏览器打开就行，不需要装任何东西、不需要起服务器。
6. **测试完整流程**：用两个不同邮箱各注册一个账号 → 允许浏览器定位权限 → 用一个账号搜另一个账号的 ID 加好友 → 另一个账号接受 → 两边就能在地图上看到彼此的实时位置了。

## 部署到 GitHub Pages(免费，手机能直接访问)

1. Fork 或直接用这个仓库
2. 仓库 Settings → Pages → Source 选 "Deploy from a branch"，Branch 选 `main` / `/(root)`，Save
3. 大约 1 分钟后，`https://<你的用户名>.github.io/<仓库名>/` 就能访问了

## 已知限制

- 好友请求目前没有防重复发送的兜底(双向同时发请求会各自留一条 pending 记录，不影响使用，只是数据库里会多一条冗余记录)
- 聊天没有"未读数"，只有收到消息时的一个 toast 提示
- 地图用的是免费 OpenStreetMap 瓦片，配色是默认样式，不是 Zenly 那种糖果色定制地图
