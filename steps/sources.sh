# sources: every source at its pinned commit under $WORK/src, then the patched trees the builds use under
# $WORK/tree: Mesa with UniXNU's patch list, the NativeAdreno ABI header (128 IBs per submission unless
# ADRENO_MAX_IBS=16), and metal2vulkan with NativeMetal's bridge patches (kept, so Rust reuses its build).
# shellcheck shell=bash

step_sources() {
	say "sources: pinned commits"
	net_check
	fetch unixnu "$UNIXNU_URL" "$UNIXNU_SHA"
	fetch adrenopm4 "$ADRENOPM4_URL" "$ADRENOPM4_SHA"
	fetch nativeadreno "$NATIVEADRENO_URL" "$NATIVEADRENO_SHA"
	fetch nativemetal "$NATIVEMETAL_URL" "$NATIVEMETAL_SHA"
	fetch nativemobiledisplay "$NATIVEMOBILEDISPLAY_URL" "$NATIVEMOBILEDISPLAY_SHA"
	fetch metal2vulkan "$METAL2VULKAN_URL" "$METAL2VULKAN_SHA"
	fetch data-a-live "$DATA_A_LIVE_URL" "$DATA_A_LIVE_SHA"
	fetch mesa "$MESA_URL" "$MESA_SHA"

	local T=$WORK/tree
	mkdir -p "$T"

	# Mesa + UniXNU's patches, in the order of its scripts/data/adreno-compiler-inputs.json
	if ! done_with tree-mesa "$MESA_SHA|$UNIXNU_SHA"; then
		say "sources: Mesa with UniXNU's patches"
		copy_tree "$WORK/src/mesa" "$T/mesa"
		local p
		for p in $(python3 -I -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["patches"]))' \
			"$WORK/src/unixnu/scripts/data/adreno-compiler-inputs.json"); do
			note "$p"
			git -C "$T/mesa" apply --whitespace=nowarn "$WORK/src/unixnu/$p"
		done
		rm -rf "$T/tu-build"   # an old build directory belongs to the old tree
		mark_done tree-mesa "$MESA_SHA|$UNIXNU_SHA"
	fi

	# NativeAdreno's ABI header; 128 IBs for a kernel that takes them (data-a-live's), as its CI builds it
	local ibs=${ADRENO_MAX_IBS:-128}
	mkdir -p "$T/abi"
	cp "$WORK/src/nativeadreno/NativeAdrenoABI.h" "$T/abi/new.h"
	case $ibs in
	128) python3 -I "$WORK/src/data-a-live/tools/turnip/abi_128.py" "$T/abi/new.h" >/dev/null ;;
	16) ;;
	*) die "ADRENO_MAX_IBS is 128 or 16" ;;
	esac
	# replaced only when it differs, so a rebuild does not recompile Turnip for an unchanged header
	if cmp -s "$T/abi/new.h" "$T/abi/NativeAdrenoABI.h"; then rm "$T/abi/new.h"; else mv "$T/abi/new.h" "$T/abi/NativeAdrenoABI.h"; fi
	note "ABI header: $ibs IBs per submission"

	# UniXNU with its AdrenoPM4 submodule filled in (the plugin builds kits/AdrenoPM4/AdrenoPM4.c)
	if ! done_with tree-unixnu "$UNIXNU_SHA|$ADRENOPM4_SHA"; then
		copy_tree "$WORK/src/unixnu" "$T/unixnu"
		rm -rf "$T/unixnu/kits/AdrenoPM4"
		copy_tree "$WORK/src/adrenopm4" "$T/unixnu/kits/AdrenoPM4"
		mark_done tree-unixnu "$UNIXNU_SHA|$ADRENOPM4_SHA"
	fi

	# metal2vulkan with NativeMetal's bridge patches, made once and kept
	if ! done_with tree-m2v "$METAL2VULKAN_SHA|$NATIVEMETAL_SHA"; then
		say "sources: metal2vulkan with NativeMetal's bridge patches"
		copy_tree "$WORK/src/metal2vulkan" "$T/metal2vulkan"
		for p in "$WORK"/src/nativemetal/bridge/patches/000*.patch; do
			note "$(basename "$p")"
			git -C "$T/metal2vulkan" apply "$p"
		done
		rm -rf "$WORK/cargo-target"
		mark_done tree-m2v "$METAL2VULKAN_SHA|$NATIVEMETAL_SHA"
	fi
}
