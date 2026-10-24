# sdk: an iPhoneOS SDK (headers and .tbd stubs) to compile and link against. This project never ships one.
# Order: the path given (./run.sh sdk PATH or IOS_SDK=PATH; a .sdk folder, .zip, .tar.*, or an Xcode .xip), an
# SDK already prepared, common places (Theos), and only then, after an explicit agreement typed in the terminal,
# a download from a public third-party SDK collection. The SDK is copied into $WORK/sdk and fixed there
# (tbd platform), never changed where it came from.
# shellcheck shell=bash

SDK_PLACES="$HOME/theos/sdks ${THEOS:-/opt/theos}/sdks /opt/theos/sdks $HOME/sdks $HOME/Downloads $HERE/sdks"

# Is DIR an iPhoneOS SDK that links arm64 (A11 and older cannot run arm64e-only stubs)?
sdk_usable() {
	local dir=$1 tbd=$1/usr/lib/libSystem.B.tbd
	[ -f "$tbd" ] || return 1
	grep -qE 'arm64-ios|archs:.*arm64( |,|\])' "$tbd" || { warn "$dir: its stubs are arm64e only"; return 1; }
}

# The SDK's version from its folder name or SDKSettings, for messages.
sdk_version() { basename "$1" | sed -n 's/^iPhoneOS\([0-9.]*\)\.sdk$/\1/p'; }

# prepare SRC: copy (or unpack) it into $WORK/sdk/NAME, fix it, make it current.
sdk_prepare() {
	local src=$1 name dest tmp
	mkdir -p "$WORK/sdk"
	tmp=$(mktemp -d "$WORK/sdk/.unpack.XXXXXX")
	case $src in
	*.xip)
		note "unpacking the iPhoneOS SDK from $src (only the SDK is written)"
		python3 -I "$HERE/tools/unxip.py" "$src" "$tmp"
		;;
	*.zip)
		python3 -I - "$src" "$tmp" <<'EOF'
import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); out = os.path.realpath(sys.argv[2])
for n in z.namelist():
    d = os.path.realpath(os.path.join(out, n))
    assert d == out or d.startswith(out + os.sep), ('unsafe name in the zip', n)
z.extractall(out)
EOF
		;;
	*.tar|*.tar.*|*.tgz) tar -xf "$src" -C "$tmp" --no-same-owner ;;
	*) cp -a "$src" "$tmp/" ;;
	esac
	# the .sdk folder inside (or the unpacked tree itself)
	local found
	found=$(find "$tmp" -maxdepth 3 -type d -name 'iPhoneOS*.sdk' | head -1)
	[ -n "$found" ] || { [ -f "$tmp/usr/lib/libSystem.B.tbd" ] && found=$tmp; }
	[ -n "$found" ] || { rm -rf "$tmp"; die "no iPhoneOS*.sdk inside $src"; }
	name=$(basename "$found"); [ "$name" = "$(basename "$tmp")" ] && name=iPhoneOS.sdk
	dest=$WORK/sdk/$name
	rm -rf "$dest"; mv "$found" "$dest"; rm -rf "$tmp"
	sdk_usable "$dest" || die "$name cannot link for arm64 (use an iOS 15 or 16 SDK)"
	# Theos-style SDKs (stubs made from a dyld cache) say "platform: (null)", which ld64.lld refuses.
	local fixed
	fixed=$( (grep -rlE '^platform: +\(null\)' "$dest" --include='*.tbd' || true) | tee "$WORK/sdk/.fixed" | wc -l)
	[ "$fixed" = 0 ] || xargs -a "$WORK/sdk/.fixed" -d '\n' sed -i -E 's/^platform: +\(null\)/platform:        ios/'
	note "$name: $fixed .tbd files had no platform, now ios"
	ln -sfn "$name" "$WORK/sdk/current"
}

sdk_terms() {
	cat <<'EOF'

  No iPhoneOS SDK was given or found. This project does not include or host Apple's SDK.
  It can fetch one from a public third-party collection on GitHub (Theos' or xybp888's, the way Theos users
  usually get theirs). Those collections are not ours and not Apple's; Apple's SDK is licensed by Apple
  (Xcode and Apple SDKs Agreement), and you are responsible for obtaining and using it under Apple's terms.

  未找到 iPhoneOS SDK。本项目不包含、也不托管苹果的 SDK。
  可以从 GitHub 上公开的第三方合集（Theos 或 xybp888）下载一份。这些合集既不属于本项目，也不属于苹果；
  苹果的 SDK 受苹果的许可协议约束，取得和使用它是否合规由你自己负责。

  Alternatively stop here and run:  ./run.sh sdk /path/to/iPhoneOS16.x.sdk (or .zip / .xip)
  也可以现在停下，改用：            ./run.sh sdk /你的/iPhoneOS16.x.sdk（或 .zip / .xip）

EOF
}

