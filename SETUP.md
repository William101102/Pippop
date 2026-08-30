# Pinpop — 上线设置（必做，2 分钟）

代码已经推上去了，但 **GitHub Pages 需要你在网页上点一次** 才能开通。我这边没法替你点。

## 第一步：开通 GitHub Pages

1. 打开：**https://github.com/William101102/zenly-app/settings/pages**
2. **Build and deployment → Source** 选 **GitHub Actions**（不要选 Deploy from a branch）
3. 保存

## 第二步：重新跑一次部署

1. 打开：**https://github.com/William101102/zenly-app/actions**
2. 点左边 **Deploy to GitHub Pages**
3. 点右上角 **Run workflow** → **Run workflow**（或点最近一次失败的记录 → **Re-run all jobs**）

等 1 分钟左右变绿 ✅ 后，打开：

**https://william101102.github.io/zenly-app/**

就能看到 Pinpop 登录页了。

---

## 想要短网址 `https://pinpop.app`？

GitHub 免费地址永远是 `用户名.github.io/仓库名`，没法变成纯 `pinpop.app`，除非 **买一个域名**（大约 $10–15/年）。

### 买域名

去 [Cloudflare](https://www.cloudflare.com/products/registrar/) 或 [Namecheap](https://www.namecheap.com) 搜索并购买：

- **pinpop.app**（推荐）
- 如果被占了：**pinpop.io**、**getpinpop.com**

### 配 DNS

| 类型 | 名称 | 值 |
|---|---|---|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| CNAME | www | william101102.github.io |

### 告诉 GitHub

在仓库根目录创建 `CNAME` 文件（内容一行）：

```
pinpop.app
```

推送后，去 **Settings → Pages → Custom domain** 填 `pinpop.app`，勾选 **Enforce HTTPS**。

### Supabase 也要加网址

Supabase 后台 → **Authentication → URL Configuration**，在 Site URL / Redirect URLs 里加上：

- `https://pinpop.app`
- `https://william101102.github.io/zenly-app`

---

## 为什么叫 Pinpop？

- **Pin** = 地图上的定位点
- **Pop** = 活泼、Zenly 那种玩具感
- 短、好记、适合当域名和产品名
