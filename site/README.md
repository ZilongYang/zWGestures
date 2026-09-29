# 介绍页（`site/`）

这个目录是一个**完整可部署的静态站点**，没有任何构建步骤、没有依赖、没有 `node_modules`：

```
site/
  index.html    单文件页面：样式与脚本全部内联
  assets/       图标与界面截图（页面唯一会请求的东西）
  README.md     本文件，不必部署
```

**页面不引用任何外部资源** —— 没有 CDN、没有网络字体、没有统计脚本。断网也能正常显示，
也不会把访客暴露给第三方。唯一的网络请求是同目录下的 `assets/`。

计划部署地址：**`https://zwg.zlmix.com/`**（已写进 `index.html` 的 `canonical` 与 `og:*` 标签；
换域名时记得一起改）。

## 本地预览

直接双击 `index.html` 就能看。但想用 `?lang=en` 与「刷新后记住语言」这两个行为，建议起个本地服务：

```bash
cd site && python3 -m http.server 8080
# http://127.0.0.1:8080/          → 中文
# http://127.0.0.1:8080/?lang=en  → 英文
```

语言切换的优先级：`?lang=` 显式指定 > 上次选择（`localStorage`）> 默认中文。
没有 JS 时中文照常可读。

## 部署方式

按「有没有 SSH、想不想维护服务器」选一种。

### 1. rsync over SSH（推荐，适合反复发版）

```bash
rsync -avz --delete --exclude README.md site/ user@host:/var/www/zwg.zlmix.com/
```

`--delete` 让远端与本地完全一致。**用之前确认目标目录是对的** —— 写错路径会删掉别的站点的文件。

### 2. tar over SSH（服务器没装 rsync 时）

```bash
tar czf - -C site --exclude README.md . | ssh user@host 'mkdir -p /var/www/zwg.zlmix.com && tar xzf - -C /var/www/zwg.zlmix.com'
```

### 3. scp / sftp（一次性拷贝）

```bash
scp -r site/index.html site/assets user@host:/var/www/zwg.zlmix.com/
# 或交互式：sftp user@host  然后  put -r index.html assets
```

不增量、也不会删掉远端多余文件。适合只上一次。

### 4. 面板上传

本地打包 → 在宝塔 / 1Panel 之类的文件管理器里上传解压：

```bash
cd site && zip -r ../zwg-site.zip . -x 'README.md'
```

### 5. 对象存储 + CDN

把 `site/` 传进 OSS / COS / S3，域名 CNAME 过去开静态托管。没有服务器要维护，
但要自己配 HTTPS 证书与缓存刷新。

### 6. Cloudflare Tunnel（服务器在内网或没有公网 IP）

```bash
cloudflared tunnel --url http://127.0.0.1:8080
# 或把 site/ 用任意静态服务器跑起来，再用 tunnel 暴露
```

不用开放端口，也不用公网 IP。

### nginx 片段（子域名直接作为站点根目录）

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name zwg.zlmix.com;

    root /var/www/zwg.zlmix.com;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # 截图与图标带长期缓存；index.html 不缓存，避免发版后访客仍看到旧页面
    location /assets/ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    location = /index.html {
        add_header Cache-Control "no-cache";
    }

    gzip on;
    gzip_types text/html text/css application/javascript image/svg+xml;
}
```

`?lang=en` 这类查询串不影响缓存 —— `index.html` 本来就不缓存。

## 发版时要同步的地方

| 位置 | 改什么 |
|---|---|
| `index.html` 的 `<span class="meta">` | `v0.1.0 · macOS 14+ · Apple Silicon` |
| `index.html` 的下载按钮 `href` | 指向 `releases/latest/download/zWGestures-arm64.dmg` —— **固定文件名，发版不用改** |
| 三处版本号 | `project.yml` 的 `MARKETING_VERSION`、本页、`CHANGELOG.md` |

页面刻意**不请求 GitHub API**：那有每小时 60 次的限流，而且会把一个失败态引入到页面里。

## 素材来源

`assets/` 里 4 张图的来历、以及为什么轨迹那张的背景是衬底而不是屏幕截图，
写在 [`docs/ROADMAP.md`](../docs/ROADMAP.md) §18 —— 那里也记了「截图里不得出现本机信息」
这条规则是怎么踩出来的。

`assets/install-gatekeeper.png` 还没拍（计划挪到「全新 macOS 用户账号」验收时拍，那个账号没有
任何个人信息）。拿到之后把 `index.html` 安装那节里注释掉的 `<figure>` 取消注释即可。

## 下载源：只用 GitHub（2026-09-30 决定）

下载按钮指向 **GitHub Releases**，页面上只有这一个源。**这是有意为之**：单一下载源不会出现
「两个地方版本不一致」的问题，而那是最容易悄悄发生的发布事故。

代价是**国内访客可能下不动或很慢**。这条已写进页面 FAQ（「下载很慢，或者干脆下不动？」
那一条），让访客能自己判断与绕开（重试、换网络、或直接从源码构建）。

**如果以后要加国内镜像**，需要同时改这几处，而且每次发版必须两边都更新：

1. `index.html` 里下载按钮的 `href` → 指向镜像地址（或改成主按钮指向镜像、GitHub 作为备用链接）；
2. `assets/SHA256SUMS` 或镜像目录里也放一份校验和；
3. 本文件与 `docs/release-notes/<版本>.md` 的下载说明；
4. 给镜像加一个「发版时别忘了同步」的检查（否则下一次发版就会漂移）。

在做出这个决定之前，不要半途加上镜像 —— 半套镜像比没有镜像更容易误导人。