sdk_download() {
	local line who url dir answer
	if [ "${XNU_IOS_BUILD_ACCEPT_SDK_TERMS:-}" != 1 ]; then
		[ -t 0 ] || die "no SDK; give one (./run.sh sdk PATH), or set XNU_IOS_BUILD_ACCEPT_SDK_TERMS=1 to allow the download"
		sdk_terms
		read -r -p "  Type 'I agree' / 输入「我同意」 to download, anything else to stop: " answer
		case $answer in "I agree"|"i agree"|我同意) ;; *) die "stopped: no SDK" ;; esac
	fi
	while read -r who url dir; do
		[ -n "$who" ] || continue
		note "fetching $dir from $who ($url), only that folder"
		local tmp; tmp=$(mktemp -d "$WORK/sdk/.dl.XXXXXX")
		if git clone -q --depth 1 --filter=blob:none --no-checkout "$url" "$tmp/repo" &&
		   git -C "$tmp/repo" sparse-checkout set --no-cone "/$dir/" &&
		   git -C "$tmp/repo" checkout -q && [ -d "$tmp/repo/$dir" ]; then
			sdk_prepare "$tmp/repo/$dir"
			rm -rf "$tmp"
			return
		fi
		rm -rf "$tmp"
		warn "$who did not give $dir"
	done <<< "$SDK_SOURCES"
	die "no SDK could be downloaded"
}

step_sdk() {
	local given=${1:-${IOS_SDK:-}} place cand
	if [ -n "$given" ]; then
		[ -e "$given" ] || die "$given does not exist"
		say "sdk: from $given"
		sdk_prepare "$(readlink -f "$given")"
	elif [ -L "$WORK/sdk/current" ] && sdk_usable "$(readlink -f "$WORK/sdk/current")"; then
		say "sdk: $(basename "$(readlink -f "$WORK/sdk/current")") (prepared before)"
	else
		say "sdk: looking for an iPhoneOS 15/16 SDK"
		for place in $SDK_PLACES; do
			for cand in "$place"/iPhoneOS16*.sdk "$place"/iPhoneOS15*.sdk "$place"/iPhoneOS16*.sdk.zip "$place"/iPhoneOS15*.sdk.zip; do
				[ -e "$cand" ] || continue
				note "found $cand"
				sdk_prepare "$cand"
				break 2
			done
		done
		[ -L "$WORK/sdk/current" ] || sdk_download
	fi
	local sdk; sdk=$(sdk_path)
	note "SDK: $sdk (iOS $(sdk_version "$sdk"))"
	sdk_smoke "$sdk"
}

# A tiny ObjC and ObjC++ program against the SDK: compiles, links, is arm64 Mach-O.
sdk_smoke() {
	local sdk=$1 t; t=$(mktemp -d)
	printf '#import <Foundation/Foundation.h>\n#import <Metal/Metal.h>\nint main(void){@autoreleasepool{id<MTLDevice> d=MTLCreateSystemDefaultDevice();NSLog(@"%%@",d.name);}return 0;}\n' > "$t/t.m"
	printf '#import <Foundation/Foundation.h>\n#include <vector>\n#include <mutex>\nint main(){std::vector<int> v{1,2};std::mutex m;@autoreleasepool{NSLog(@"%%zu",v.size());}return 0;}\n' > "$t/t.mm"
	"$LLVM/clang" -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -fuse-ld="$LLVM/ld64.lld" -mlinker-version=907 \
		"$t/t.m" -framework Foundation -framework Metal -o "$t/m" 2> "$t/err" &&
	"$LLVM/clang++" -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -std=c++17 -fuse-ld="$LLVM/ld64.lld" -mlinker-version=907 \
		"$t/t.mm" -framework Foundation -o "$t/mm" 2>> "$t/err" || { cat "$t/err" >&2; rm -rf "$t"; die "the SDK does not build a test program"; }
	note "smoke test: ObjC and ObjC++ link for arm64 ($(file -b "$t/m" | cut -d, -f1))"
	rm -rf "$t"
}
