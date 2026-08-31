# Pinpop

A Zenly-style social map. Friends show up live, you can wave, chat, and see
who is actually sharing. The same React UI is the website **and** the iOS app
(`com.pinpop.app` via Capacitor). GitHub Pages is only the invite link for
people who do not have the app yet.

<p align="center">
  <img src="docs/preview.png" alt="Pinpop phone preview: live map, friend rail, and dock" width="360" />
</p>

<p align="center">
  <a href="https://william101102.github.io/zenly-app/?preview=1">Open the live preview</a>
  · no account needed
</p>

- **Green ring** — this person is sharing a live location.
- **Gray ring** — they hid it, or have not updated in a while.
- **Zoom out** — overlapping people collapse into a circle with a count. Tap it
  to zoom back in.
- **Highlights** — post a photo (or just a line of text) from the 朋友 tab;
  friends see it in a Zenly/Snap-style story rail for 24 hours, then it's gone.
  Optionally attach your location and it also shows as a circular story pin
  on the map — à la Snap Map — until it expires.
- **Throw something** — tap a friend, pick from 14 throwables (🎂🌹🍕💦…) and
  send it with a little arc animation; landing on someone pops a celebratory
  toast on their end.
- **Streaks** — consecutive days you and a friend interact (message or throw)
  light up an escalating ✨ → 🔥 → 💯 badge, with a ⏳ warning when a streak is
  about to lapse and a small celebration the first time it crosses a milestone.
- **Invite links** — sharing your link mints a token; whoever opens it becomes
  a friend immediately, no separate approval step.

## 功能一览（中文）

Pinpop 是一个 Zenly 风格的社交地图 App：好友在地图上实时显示位置，可以打招呼、
聊天、看看谁在附近。同一套 React 代码同时是网页版和 iOS App。

**地图与位置**
- 实时位置地图 — 好友的头像随着他们移动在地图上实时更新。
- **Ghost Mode（幽灵模式）** — 三档位置隐私：精确 / 模糊（随机偏移约
  0.2–1.2 公里）/ 冻结（停在最后一次分享的位置），可以针对单个好友单独设置，
  好友端拿不到你的真实坐标。
- 圆环颜色：绿色表示正在实时分享位置，灰色表示已隐藏或很久没更新。
- 缩小地图时，重叠的人会合并成一个带数字的圆圈，点一下放大回去。
- **附近打卡** — 到一个地方可以打卡（咖啡、吃饭、公园、健身房、购物、家、
  工作、其他），可以选择好友可见或仅自己可见。
- **足迹与热力图** — 记录你常去的地方和停留时长，热力图只有你自己能看到；
  自动识别「过夜地点」（比如家），这部分数据完全私密。

**社交互动**
- **扔东西** — 打开一个好友的名片，可以从 14 种表情道具里选一个扔过去
  （🎂🌹🍕💦…），带一个小动画，对方会弹出一个庆祝弹窗。
- **连续互动火花（Streak）** — 你和某个好友连续互动（聊天或互扔东西）的天数
  会点亮 ✨ → 🔥 → 💯 的等级徽章，快断掉时会有 ⏳ 提醒，第一次达到里程碑
  （3/7/14/30/50/100/200/365 天）还会有小庆祝动画。
- **火花补救机制**（抖音同款逻辑）— 断了一天没关系，只要接下来连续 3 天
  互动，火花会补救回断掉之前的天数（外加这 3 天），名片上会显示 🩹 补救进度。
- **Highlights（限时动态）** — 在「朋友」页发一张照片或一句话，好友会在
  Zenly/Snap 风格的故事栏里看到，24 小时后自动消失。可以选择带上你的位置，
  这样地图上还会出现一个圆形的动态图钉（类似 Snap Map），过期后自动消失。
- **Zenlands（我的地标）** — 给常去的地方（比如健身房）起个名字，好友能看到
  这个名字，你到达/离开时他们会收到通知。
- **群聊** — 选至少两位好友，创建一个群聊天。
- **一对一聊天** — 私聊、未读消息角标、通知中心汇总好友请求/未读消息/收到
  的表情/好友动态。

