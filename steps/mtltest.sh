# mtltest: data-a-live's Metal test program, built here although no metal compiler runs off macOS. Its shaders
# come as AIR: taken from the metallib inside the mtltest that data-a-live's CI built (its release), each
# function's AIR module disassembled and linked into one module with Rust's llvm-tools (LLVM 21+ reads Apple's
# AIR), assembled again with llvm-as and embedded; mtltest built with MTLTEST_AIR hands that bare AIR to the
# plugin's own native_bridge_metal_library_with_air. mtltest.m is taken at the commit that release was built
# from, so the shaders and the program match. MTLTEST_AIR_LL=FILE uses an AIR text of your own instead (for
# example the extracted one, edited). Out: $OUT/mtltest.
# shellcheck shell=bash

step_mtltest() {
	local SDK; SDK=$(sdk_path)
	local B=$WORK/build/mtltest O=$OUT/mtltest R
	R=$(rust_bin)
	say "mtltest"
	rm -rf "$B" "$O"; mkdir -p "$B/ci" "$B/gen" "$O"
	local f
	for f in BUILD.txt SHA256SUMS.metal mtltest; do
		curl -sSfL --retry 3 --max-time 600 -o "$B/ci/$f" "$MTLTEST_RELEASE/$f" || die "could not download $f from $MTLTEST_RELEASE"
	done
	[ "$(grep ' mtltest$' "$B/ci/SHA256SUMS.metal" | cut -c1-64)" = "$(sha256sum "$B/ci/mtltest" | cut -c1-64)" ] ||
		die "the release's mtltest does not match its SHA256SUMS.metal"
	local commit; commit=$(awk '/^commit/ {print $2}' "$B/ci/BUILD.txt")
	[ -n "$commit" ] || die "no commit in the release's BUILD.txt"
	note "CI mtltest of data-a-live ${commit:0:9}"
	fetch data-a-live-mtltest "$DATA_A_LIVE_URL" "$commit"
	local SRC=$WORK/src/data-a-live-mtltest/tools/metal
	grep -q MTLTEST_AIR "$SRC/mtltest.m" ||
		die "mtltest.m at ${commit:0:9} predates local builds (no MTLTEST_AIR); a newer data-a-live CI build is needed"

	local LL=${MTLTEST_AIR_LL:-$B/mtltest.air.ll}
	if [ -z "${MTLTEST_AIR_LL:-}" ]; then
		note "shaders: AIR from the release's metallib"
		mkdir -p "$B/air"
		python3 -I "$HERE/tools/air_from_metallib.py" "$B/ci/mtltest" "$B/air"
		"$R/llvm-link" "$B"/air/f*.bc -o "$B/air/linked.bc"
		"$R/llvm-dis" "$B/air/linked.bc" -o "$LL"
	fi
	note "$(grep -c '^define' "$LL") shader functions"
	"$R/llvm-as" -o "$B/mtltest_air" "$LL"
	(cd "$B" && xxd -i mtltest_air > gen/mtltest_air.h)
	"$LLVM/clang" -target arm64-apple-ios16.0 -isysroot "$SDK" -O2 -g -fstack-protector-strong \
		-fuse-ld="$LLVM/ld64.lld" -mlinker-version=907 -DMTLTEST_AIR -fobjc-arc -Wall -I "$B/gen" "$SRC/mtltest.m" \
		-framework Foundation -framework Metal -framework IOSurface -o "$O/mtltest"
	rcodesign sign "$O/mtltest" >/dev/null 2>&1
	(cd "$O" && sha256sum mtltest > SHA256SUMS)
	note "$O/mtltest"
}
