# plugin: UniXNU's NativeMetal plugin (NativeAdrenoMetal.bundle) for iOS 16 arm64, with data-a-live's iOS 16
# adaptation (tools/metal/adapt_ios16.py), the way data-a-live's CI builds it on macOS (tools/metal/build_plugin.sh),
# without Xcode: clang + ld64.lld against the SDK, the metal2vulkan bridge in Rust for aarch64-apple-ios, llvm-as
# from Rust's llvm-tools, rcodesign for the ad-hoc signature. Out: $OUT/plugin.
# shellcheck shell=bash

step_plugin() {
	local SDK; SDK=$(sdk_path)
	local T=$WORK/tree B=$WORK/build/plugin O=$OUT/plugin
	say "plugin: NativeAdrenoMetal.bundle"
	rm -rf "$B" "$O"; mkdir -p "$B/gen" "$O"
	# NativeMetal is edited in place by the adaptation: a fresh copy each build, NativeMobileDisplay beside it
	# (NativeMetal includes ../NativeMobileDisplay/, its sibling under UniXNU's drivers/).
	copy_tree "$WORK/src/nativemetal" "$B/src/nativemetal"
	copy_tree "$WORK/src/nativemobiledisplay" "$B/src/NativeMobileDisplay"
	local NM=$B/src/nativemetal U=$T/unixnu M2V=$T/metal2vulkan MESA=$T/mesa LLVM_AS
	LLVM_AS=$(rust_bin)/llvm-as
	local BASE=(-target arm64-apple-ios16.0 -isysroot "$SDK" -O2 -g -fstack-protector-strong)
	local LINK=(-fuse-ld="$LLVM/ld64.lld" -mlinker-version=907)

	note "NativeMetal for iOS 16 (data-a-live adapt_ios16.py)"
	python3 -I "$WORK/src/data-a-live/tools/metal/adapt_ios16.py" "$NM" > "$B/adapt.log"

	note "smoke shaders (as UniXNU's gen-turnip-smoke-shaders.py)"
	{
		echo '// Generated from NativeMetal/shaders by xnu-ios-build-linux; do not edit.'
		echo '#pragma once'
		echo '#include <stdint.h>'
		local s n
		for s in "$NM"/shaders/smoke_*; do
			n=$(basename "$s")
			glslc --target-env=vulkan1.1 -O "$s" -o "$B/$n.spv"
			spirv-val --target-env vulkan1.1 "$B/$n.spv"
			python3 -I -c 'import struct,sys; d=open(sys.argv[1],"rb").read(); w=struct.unpack("<%dI" % (len(d)//4), d)
print("static const uint32_t kSpv_%s[] = {" % sys.argv[2].replace(".", "_"))
for i in range(0, len(w), 8): print("    " + ", ".join("0x%08x" % x for x in w[i:i+8]) + ",")
print("};")' "$B/$n.spv" "$n"
		done
	} > "$B/gen/NativeTurnipShaders.h"

	note "metal2vulkan bridge (as UniXNU's build-native-metal-bridge.py)"
	# The fixtures use LLVM 21+ syntax (captures(none)): Rust's llvm-as, not the distribution's LLVM 18.
	"$LLVM_AS" -o "$B/runtime_examples.air" "$M2V/crates/metal2vulkan-validation/fixtures/public/examples/runtime_examples.ll"
	"$LLVM_AS" -o "$B/function_constant.air" "$M2V/crates/metal2vulkan-validation/fixtures/public/kernel_function_constant_gate_fold.ll"
	cat > "$B/Cargo.toml" <<EOF
[package]
name = "native-metal-bridge"
version = "0.1.0"
edition = "2024"
rust-version = "${RUST_VERSION%.*}"
[workspace]
[lib]
crate-type = ["staticlib"]
path = "$NM/bridge/NativeMetalBridge.rs"
[dependencies]
metal2vulkan = { path = "$M2V/crates/metal2vulkan", features = ["ash"] }
metal2vulkan-runtime = { path = "$M2V/crates/metal2vulkan-runtime" }
libc = "0.2"
sha2 = { version = "0.10", features = ["asm"] }
[profile.release]
panic = "unwind"
debug = 1
EOF
	local RID TGT=$WORK/cargo-target
	RID=$( (git -C "$M2V" rev-parse HEAD; git -C "$M2V" diff HEAD) | sha256sum | cut -c1-32)
	# C code inside crates (cc-rs) is compiled for the phone with clang against the SDK; nothing is linked here.
	NMB_RUNTIME_ID=$RID NMB_FIXTURE_AIR=$B/runtime_examples.air NMB_FC_AIR=$B/function_constant.air \
		IPHONEOS_DEPLOYMENT_TARGET=16.0 SDKROOT="$SDK" \
		CC_aarch64_apple_ios="$LLVM/clang" CXX_aarch64_apple_ios="$LLVM/clang++" AR_aarch64_apple_ios="$LLVM/llvm-ar" \
		CFLAGS_aarch64_apple_ios="-target arm64-apple-ios16.0 -isysroot $SDK" \
		cargo "+$RUST_VERSION" build -q --release --manifest-path "$B/Cargo.toml" --target aarch64-apple-ios --target-dir "$TGT"
	local BRIDGE=$TGT/aarch64-apple-ios/release/libnative_metal_bridge.a

	note "plugin bundle (as UniXNU's build-adreno-metal-plugin.py)"
	local BUNDLE=$O/NativeAdrenoMetal.bundle
	mkdir -p "$BUNDLE"
	"$LLVM/clang" "${BASE[@]}" -std=c11 -c "$U/kits/AdrenoPM4/AdrenoPM4.c" -o "$B/AdrenoPM4.o"
	# NativeMetal's self-checks call -[MTLSharedEvent waitUntilSignaledValue:timeoutMS:] (the plugin's own event
	# implements it); an iOS 16 SDK does not declare it, so a copy of MTLEvent.h with it is found first.
	local COMPAT=() EVENT_H=$SDK/System/Library/Frameworks/Metal.framework/Headers/MTLEvent.h
	if ! grep -q "waitUntilSignaledValue" "$EVENT_H"; then
		mkdir -p "$B/gen/compat/Metal"
		python3 -I - "$EVENT_H" "$B/gen/compat/Metal/MTLEvent.h" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r'@protocol MTLSharedEvent <MTLEvent>.*?\n@end', t, re.S)
