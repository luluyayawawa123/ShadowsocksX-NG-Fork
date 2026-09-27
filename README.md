# ShadowsocksX-NG Fork

这是 [ShadowsocksX-NG 原项目](https://github.com/shadowsocks/ShadowsocksX-NG)的个人维护版本。软件在菜单栏运行，通过 Shadowsocks 代理，并支持 PAC 自动模式、全局模式和手动模式。

[下载最新稳定版 DMG](https://github.com/luluyayawawa123/ShadowsocksX-NG-Fork/releases/latest) · [查看构建状态](https://github.com/luluyayawawa123/ShadowsocksX-NG-Fork/actions)

## 下载与安装

从本仓库的 [Releases 页面](https://github.com/luluyayawawa123/ShadowsocksX-NG-Fork/releases)下载 DMG，打开后将 `ShadowsocksX-NG.app` 拖入“应用程序”。覆盖安装前先退出正在运行的旧版。覆盖应用不会删除已有的服务器配置或自定义 PAC 规则。

## 本维护版本的改动

- 当前内置 GFWList 在发布时与[官方规则](https://github.com/gfwlist/gfwlist)同步。首次启动会直接使用内置规则；覆盖安装后，软件会用较新的内置规则替换本地旧规则。
- 如果本地规则比内置规则更新，启动时会保留本地规则，避免降级。自定义规则和个人配置不会因此被覆盖。
- 在菜单栏点击“从 GFW List 更新PAC”后，弹窗会说明更新成功、无需更新、下载源较旧或更新失败。成功时显示规则自身标注的 `Last Modified` 日期，而不是文件保存时间。
- 规则或自定义规则改变后会重新生成 PAC；PAC 自动模式下会刷新正在使用的代理配置。
- 修复手动更新 PAC 时重复重启代理服务可能造成的闪退。

## 规则文件

规则文件保存在用户目录下的 `~/.ShadowsocksX-NG/`：

| 文件 | 用途 |
| --- | --- |
| `gfwlist.txt` | 下载或内置的 GFWList 规则 |
| `user-rule.txt` | 你自己的 PAC 规则；更新 GFWList 不会覆盖它 |
| `gfwlist.js` | 软件根据以上规则生成的 PAC 文件 |

默认下载地址是 GFWList 官方 GitHub 仓库经 jsDelivr 分发的 CDN 地址。CDN 缓存偶尔可能落后于官方源；如果下载到更旧的规则，软件会保留较新的本地或内置规则。

## 原有功能

- 支持 SIP003 插件，并内置 `kcptun`、`simple-obfs` 和 `v2ray-plugin`。
- 支持 AEAD 加密方式、二维码和链接分享配置，以及从剪贴板或屏幕二维码导入配置。
- 支持自定义 PAC 规则，并通过 `privoxy` 提供 HTTP 代理。
- `ss-local` 通过 macOS 的 Launch Agent 在后台运行。退出菜单栏应用后，后台代理进程可能仍在运行。
- 手动模式不会自动修改系统代理设置，适合自行配置应用使用 SOCKS5 代理。

原项目重写的原因是旧实现包含大量不再使用的代码，且把 `ss-local` 源码直接放在应用中，不便更新依赖。新实现将 `ss-local` 作为独立后台程序运行，图形界面主要使用 Swift 编写。

## 系统与构建

工程的最低 macOS 部署目标设为 10.12；较旧系统的实际兼容性取决于构建工具和依赖，当前发布包未逐一验证。自行编译需要 Xcode、CocoaPods 和项目依赖。仓库默认开发分支是 `develop`。

推送分支代码会运行 [测试构建](https://github.com/luluyayawawa123/ShadowsocksX-NG-Fork/actions/workflows/feature.yml)。从要发布的提交创建并推送新版本 Tag，会运行 [正式构建](https://github.com/luluyayawawa123/ShadowsocksX-NG-Fork/actions/workflows/release.yml)，自动生成 DMG、校验文件和 GitHub Release。

只修改 Markdown 文档或许可证时，会跳过测试构建；如果同一次提交还修改了程序、构建脚本或规则资源，测试构建仍会运行。

如要贡献代码，请基于最新的 `develop` 新建独立分支提交修改；分支流程可参考 [GitFlow](https://nvie.com/posts/a-successful-git-branching-model/)。

## 反馈与许可

问题和建议请提交到本仓库的 [Issues](https://github.com/luluyayawawa123/ShadowsocksX-NG-Fork/issues)。本项目依据 [GPLv3 许可证](LICENSE)发布。
