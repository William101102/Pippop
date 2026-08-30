# 把 Pinpop 发到 App Store

网页版继续照常部署到 GitHub Pages，同一份代码通过 Capacitor 打包成原生 iOS 应用。
不需要重写 UI。

## 你必须自己做的两件事

这两件事我无法代劳：

1. **装完整版 Xcode**（App Store 里下载，约 10GB）。当前这台机器只有 Command Line
   Tools，没有 `xcodebuild`，所以 iOS 工程无法编译。装完执行一次：

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

2. **注册 Apple Developer Program**（每年 99 美元）。没有它无法上架，也无法在真机
   上测试后台定位。

再装一下 CocoaPods（Capacitor 用它管理原生依赖）：

```bash
brew install cocoapods
```

## 生成 iOS 工程

```bash
npm run ios:add     # 创建 ios/ 工程并写入权限文案
npm run ios:sync    # 构建网页产物并同步进原生工程
npm run ios:open    # 用 Xcode 打开
```

`ios:add` 只需跑一次。之后每次改完代码跑 `ios:sync` 就行。

`ios/` 目录是生成物，已在 `.gitignore` 里忽略；权限文案由
`ios-setup/apply-info-plist.mjs` 注入，可重复执行，所以重新生成工程不会丢配置。

## 在 Xcode 里要设置的

- **Signing & Capabilities**：选你的 Team，Bundle Identifier 用 `com.pinpop.app`
  （或改成你自己的，同时改 `capacitor.config.ts` 里的 `appId`）。
- **Background Modes**：勾选 Location updates。`Info.plist` 已经声明了，但
  Xcode 的 capability 开关也要打开。
- **App Icon**：把 1024×1024 图放进 `ios/App/App/Assets.xcassets/AppIcon.appiconset`。

## 审核最容易被拒的点

按拒绝概率从高到低：

1. **指南 4.2「最低功能要求」** —— 纯网页套壳会被拒。这也是为什么接了真实的原生
   能力：后台定位、触感反馈、原生分享面板、原生启动屏。审核备注里要明确写出
   「后台位置共享」是核心功能，App Store 版本不是网站的镜像。

2. **指南 5.1.1(v) 账号删除** —— 有账号体系就必须提供应用内删除入口。已经做好了：
   设置面板 → 账号 → 删除账号，二次确认后调用 `delete_my_account()`，级联清空所有
   数据和头像文件。**前提是先在 Supabase 跑过 `backend/supabase/setup.sql`。**

3. **后台定位的必要性说明** —— 申请「始终」权限时，审核会要求解释为什么需要。理由是
   好友要能看到你实时移动，否则只能看到你最后一次打开应用的位置。

4. **隐私清单（Privacy Manifest）** —— Xcode 15+ 要求。在 App Store Connect 里如实
   申报：精确位置、粗略位置、用户 ID、照片，用途都是「App 功能」，且**不用于追踪**。

5. **权限文案** —— 不能只写「需要位置权限」，必须说明用途和谁能看到。
   `Info.plist` 里的文案已经按这个标准写好。

## 一个容易漏的坑

邀请链接不能指向 `capacitor://localhost`，否则收到链接的人打不开。`inviteUrl()`
在原生环境会回退到公开网页地址。如果你以后接了自己的域名，构建时设置：

```bash
VITE_PUBLIC_APP_URL=https://你的域名 npm run ios:sync
```
