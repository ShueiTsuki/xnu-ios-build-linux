# xnu-ios-build-linux

[中文](#中文) · [English](#english)

## 中文

这个仓库在 Linux 上编译 [Data A Live](https://github.com/ShueiTsuki/data-a-live) 的 GPU 部分，不用 Mac，也不用 Xcode。Windows 上可以在 WSL 2 里跑。

Data A Live 让小米 17 Pro 跑 iOS 16。iOS 的 Metal 要靠这里编出来的程序才能跑在手机的 Adreno 显卡上。

使用前请先读 [DISCLAIMER.md](DISCLAIMER.md)。编译要用苹果的 iPhoneOS SDK，按苹果的条款取得和使用它是你自己的责任。

### 编出来的文件

- `NativeAdrenoMetal.bundle`：UniXNU 的 NativeMetal 插件，用 data-a-live 的 `adapt_ios16.py` 改成适配 iOS 16。iOS 程序的 Metal 调用由它交给 metal2vulkan 翻译，再交给 Turnip 执行。
- `libvulkan_freedreno.dylib`：Mesa 的 Turnip，也就是 Adreno 显卡的 Vulkan 驱动。打了 UniXNU 的补丁，通过 Darwin 内核接口和显卡通信。
- `vktest`：Vulkan 自测程序，源码在 data-a-live 的 `tools/vktest`。
- `mtltest`：Metal 自测程序，源码在 data-a-live 的 `tools/metal`。

四个文件都是 iOS arm64 程序，做了临时签名（ad hoc）。每个输出目录里有一份 `SHA256SUMS`。在手机上运行前，要把它们的 CDHash 放进信任列表。

### 怎么用

要一台用 apt 的 Linux，比如 Debian、Ubuntu，或者 WSL 2 里的 Ubuntu。装软件包时会用到 sudo。

```bash
git clone https://github.com/ShueiTsuki/xnu-ios-build-linux
cd xnu-ios-build-linux
./run.sh
```

`./run.sh` 按下面的顺序做：

1. 装工具。用 apt 装缺的包，里面有 clang 18、lld 18、glslc 等。没有 rustup 就先装 rustup，再装 Rust 1.98 和它的 iOS 编译目标、LLVM 工具。meson 1.9.1 装进工作目录里的 Python 虚拟环境。签名工具 rcodesign 0.29 第一次用时由 cargo 编出来。
2. 准备 SDK，细节在下一节。
3. 按 `pins.env` 里写的提交拉源码：UniXNU、AdrenoPM4、NativeAdreno、NativeMetal、NativeMobileDisplay、metal2vulkan、Mesa、data-a-live。这些提交和 data-a-live 线上编译（`.github/workflows/turnip.yml`）用的一样。Mesa 先从 Chromium 的镜像拉，拉不到再从 freedesktop 的 GitLab 拉。补丁打在源码的副本上。
4. 编插件，再编 Turnip 和 vktest。
5. 编 mtltest。这一步失败时，前面编好的插件和 Turnip 照样留着。
6. 列出编好的文件和大小。默认放在 `~/.cache/xnu-ios-build-linux/out/` 下的 `plugin`、`turnip`、`mtltest` 三个目录里。

每一步做完会记下当时用的版本。再运行时，版本没变的步骤直接跳过，所以中途失败了，再运行一次 `./run.sh` 就会接着做。

也可以只做其中一步：

- `./run.sh setup`：只装工具。
- `./run.sh sdk [路径]`：只准备 SDK。
- `./run.sh sources`：只拉源码、打补丁。
- `./run.sh plugin`、`./run.sh turnip`、`./run.sh mtltest`：只编其中一样。
- `./run.sh clean`：删掉编译结果和编好的文件，工具、源码和 SDK 留着。
- `./run.sh help`：列出这些命令。

### SDK 从哪来

脚本按这个顺序找 SDK：

1. 你给的路径：`./run.sh all /路径/iPhoneOS16.x.sdk`，或者设环境变量 `IOS_SDK`。可以是 `.sdk` 文件夹、`.zip`、`.tar.*`，也可以是 Xcode 的 `.xip`。从 `.xip` 里只解出 iPhoneOS SDK。
2. 以前准备好的那份。
3. 常见的位置：`~/theos/sdks`、`/opt/theos/sdks`、`~/sdks`、`~/Downloads`、仓库下的 `sdks/`。在这些地方找 iPhoneOS 16 或 15 的 SDK。
4. 还找不到，脚本会说明情况，等你在终端里输入「我同意」，再从 GitHub 上的第三方合集下载 iPhoneOS16.5.sdk 这一个文件夹。先试 Theos 的 `theos/sdks`，不行再试 `xybp888/iOS-SDKs`。

找到的 SDK 会复制到工作目录里，脚本改的是这份副本。准备好以后，脚本用它编一个 ObjC 和一个 ObjC++ 的小程序，确认能链接出 arm64 程序。

SDK 要用 iOS 15 或 16 的。Xcode 27.2 带的 iOS SDK，库存根（`.tbd`）里只有 arm64e。iPhone X 这一代芯片（A11）是 arm64，用它链接不上。它的 C++ 头文件对 clang 18 也太新。Theos 那种从系统里导出的 iOS 16 SDK 能用。这类 SDK 的 `.tbd` 里写着 `platform: (null)`，ld64.lld 不认，脚本会把这一行改成 `ios`。

### 可以调的环境变量

- `XNU_IOS_BUILD_WORK`：工作目录，工具、源码、SDK 和编译结果都放在这里。默认 `~/.cache/xnu-ios-build-linux`。
- `IOS_SDK`：SDK 的位置，作用和 `./run.sh sdk 路径` 一样。
- `XNU_IOS_BUILD_ACCEPT_SDK_TERMS=1`：下载 SDK 前不在终端里问，自动化时用。设了它，等于你接受上面说的责任。
- `ADRENO_MAX_IBS`：每次提交给显卡的命令缓冲个数上限。默认 128，对应 data-a-live 的内核。UniXNU 原版内核用 16。
- `SRC_<名字>`：用本地的 git 仓库代替下载，比如 `SRC_MESA=~/mesa`。
- `MTLTEST_AIR_LL`：编 mtltest 时用你自己的 AIR 文本。
- `LLVM`：clang 18 所在的目录，默认 `/usr/lib/llvm-18/bin`。

### 签名

Linux 上没有苹果的 `codesign`，脚本用 rcodesign 签名。它做的临时签名和 `codesign -s -` 是同一种。

ld64.lld 链接时会顺手签一次名。之后改库的 install name、去掉符号，这个签名就不对了，所以每个文件最后都用 rcodesign 重签一遍。插件签名时用的标识是 `org.blu-sharky.NativeAdrenoMetal`，和 data-a-live 线上编译的一样。

`rcodesign verify` 检查这种签名会报错，检查苹果 `codesign` 签出来的文件也一样报错。这个报错可以不管。

### 编译中处理过的问题

- metal2vulkan 的测试用例里有 `captures(none)`，这是 LLVM 21 才有的写法，系统的 LLVM 18 读不了。脚本处理 AIR 时用 Rust 自带的 LLVM 工具。
- NativeMetal 的自检会调用 `-[MTLSharedEvent waitUntilSignaledValue:timeoutMS:]`，iOS 16 SDK 里没有这个声明。脚本在编译目录里放一份加了这一行的 `MTLEvent.h`，编译时先找到这一份。
- NativeMetal 用 `../NativeMobileDisplay/` 引用头文件，所以编译时这两个仓库放在同一层目录里。
- Metal 着色器只能用苹果的 metal 编译器编，这个编译器只有 macOS 版。脚本下载 data-a-live 线上编好的 mtltest，从它里面的 metallib 取出每个着色器的 AIR，合并后重新汇编，嵌进本地编的 mtltest。运行时 mtltest 把这段 AIR 交给插件的 `native_bridge_metal_library_with_air` 直接加载。这要求线上那次编译用的 `mtltest.m` 已经支持 `MTLTEST_AIR`，不支持时这一步会报错退出。

### 出问题时

WSL 里连不上 GitHub，几毫秒就报 `Couldn't connect to server`，多半是 Windows 的 hosts 文件里有一行把 `github.com` 指向 `127.0.0.1`。GitHub 加速工具常这么做。WSL 默认照搬 Windows 的 hosts，可是在 WSL 里 `127.0.0.1` 指的是 WSL 自己，那里没有程序在接。下面三种办法选一种：

- 删掉 hosts 里那一行。
- 在 `/etc/wsl.conf` 的 `[network]` 下面写 `generateHosts = false`，然后重启 WSL。
- 改用 WSL 的镜像网络模式。

脚本拉源码前会检查这一点并给出提示。也可以用 `SRC_<名字>` 指向已经下载好的本地仓库。

某一步失败了，再运行一次 `./run.sh`，做过的步骤会跳过。要从头编，先运行 `./run.sh clean`。

### 许可证

这个仓库里的脚本用 MIT 协议，条款在 [LICENSE](LICENSE) 里。脚本拉下来的第三方源码，和打在上面的补丁，保留原来的协议。

## English

This repository builds the GPU part of [Data A Live](https://github.com/ShueiTsuki/data-a-live) on Linux, without a Mac or Xcode. On Windows it runs in WSL 2.

Data A Live runs iOS 16 on the Xiaomi 17 Pro. iOS's Metal needs the programs built here to run on the phone's Adreno GPU.

Read [DISCLAIMER.md](DISCLAIMER.md) before use. The build needs Apple's iPhoneOS SDK, and getting and using it under Apple's terms is your responsibility.

### What it builds

- `NativeAdrenoMetal.bundle`: UniXNU's NativeMetal plugin, adapted to iOS 16 by data-a-live's `adapt_ios16.py`. It takes the Metal calls of iOS programs, has metal2vulkan translate them, and hands the result to Turnip.
- `libvulkan_freedreno.dylib`: Mesa's Turnip, the Vulkan driver for Adreno GPUs, with UniXNU's patches. It talks to the GPU through the Darwin kernel interface.
- `vktest`: a Vulkan self-test, from data-a-live's `tools/vktest`.
- `mtltest`: a Metal self-test, from data-a-live's `tools/metal`.

All four are iOS arm64 programs with an ad hoc signature. Each output folder has a `SHA256SUMS`. To run them on the phone, put their CDHashes in a trust cache.

### Use

You need a Linux that uses apt, such as Debian, Ubuntu, or Ubuntu in WSL 2. Installing packages uses sudo.

```bash
git clone https://github.com/ShueiTsuki/xnu-ios-build-linux
cd xnu-ios-build-linux
./run.sh
```

`./run.sh` does this, in order:

1. Installs tools. Missing apt packages, among them clang 18, lld 18 and glslc. rustup if it is missing, then Rust 1.98 with its iOS target and LLVM tools. meson 1.9.1 in a Python virtual environment in the work folder. rcodesign 0.29, built once with cargo.
2. Prepares an SDK, described in the next section.
3. Fetches the sources at the commits in `pins.env`: UniXNU, AdrenoPM4, NativeAdreno, NativeMetal, NativeMobileDisplay, metal2vulkan, Mesa and data-a-live. They are the commits data-a-live's CI uses (`.github/workflows/turnip.yml`). Mesa comes from Chromium's mirror, or from freedesktop's GitLab when the mirror fails. Patches go on copies of the sources.
4. Builds the plugin, then Turnip and vktest.
5. Builds mtltest. If this step fails, the plugin and Turnip built before it stay.
6. Lists the built files and their sizes. By default they are in `plugin`, `turnip` and `mtltest` under `~/.cache/xnu-ios-build-linux/out/`.

Each step records the versions it was done with. A later run skips the steps whose versions are unchanged, so after a failure, running `./run.sh` again carries on.

Single steps:

- `./run.sh setup`: the tools only.
- `./run.sh sdk [PATH]`: the SDK only.
- `./run.sh sources`: fetch the sources and patch them.
- `./run.sh plugin`, `./run.sh turnip`, `./run.sh mtltest`: build one of them.
- `./run.sh clean`: delete the builds and built files, keeping the tools, sources and SDK.
- `./run.sh help`: list these commands.

### Where the SDK comes from

The script looks for an SDK in this order:

1. The path you give: `./run.sh all /path/iPhoneOS16.x.sdk`, or the `IOS_SDK` environment variable. It can be a `.sdk` folder, a `.zip`, a `.tar.*` or an Xcode `.xip`. From a `.xip` only the iPhoneOS SDK is unpacked.
2. The one prepared on an earlier run.
3. The usual places: `~/theos/sdks`, `/opt/theos/sdks`, `~/sdks`, `~/Downloads` and `sdks/` in the repository. It looks there for an iPhoneOS 16 or 15 SDK.
4. If there is still none, the script explains, waits for you to type "I agree" in the terminal, and then downloads only the iPhoneOS16.5.sdk folder from a third-party collection on GitHub: Theos' `theos/sdks` first, then `xybp888/iOS-SDKs`.

The SDK is copied into the work folder, and the script changes that copy. Then it builds a small ObjC program and a small ObjC++ program with it, to check that they link for arm64.

Use an iOS 15 or 16 SDK. The iOS SDK in Xcode 27.2 lists only arm64e in its library stubs (`.tbd`). The iPhone X generation (A11) is arm64, so nothing links with it. Its C++ headers are also too new for clang 18. iOS 16 SDKs made from the OS, like Theos' ones, work. Their `.tbd` files say `platform: (null)`, which ld64.lld refuses, and the script changes that line to `ios`.

### Environment variables

- `XNU_IOS_BUILD_WORK`: the work folder for tools, sources, the SDK and builds. Default `~/.cache/xnu-ios-build-linux`.
- `IOS_SDK`: where the SDK is, the same as `./run.sh sdk PATH`.
- `XNU_IOS_BUILD_ACCEPT_SDK_TERMS=1`: download the SDK without the question in the terminal, for automation. Setting it means you accept the responsibility described above.
- `ADRENO_MAX_IBS`: the most command buffers in one GPU submission. 128 by default, for data-a-live's kernel. Original UniXNU kernels take 16.
- `SRC_<NAME>`: a local git checkout instead of a download, for example `SRC_MESA=~/mesa`.
- `MTLTEST_AIR_LL`: your own AIR text for mtltest.
- `LLVM`: the folder with clang 18, default `/usr/lib/llvm-18/bin`.

### Signing

Linux has no Apple `codesign`, so the script signs with rcodesign. Its ad hoc signature is the same kind `codesign -s -` makes.

ld64.lld signs each file as it links it. Changing a library's install name and stripping symbols afterwards makes that signature wrong, so every file is signed again with rcodesign at the end. The plugin gets the identifier `org.blu-sharky.NativeAdrenoMetal`, as on data-a-live's CI.

`rcodesign verify` reports errors for these signatures, and for files signed by Apple's `codesign` too. Those errors can be ignored.

### Problems the build works around

- metal2vulkan's test cases contain `captures(none)`, which is LLVM 21 syntax. The system's LLVM 18 cannot read it, so the script handles AIR with the LLVM tools that come with Rust.
- NativeMetal's self-checks call `-[MTLSharedEvent waitUntilSignaledValue:timeoutMS:]`, which the iOS 16 SDK does not declare. The script puts a copy of `MTLEvent.h` with that line in the build folder, where the compiler finds it first.
- NativeMetal includes headers from `../NativeMobileDisplay/`, so the build puts the two repositories side by side.
- Metal shaders compile only with Apple's metal compiler, which exists only for macOS. The script downloads the mtltest that data-a-live's CI built, takes each shader's AIR out of its metallib, links and assembles it again, and embeds it in the mtltest built here. At run time mtltest hands that AIR to the plugin's `native_bridge_metal_library_with_air`. This needs a CI build whose `mtltest.m` supports `MTLTEST_AIR`. With an older one the step stops with an error.

### When something goes wrong

If WSL cannot reach GitHub and fails with `Couldn't connect to server` within milliseconds, the Windows hosts file most likely maps `github.com` to `127.0.0.1`. GitHub accelerators often do this. WSL copies the Windows hosts file, but inside WSL `127.0.0.1` is WSL itself, where nothing listens. Pick one fix:

- Remove that line from the hosts file.
- Write `generateHosts = false` under `[network]` in `/etc/wsl.conf` and restart WSL.
- Switch WSL to mirrored networking.

The script checks for this before fetching sources. `SRC_<NAME>` can also point at local checkouts you already have.

If a step fails, run `./run.sh` again, and the finished steps are skipped. To build from the start, run `./run.sh clean` first.

### Licence

The scripts in this repository are under the MIT licence, in [LICENSE](LICENSE). The third-party sources the scripts fetch, and the patches applied to them, keep their own licences.