**加好友**
- **邀请链接一键加好友** — 分享你的专属链接，对方点开就直接成为好友，
  不需要再走一遍「同意请求」的流程（和 Discord/WhatsApp 的邀请链接逻辑一样）。
- 也支持搜索用户名/昵称手动加好友，以及传统的发送/接受好友请求流程。

**账号与语言**
- 邮箱注册/登录，头像上传（自动裁剪压缩），状态文字/表情自定义。
- 账号删除（危险操作二次确认）。
- 现在整个 App 界面已经全部改为英文（原本是中文），适合面向海外用户。

## Run it locally

You need **Node 20+** and npm. No Xcode and no Supabase keys for the demo.

```bash
git clone https://github.com/William101102/zenly-app.git
cd zenly-app
npm install
npm run dev
```

Open [http://127.0.0.1:5173/?preview=1](http://127.0.0.1:5173/?preview=1).

On a laptop the page is a phone frame. That is the app, not a marketing site.
`?preview=1` loads demo friends around Santa Monica so you can tap around
without an account.

```text
npm run test        # unit tests
npm run typecheck   # TypeScript
```

### Real accounts (optional)

The preview is enough to see the product. To sign in for real:

1. Copy `.env.example` to `.env.local`.
2. Put in your Supabase URL and anon key (never a service-role key).
3. Run `backend/supabase/setup.sql` in the Supabase SQL editor (again after
   pulling, so the public avatar policy and 0.2–1.2 km blur stay current).
4. Restart `npm run dev` and open [http://127.0.0.1:5173/](http://127.0.0.1:5173/)
   without `?preview=1`.

| Variable | Where |
|---|---|
| `VITE_SUPABASE_URL` | `.env.local` and GitHub Actions vars |
| `VITE_SUPABASE_ANON_KEY` | same |
| `VITE_PUBLIC_APP_URL` | optional; invite links inside the installed app |

## Ship it to the App Store

The store build is this same UI inside a native shell. You cannot skip Xcode or
the Apple Developer Program. Review notes and permission copy live in
[`ios-setup/README.md`](ios-setup/README.md).

### 1. Accounts and tools (one-time)

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2. Install **full Xcode** from the Mac App Store (Command Line Tools are not enough).
3. Point the toolchain at it and accept the license:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

4. Install CocoaPods: `brew install cocoapods`.
5. Have a Supabase project with `backend/supabase/setup.sql` applied, and the
   same `VITE_SUPABASE_*` values you use locally.

### 2. Generate the iOS project

From the repo root, with `.env.local` already filled in:

```bash
npm install
npm run ios:add      # once: creates ios/ and writes Info.plist + icons
npm run ios:sync     # after any UI change: rebuild web assets into ios/
npm run ios:open     # opens Xcode
```

`ios/` is generated and gitignored. Do not hand-edit it; re-run `ios:sync`.

### 3. In Xcode

1. **Signing & Capabilities** — select your Team. Bundle ID is `com.pinpop.app`
   (change it in `capacitor.config.ts` if you own a different one).
2. Turn on **Background Modes → Location updates**.
3. Confirm the 1024×1024 App Icon is in
   `ios/App/App/Assets.xcassets/AppIcon.appiconset`.
4. Plug in a phone (or use a simulator) and press Run. Background location
   only works on a real device.

### 4. TestFlight, then App Store

1. In Xcode: **Product → Archive**.
2. **Distribute App → App Store Connect → Upload**.
3. In [App Store Connect](https://appstoreconnect.apple.com): create the Pinpop
   app, add screenshots, privacy nutrition labels, and a review note that
   **live friend location is the core feature** (guideline 4.2 — this is not a
   website wrapper).
4. Declare location, user ID, and photos as **App Functionality**, not tracking.
5. Turn on **TestFlight**, install on your phone, confirm sharing still works
   with the app in the background.
6. Submit for review.

After you change the React UI, run `npm run ios:sync`, archive again, and
upload a new build. Invite links should stay on the public site
(`https://william101102.github.io/zenly-app/?add=username`), not
`capacitor://localhost`.

```text
src/                         React UI (web + native)
ios-setup/                   Info.plist, icons, URL scheme, store notes
backend/supabase/            Schema, RLS, push edge function
docs/preview.png             Screenshot used in this README
```
