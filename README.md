# xnu-ios-build-linux

> **Disclaimer first / 先读免责声明:** not affiliated with Apple, Qualcomm, Xiaomi, Google, UniXNU, Mesa or
> metal2vulkan. **No Apple software is included or hosted here.** You need your own iPhoneOS SDK and are
> responsible for obtaining and using it under Apple's terms. Provided as is, at your own risk; for research,
> interoperability and education. Full text: [DISCLAIMER.md](DISCLAIMER.md).
>
> 本项目与苹果、高通、小米、谷歌、UniXNU、Mesa、metal2vulkan 均无关联。**这里不包含、也不托管任何苹果软件。**
> 你需要自备 iPhoneOS SDK，并自行负责按苹果的条款取得和使用它。按现状提供，风险自负；仅用于研究、互操作和学习。
> 全文见 [DISCLAIMER.md](DISCLAIMER.md)。

[中文](#中文) · [English](#english)

---

## 中文

### 这是什么

在 Linux（包括 Windows 上的 WSL 2）上，不用 Mac、不用 Xcode，一条命令编出 [Data A Live](https://github.com/ShueiTsuki/data-a-live)
（小米 17 Pro 上跑 iOS 16）GPU 这一套要用的 iOS arm64 程序：

| 产物 | 是什么 |
|---|---|
| `NativeAdrenoMetal.bundle` | UniXNU 的 NativeMetal 插件，经 data-a-live 适配 iOS 16：让 iOS 的 Metal 通过 metal2vulkan 跑在 Turnip 上 |
| `libvulkan_freedreno.dylib` | Mesa 的 Turnip（Adreno 的 Vulkan 驱动），带 UniXNU 的 Darwin 内核接口 |
| `vktest` | Vulkan 自测程序 |
| `mtltest` | Metal 自测程序（不需要 Apple 的 metal 编译器，见下文） |

### 用法

```bash
git clone https://github.com/ShueiTsuki/xnu-ios-build-linux
cd xnu-ios-build-linux
./run.sh
```

就这一条。它会依次：

1. **装工具**：用 apt 装缺的包（clang 18、lld、glslc 等），装 Rust 1.98（含 iOS 编译目标和 LLVM 工具）、meson 1.9.1、签名工具 rcodesign。
2. **准备 SDK**：先用你给的（`./run.sh all /路径/iPhoneOS16.x.sdk`，也可以是 `.zip`、`.tar.*` 或 Xcode 的 `.xip`），再找常见位置（如 `~/theos/sdks`）。
   都没有时，会说明情况，**等你在终端里输入「我同意」**，才从公开的第三方合集（Theos 的 `theos/sdks`，备选 `xybp888/iOS-SDKs`）只下载 iPhoneOS16.5.sdk 这一个文件夹。
   SDK 会复制到工作目录里再修正，原来的文件不动。
3. **拉源码**：按固定版本拉取 UniXNU、NativeMetal、NativeAdreno、NativeMobileDisplay、AdrenoPM4、metal2vulkan、Mesa、data-a-live，打好补丁。
4. **编译并签名**：插件、Turnip、vktest、mtltest，全部做临时签名（ad hoc）。
5. **告诉你产物在哪**：默认在 `~/.cache/xnu-ios-build-linux/out/`。

每一步做过就跳过，中途失败了再运行一次会接着做。也可以只做其中一步：`./run.sh setup | sdk [路径] | sources | plugin | turnip | mtltest | clean`。

可调的设置：

| 变量 | 作用 |
|---|---|
| `XNU_IOS_BUILD_WORK` | 工作目录（工具、源码、SDK、编译结果），默认 `~/.cache/xnu-ios-build-linux` |
| `IOS_SDK` | SDK 的位置，和 `./run.sh sdk 路径` 一样 |
| `XNU_IOS_BUILD_ACCEPT_SDK_TERMS=1` | 不在终端里问，直接同意下载 SDK（自动化用；同样表示你接受上面的责任） |
| `ADRENO_MAX_IBS` | 128（默认，data-a-live 的内核）或 16（UniXNU 上游内核） |
| `SRC_<名字>` | 用本地的 git 仓库代替下载，例如 `SRC_MESA=~/mesa` |
| `MTLTEST_AIR_LL` | 用你自己的 AIR 文本编 mtltest |
| `LLVM` | clang 18 的位置，默认 `/usr/lib/llvm-18/bin` |

### 为什么这样选

- **SDK 用 iOS 15/16 的。** 新版 Xcode（例如 27.2）带的 iOS SDK，库存根（`.tbd`）只写了 arm64e，iPhone X 这一代（A11）是 arm64，链接不上；它的 C++ 头文件对 clang 18 也太新。
  社区常见的 iOS 16 SDK（Theos 那种，从系统里导出的）可以用，只是 `.tbd` 里写着 `platform: (null)`，ld64.lld 不认，脚本会改成 `ios`。
- **签名用 rcodesign。** Linux 上没有 `codesign`。rcodesign 做的临时签名和 `codesign -s -` 是同一种，手机上把它的 CDHash 放进信任列表就能运行。
  注意：`rcodesign verify` 对这种签名会报错（对 Apple 自己的 `codesign` 签出来的也一样），它自己也说明这个功能不可靠，不用管它。
- **链接器自带的签名不够。** ld64.lld 链接时能顺手签名（linker-signed），但改名（install name）和去符号（strip）之后签名就失效了，所以最后统一用 rcodesign 重签，插件还带上和线上编译一样的标识。

### 踩过的坑

- **LLVM 版本。** metal2vulkan 的测试用例用了 LLVM 21 才有的写法 `captures(none)`，系统自带的 LLVM 18 读不了。脚本用 Rust 自带的 LLVM 工具（22 版）来处理 AIR。
- **旧 SDK 缺一个方法。** NativeMetal 的自检会调用 `-[MTLSharedEvent waitUntilSignaledValue:timeoutMS:]`，iOS 16 SDK 里没有声明。脚本只在编译目录里放一份补了这一行的 `MTLEvent.h`，SDK 本身不动。
- **NativeMobileDisplay 要放在旁边。** NativeMetal 用 `../NativeMobileDisplay/` 引用它的头文件，两个仓库必须是同级目录。
- **mtltest 的着色器。** Metal 着色器只能用 Apple 的 metal 编译器编（只有 macOS 版）。脚本的做法是：取 data-a-live 线上编好的 mtltest，从里面的 metallib 取出每个着色器的 AIR，在本地合并、重新汇编，嵌进本地编的 mtltest；运行时交给插件自带的 `native_bridge_metal_library_with_air` 直接加载，不经过 metallib。这需要 data-a-live 的线上编译足够新（mtltest.m 支持 `MTLTEST_AIR`）。

### 常见问题

- **WSL 里连不上 GitHub（`Couldn't connect to server`，几毫秒就失败）。** 多半是 Windows 的 hosts 文件里有一条把 `github.com` 指向 `127.0.0.1`（GitHub 加速工具常这么做），
  WSL 默认照搬 Windows 的 hosts，可在 WSL 里 `127.0.0.1` 是它自己，没有程序在接。解决办法任选一个：删掉那一条；在 `/etc/wsl.conf` 的 `[network]` 下写 `generateHosts = false` 后重启 WSL；
  或者改用 WSL 的镜像网络模式。脚本在拉源码前会检查这一点并给出提示。也可以用 `SRC_<名字>` 指向已经下载好的本地仓库。
- **中途失败。** 再运行一次 `./run.sh`，做过的步骤会跳过。要从头编，`./run.sh clean`（不删工具、源码和 SDK）。

### 协议

本仓库的脚本采用 [MIT](LICENSE) 协议（ShueiTsuki and contributors）。脚本拉取的第三方源码和对它们的补丁沿用各自原来的协议。

---

## English

### What this is

One command that builds, on Linux (WSL 2 included) and without a Mac or Xcode, the iOS arm64 pieces of
[Data A Live](https://github.com/ShueiTsuki/data-a-live)'s GPU stack (iOS 16 on the Xiaomi 17 Pro):

| Output | What it is |
|---|---|
| `NativeAdrenoMetal.bundle` | UniXNU's NativeMetal plugin with data-a-live's iOS 16 adaptation: iOS Metal through metal2vulkan on Turnip |
| `libvulkan_freedreno.dylib` | Mesa's Turnip (the Adreno Vulkan driver) with UniXNU's Darwin kernel backend |
| `vktest` | Vulkan self-test |
| `mtltest` | Metal self-test (built without Apple's metal compiler, see below) |

### Use

```bash
git clone https://github.com/ShueiTsuki/xnu-ios-build-linux
cd xnu-ios-build-linux
./run.sh
```

That is all. In turn it:

1. **Installs tools**: missing apt packages (clang 18, lld, glslc, ...), Rust 1.98 with the iOS target and LLVM tools, meson 1.9.1, rcodesign.
2. **Prepares an SDK**: the one you give (`./run.sh all /path/iPhoneOS16.x.sdk`, or a `.zip`, `.tar.*` or Xcode `.xip`), else one in a usual place (such as `~/theos/sdks`).
   If there is none, it explains and **waits for you to type "I agree"** before fetching only the iPhoneOS16.5.sdk folder from a public third-party collection (Theos' `theos/sdks`, then `xybp888/iOS-SDKs`).
   The SDK is copied into the work folder and fixed there; the original is left alone.
3. **Fetches sources** at pinned commits (UniXNU, NativeMetal, NativeAdreno, NativeMobileDisplay, AdrenoPM4, metal2vulkan, Mesa, data-a-live) and applies the patches.
4. **Builds and signs** the plugin, Turnip, vktest and mtltest (ad hoc).
5. **Prints where the outputs are**: `~/.cache/xnu-ios-build-linux/out/` by default.

Each step skips what is done, so after a failure just run it again. Single steps: `./run.sh setup | sdk [PATH] | sources | plugin | turnip | mtltest | clean`.

Settings:

| Variable | Effect |
|---|---|
| `XNU_IOS_BUILD_WORK` | work folder (tools, sources, SDK, builds), default `~/.cache/xnu-ios-build-linux` |
| `IOS_SDK` | the SDK, same as `./run.sh sdk PATH` |
| `XNU_IOS_BUILD_ACCEPT_SDK_TERMS=1` | agree to the SDK download without the prompt (automation; you accept the same responsibility) |
| `ADRENO_MAX_IBS` | 128 (default, data-a-live's kernel) or 16 (upstream UniXNU kernels) |
| `SRC_<NAME>` | a local git checkout instead of a download, e.g. `SRC_MESA=~/mesa` |
| `MTLTEST_AIR_LL` | your own AIR text for mtltest |
| `LLVM` | where clang 18 is, default `/usr/lib/llvm-18/bin` |

### Why these choices

- **An iOS 15/16 SDK.** Recent Xcode iOS SDKs (27.2, for one) list only arm64e in their stubs, so nothing links for
  arm64 (A11, iPhone X), and their libc++ headers are too new for clang 18. The usual community iOS 16 SDKs (Theos
  style, made from the OS) work, except that their stubs say `platform: (null)`, which ld64.lld refuses; the script
  rewrites it to `ios`.
- **rcodesign for signing.** There is no `codesign` on Linux. rcodesign's ad-hoc signature is the same kind
  `codesign -s -` makes; put its CDHash in a trust cache on the device. `rcodesign verify` reports errors for such
  signatures (for Apple's own `codesign` output too) and says itself that it is unreliable; ignore it.
- **The linker's own signature is not enough.** ld64.lld can sign as it links (linker-signed), but changing the
  install name and stripping break that signature, so everything is signed again with rcodesign at the end, the
  plugin with the identifier the macOS build gives it.

### Pitfalls met on the way

- **LLVM version.** metal2vulkan's fixtures use `captures(none)`, LLVM 21 syntax that LLVM 18 cannot read; AIR is
  handled with Rust's llvm-tools (LLVM 22).
- **A method an older SDK lacks.** NativeMetal's self-checks call `-[MTLSharedEvent waitUntilSignaledValue:timeoutMS:]`,
  which an iOS 16 SDK does not declare; a copy of `MTLEvent.h` with that line is put in the build folder only.
- **NativeMobileDisplay beside NativeMetal.** NativeMetal includes `../NativeMobileDisplay/`, so the two must be siblings.
- **mtltest's shaders.** Metal shaders compile only with Apple's metal compiler (macOS only). The script takes the
  mtltest data-a-live's CI built, pulls each shader's AIR out of its metallib, links and reassembles it here, embeds it
  in a locally built mtltest, which hands it to the plugin's own `native_bridge_metal_library_with_air` at run time.
  This needs a data-a-live CI build recent enough (mtltest.m with `MTLTEST_AIR`).

### Troubleshooting

- **WSL cannot reach GitHub (`Couldn't connect to server` within milliseconds).** Usually Windows' hosts file maps
  `github.com` to `127.0.0.1` (GitHub accelerators do this) and WSL copies that file, but in WSL `127.0.0.1` is WSL
  itself, where nothing listens. Either remove the entry, set `generateHosts = false` under `[network]` in
  `/etc/wsl.conf` and restart WSL, or use WSL's mirrored networking. The script checks for this before fetching
  sources. `SRC_<NAME>` can also point at local checkouts.
- **A step failed.** Run `./run.sh` again; finished steps are skipped. `./run.sh clean` starts the builds over
  (tools, sources and the SDK are kept).

### Licence

The scripts here are under the [MIT licence](LICENSE) (ShueiTsuki and contributors). The third-party sources they
fetch, and the patches applied to them, keep their own licences.
