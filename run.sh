#!/bin/bash
# xnu-ios-build-linux: build iOS 16 arm64 software for data-a-live's Metal-on-Adreno stack on Linux / WSL 2, no Xcode.
#
#   ./run.sh               everything: setup, sdk, sources, plugin, turnip, mtltest
#   ./run.sh setup         the build machine's tools (apt packages, Rust + iOS target, meson, rcodesign)
#   ./run.sh sdk [PATH]    prepare an iPhoneOS SDK (a .sdk folder, .zip, .tar.* or Xcode .xip; found or offered if none)
#   ./run.sh sources       fetch every source at its pinned commit and make the patched trees
#   ./run.sh plugin        NativeAdrenoMetal.bundle          -> $WORK/out/plugin
#   ./run.sh turnip        libvulkan_freedreno.dylib, vktest -> $WORK/out/turnip
#   ./run.sh mtltest       mtltest                           -> $WORK/out/mtltest
#   ./run.sh clean         remove builds and outputs (keeps tools, sources and the SDK)
#
# WORK is $XNU_IOS_BUILD_WORK or ~/.cache/xnu-ios-build-linux. Each step skips what is already done, so running again
# after a failure carries on. Read DISCLAIMER.md first.
set -Eeuo pipefail
# a failing command says where, instead of the script just stopping
trap 'printf "\033[1;31mxx\033[0m failed: %s (%s line %s)\n" "$BASH_COMMAND" "${BASH_SOURCE[0]##*/}" "$LINENO" >&2' ERR
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
for s in setup sdk sources plugin turnip mtltest; do
	. "$HERE/steps/$s.sh"
done

summary() {
	say "outputs (in $OUT)"
	local f
	for f in plugin/NativeAdrenoMetal.bundle/NativeAdrenoMetal turnip/libvulkan_freedreno.dylib turnip/vktest mtltest/mtltest; do
		[ -f "$OUT/$f" ] && note "$(du -h "$OUT/$f" | cut -f1)	$OUT/$f"
	done
	note "each folder has SHA256SUMS; all are ad-hoc signed (put their CDHashes in a trust cache to run them)"
}

cmd=${1:-all}
case $cmd in
setup) step_setup ;;
sdk) step_setup; step_sdk "${2:-}" ;;
sources) step_setup; step_sources ;;
plugin|turnip|mtltest) step_setup; step_sdk; step_sources; "step_$cmd"; summary ;;
all)
	step_setup; step_sdk "${2:-}"; step_sources; step_plugin; step_turnip
	# mtltest depends on a data-a-live CI build new enough for it; the rest stands without it
	( step_mtltest ) || warn "mtltest was not built (see above); plugin and Turnip are"
	summary ;;
clean) rm -rf "$WORK/build" "$WORK/out" "$WORK/tree/tu-build"; say "cleaned builds and outputs" ;;
-h|--help|help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
*) die "unknown command $cmd (./run.sh help)" ;;
esac