assert m, 'no MTLSharedEvent protocol'
decl = '- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)milliseconds;\n'
open(sys.argv[2], 'w').write(t[:m.end() - 4] + decl + t[m.end() - 4:])
PY
		COMPAT=(-I "$B/gen/compat")
	fi
	# -x drops local symbols (as strip -x on macOS)
	"$LLVM/clang++" "${BASE[@]}" "${LINK[@]}" "${COMPAT[@]}" -std=c++17 -fobjc-arc -Wno-deprecated-declarations -bundle \
		-I "$T/abi" -I "$U/kits/AdrenoPM4" -I "$MESA/include" -I "$B/gen" \
		-x objective-c++ "$NM/NativeAdrenoMetalPlugin.mm" "$NM/NativeBridgeMetalFrontend.mm" -x none \
		"$B/AdrenoPM4.o" "$BRIDGE" -Wl,-dead_strip -Wl,-x -lobjc \
		-framework Foundation -framework Metal -framework IOSurface \
		-o "$BUNDLE/NativeAdrenoMetal" 2> "$B/link.log" || { cat "$B/link.log" >&2; die "plugin link failed"; }
	rm -rf "$BUNDLE/NativeAdrenoMetal.dSYM"
	# ad hoc, with the identifier codesign -s - --identifier gives it on data-a-live's CI
	rcodesign sign --binary-identifier org.blu-sharky.NativeAdrenoMetal "$BUNDLE/NativeAdrenoMetal" >/dev/null 2>&1
	python3 -I - "$BUNDLE/Info.plist" <<'EOF'
import plistlib, sys
plistlib.dump({k: v for k, v in (kv.split('=', 1) for kv in (
	'CFBundleIdentifier=org.blu-sharky.NativeAdrenoMetal', 'CFBundleExecutable=NativeAdrenoMetal',
	'CFBundlePackageType=BNDL', 'CFBundleVersion=1', 'CFBundleShortVersionString=1',
	'NSPrincipalClass=NativeAdrenoMetalDevice', 'MinimumOSVersion=16.0'))}, open(sys.argv[1], 'wb'))
EOF
	(cd "$O" && sha256sum NativeAdrenoMetal.bundle/NativeAdrenoMetal NativeAdrenoMetal.bundle/Info.plist > SHA256SUMS)
	note "$(du -h "$BUNDLE/NativeAdrenoMetal" | cut -f1) $BUNDLE"
}
