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

## 一次真实的部署记录（2026-09-30，Debian + 1Panel）

> **连接信息不写在这里。** 主机别名、绝对路径、面板布局都属于基础设施信息，公开仓库里没有它们
> 的任何好处 —— 本机的真实值记在 `docs/private/local-deploy.md`（那个目录已 gitignore）。
> 下面只留**通用做法**与**踩过的坑**，那才是别人（和以后的我们）真正用得上的部分。
> 这也是这个项目的一条约定：凡是「只对某台机器成立」的东西，都不进仓库。

站点目录形态（1Panel 的默认布局）：

```
宿主机：  /opt/1panel/www/sites/<域名>/index
容器内：  /www/sites/<域名>/index        ← OpenResty 跑在容器里，面板把前者挂载为后者
```

注意 nginx 的 `root` 用的是**容器内路径**；这也是文件必须 world-readable 的原因之一。

**那台服务器上没有 rsync**，所以实际用的是 tar over SSH：

```bash
SITE=/opt/1panel/www/sites/<域名>/index

# 1) 备份面板的默认占位页（挪到 web 根之外）
ssh user@your-server "mkdir -p $(dirname $SITE)/panel-default-backup \
  && cp -a $SITE/. $(dirname $SITE)/panel-default-backup/"

# 2) 传（COPYFILE_DISABLE=1 防止 macOS 生成 ._* 影子文件）
COPYFILE_DISABLE=1 tar czf - -C site --exclude README.md --exclude '.DS_Store' . \
  | ssh user@your-server "tar xzf - -C $SITE"

# 3) 收尾：属主与权限（**这一步不能省，见下**）
ssh user@your-server "chown -R root:root $SITE \
  && find $SITE -type d -exec chmod 755 {} + \
  && find $SITE -type f -exec chmod 644 {} +"
```

### ⚠️ 为什么第 3 步不能省

`tar` **原样保留本地文件的属主与权限**。第一次部署后远端出现的是：

```
-rw------- 1 501 staff 33937 index.html     ← 501 是 macOS 的 uid，600 表示只有它能读
```

结果就是 Web 服务器**读不到文件**，访客拿到 403。所以每次用 tar/scp 部署之后都要
`chown` + `chmod`。（本次已顺手把本地的 `site/index.html` 从 600 改成 644，
但**别依赖这一点** —— 换一台机器或换个编辑器就可能又变回去。）

rsync 没有这个问题：它默认按远端 umask 新建文件。

### 部署后的验证（本次实际执行的）

```bash
curl -sI https://zwg.zlmix.com/                     # 期望 200 text/html
curl -sI https://zwg.zlmix.com/assets/icon.png      # 期望 200 image/png
# 逐字节比对线上与本地（确认没有传坏）
curl -s https://zwg.zlmix.com/ -o /tmp/live.html && shasum -a 256 /tmp/live.html site/index.html
```

本次结果：HTTP→HTTPS 301、首页与 4 张素材**逐字节一致**、gzip 已启用。
面板的 `server_name` 里同时写了两个域名，所以 `zwg.zlmix.com` 与 `zwgestures.zlmix.com` **都生效** ——
以后换用其中一个都不用改配置，但**页面里的 `canonical` 与 `og:*` 只应指向一个**，避免同一内容两个地址。

### 已知的两处未处理

1. **`assets/` 没有长缓存头。** 面板生成的配置里没有 `expires` / `Cache-Control`，
   而这份配置由面板管理，**手改可能在面板重新生成时丢失** —— 要加请走面板的网站配置界面。
   单页站点 + 5 个文件，影响很小，所以先没动。
2. **404 页还是面板的默认样式**，与站点风格不一致。`404.html` 在站点目录里，
   属于站点内容、可以安全替换（不用改 nginx 配置）。

## 部署方式（其它选择）

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
