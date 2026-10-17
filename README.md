# Easy ESXi Builder

把官方 ESXi 离线包和社区驱动 zip 放在同一个目录，一条命令打出安装 ISO。不用再手敲 `Add-EsxSoftwareDepot` 和 `Add-EsxSoftwarePackage`。

宿主机用 Linux。`docker/build-esxi.ps1` 会在构建镜像时拷进容器，容器启动后自动执行。

## Usage

克隆仓库并构建镜像。必须在仓库根目录执行，`Dockerfile` 里的 `COPY docker/build-esxi.ps1` 依赖这个构建上下文。

```bash
git clone https://github.com/AristotleLai/easy-ESXi-builder.git
cd easy-ESXi-builder
docker build -t easy-esxi-builder -f docker/Dockerfile .
```

另建一个目录，只放 zip，不要放进仓库：

- 官方离线包，文件名里通常带 `depot`，例如 `VMware-ESXi-8.0-20513097-depot.zip`
- 需要的社区驱动 zip，有几个放几个

```text
/opt/esxi-build/
├── VMware-ESXi-8.0-20513097-depot.zip
├── nvme-community-driver_1.0.1.0-3vmw.700.1.0.15843807-component-18902434.zip
├── Net-Community-Driver_1.2.7.0-1vmw.700.1.0.15843807_19480755.zip
└── ESXi800-VMKUSB-NIC-FLING-61054763-component-20826251.zip
```

在这个目录执行：

```bash
cd /opt/esxi-build
docker run --rm -v "$PWD":/data easy-esxi-builder
```

ISO 写回当前目录，名字类似 `ESXi-8.0.0-20513097-standard-custom.iso`。

脚本会自己找出官方底包，加载其余 zip，只把新出现的软件包打进克隆出来的 `*-standard` profile，然后导出 ISO。社区驱动要求接受级别 `CommunitySupported`。和原有驱动冲突时会先卸掉冲突包再重试，例如 USB 网卡 Fling 会换掉 `vmkusb`。

zip 和生成的 ISO 不要提交到这个仓库。

## 可选环境变量

| 变量 | 默认 | 作用 |
|---|---|---|
| `ESXI_PROFILE_KIND` | `standard` | 设为 `no-tools` 时克隆不带 VMware Tools 的 profile |
| `ESXI_VENDOR` | `custom` | 新 profile 的 vendor |
| `ESXI_ISO` | `/data/<profile>-custom.iso` | ISO 导出路径 |

```bash
docker run --rm \
  -e ESXI_PROFILE_KIND=no-tools \
  -v "$PWD":/data \
  easy-esxi-builder
```

手工逐条加载 depot 的旧流程见 [苏洋的构建笔记](https://soulteary.com/2023/01/29/how-to-easily-create-and-install-a-custom-esxi-image.html)。
