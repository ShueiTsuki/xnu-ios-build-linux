# turnip: Mesa's freedreno Vulkan driver (Turnip) with UniXNU's Darwin kernel backend for iOS 16 arm64, and
# data-a-live's vktest against it, as data-a-live's CI builds them on macOS (tools/turnip/build_ios.sh): meson
# cross-build with clang + ld64.lld against the SDK, llvm-install-name-tool and llvm-strip, then rcodesign.
# The meson build directory is kept ($WORK/tree/tu-build): ninja rebuilds only what changed. Out: $OUT/turnip.
# shellcheck shell=bash

step_turnip() {
	local SDK; SDK=$(sdk_path)
	local T=$WORK/tree O=$OUT/turnip DAL=$WORK/src/data-a-live
	local B=$T/tu-build MESA=$T/mesa ABI=$T/abi CC=$LLVM/clang CXX=$LLVM/clang++
	say "turnip: libvulkan_freedreno.dylib and vktest"
	rm -rf "$O"; mkdir -p "$O" "$B"
	local FLAGS="['-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK', '-fstack-protector-strong']"
	local LINK="['-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK', '-fstack-protector-strong', '-fuse-ld=$LLVM/ld64.lld', '-mlinker-version=907']"
	cat > "$B/ios.cross.new" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
objc = '$CC'
ar = '$LLVM/llvm-ar'
strip = '$LLVM/llvm-strip'
pkg-config = '/usr/bin/false'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = $FLAGS
cpp_args = $FLAGS
objc_args = $FLAGS
c_link_args = $LINK
cpp_link_args = $LINK
objc_link_args = $LINK
EOF
	# a different cross file (another SDK or LLVM) needs a fresh build directory
	if ! cmp -s "$B/ios.cross.new" "$B/ios.cross"; then rm -rf "$B/tu"; mv "$B/ios.cross.new" "$B/ios.cross"; else rm "$B/ios.cross.new"; fi
	local OPTIONS=(-Dgallium-drivers= -Dvulkan-drivers=freedreno -Dfreedreno-kmds=darwin "-Dtu-darwin-abi-dir=$ABI"
		-Dplatforms=macos -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled
		-Dgles2=disabled -Dllvm=disabled -Dshared-glapi=disabled -Dxmlconfig=disabled -Dshader-cache=disabled
		-Dtools= -Dbuild-tests=false -Dvideo-codecs= -Dvulkan-layers= -Dlibunwind=disabled -Dlmsensors=disabled
		-Dvalgrind=disabled -Dexpat=disabled -Dzstd=disabled -Dbuildtype=release -Db_ndebug=true
		-Dtu-builtin-source-id=pandora -Dtu-builtin-pack-header=)
	if [ ! -f "$B/tu/build.ninja" ]; then
		note "meson setup"
		# the build machine's own compiler (meson needs one for generators) is the system cc
		env CC="$CC" CXX="$CXX" CFLAGS= CXXFLAGS= CPPFLAGS= LDFLAGS= CC_FOR_BUILD=cc CXX_FOR_BUILD=c++ \
			meson setup "$B/tu" "$MESA" --cross-file "$B/ios.cross" --wrap-mode=nodownload "${OPTIONS[@]}" > "$B/setup.log" ||
			{ tail -30 "$B/setup.log" >&2; die "meson setup failed (log: $B/setup.log)"; }
	fi
	note "ninja"
	ninja -C "$B/tu" src/freedreno/vulkan/libvulkan_freedreno.dylib > "$B/ninja.log" ||
		{ grep -E 'error|FAILED' "$B/ninja.log" | head -20 >&2; die "Turnip build failed (log: $B/ninja.log)"; }
	local LIB=$O/libvulkan_freedreno.dylib
	cp "$B/tu/src/freedreno/vulkan/libvulkan_freedreno.dylib" "$LIB"
	"$LLVM/llvm-install-name-tool" -id /usr/lib/libvulkan_freedreno.dylib "$LIB"
	"$LLVM/llvm-strip" -x "$LIB"
	"$LLVM/llvm-nm" -g --defined-only "$LIB" | grep -q ' T _vk_icdGetInstanceProcAddr' || die "no vk_icdGetInstanceProcAddr in Turnip"

	note "vktest"
	local V=$WORK/build/vktest; mkdir -p "$V"
	glslangValidator -V --target-env vulkan1.1 --vn fill_spv -o "$V/fill_spv.h" "$DAL/tools/vktest/fill.comp" >/dev/null
	glslangValidator -V --target-env vulkan1.1 --vn tri_vert_spv -o "$V/tri_vert_spv.h" "$DAL/tools/vktest/tri.vert" >/dev/null
	glslangValidator -V --target-env vulkan1.1 --vn tri_frag_spv -o "$V/tri_frag_spv.h" "$DAL/tools/vktest/tri.frag" >/dev/null
	"$CC" -target arm64-apple-ios16.0 -isysroot "$SDK" -fuse-ld="$LLVM/ld64.lld" -mlinker-version=907 -O2 -Wall \
		-I "$MESA/include" -I "$V" "$DAL/tools/vktest/vktest.c" -o "$O/vktest"
	# the name tool and strip change the files after the linker's signature: signed again, ad hoc (codesign -s -)
	local f
	for f in "$LIB" "$O/vktest"; do rcodesign sign "$f" >/dev/null 2>&1; done
	(cd "$O" && sha256sum libvulkan_freedreno.dylib vktest > SHA256SUMS)
	note "$(du -h "$LIB" | cut -f1) $LIB"
}
