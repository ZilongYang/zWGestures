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

## 本地预览

直接双击 `index.html` 就能看。但想用 `?lang=en` 与刷新后记住语言这两个行为，建议起一个本地服务：

```bash
cd site && python3 -m http.server 8080
# 打开 http://127.0.0.1:8080/          → 中文
# 打开 http://127.0.0.1:8080/?lang=en  → 英文
```

语言切换逻辑：`?lang=` 显式指定 > 上次选择（`localStorage`）> 默认中文。没有 JS 时中文照常可读。

## 部署

```bash
# --delete 让远端与本地一致；README.md 不必上传
rsync -avz --delete --exclude README.md site/ user@host:/var/www/zwgestures/
```

用 `scp` 也可以，注意别漏了 `assets/`：

```bash
scp -r site/index.html site/assets user@host:/var/www/zwgestures/
```

### nginx 片段

```nginx
server {
    listen 443 ssl;
    server_name zwgestures.example.com;
    root /var/www/zwgestures;
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

`?lang=en` 这类查询串不影响缓存：`index.html` 本来就不缓存。

## 发版时要改的地方

页面里的**版本号与下载地址是手写的**（刻意不请求 GitHub API —— 那有每小时 60 次的限流，
而且会把一个失败态引入到页面里）：

| 位置 | 改什么 |
|---|---|
| `index.html` 的 `<span class="meta">` | `v0.1.0 · macOS 14+ · Apple Silicon` |
| 下载按钮的 `href` | 指向 `releases/latest/download/zWGestures-arm64.dmg`，**固定文件名所以不用改** |

> 版本号同步三处：`project.yml` 的 `MARKETING_VERSION`、本页、`CHANGELOG.md`。

## 素材来源

`assets/` 里 4 张图的来历、以及为什么轨迹那张的背景是衬底而不是屏幕截图，
写在 [`docs/ROADMAP.md`](../docs/ROADMAP.md) §18 里 —— 那里也记了「截图里不得出现本机信息」
这条规则是怎么踩出来的。

`assets/install-gatekeeper.png` 还没拍（计划挪到「全新 macOS 用户账号」验收时拍，那个账号没有
任何个人信息）。拿到之后把 `index.html` 安装那节里注释掉的 `<figure>` 取消注释即可。
