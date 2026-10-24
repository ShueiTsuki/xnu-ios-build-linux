# Shared by run.sh and the steps: where things go, messages, done-markers, git fetches at a pinned commit.
# shellcheck shell=bash

# Everything the toolchain makes lives under WORK (tools, sources, the prepared SDK, builds, outputs).
WORK=${XNU_IOS_BUILD_WORK:-$HOME/.cache/xnu-ios-build-linux}
OUT=$WORK/out
mkdir -p "$WORK" "$OUT"

# shellcheck source=../pins.env
. "$HERE/pins.env"

LLVM=${LLVM:-/usr/lib/llvm-$LLVM_MAJOR/bin}
export PATH="$WORK/tools/bin:$WORK/venv/bin:$HOME/.cargo/bin:$PATH"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# A step is done when its marker holds the same key (pins, options) as now; run it again when they change.
done_with() { [ -f "$WORK/.done/$1" ] && [ "$(cat "$WORK/.done/$1")" = "$2" ]; }
mark_done() { mkdir -p "$WORK/.done"; printf '%s' "$2" > "$WORK/.done/$1"; }

# root, or sudo for what needs it
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }

# fetch NAME URLS SHA: $WORK/src/NAME at SHA (one commit, shallow), from SRC_<NAME> when that names a local
# git checkout. URLS may list several, tried in turn. Nothing is fetched when it is already there.
fetch() {
	local name=$1 urls=$2 sha=$3 dir=$WORK/src/$1 var url
	var=SRC_$(echo "$name" | tr 'a-z-' 'A-Z_')
	if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$sha" ]; then
		note "$name ${sha:0:9} (have it)"
		return
	fi
	rm -rf "$dir"; mkdir -p "$dir"
	git -C "$dir" init -q
	[ -n "${!var:-}" ] && urls=${!var}
	for url in $urls; do
		if git -C "$dir" fetch -q --depth 1 "$url" "$sha" 2>/dev/null || git -C "$dir" fetch -q "$url" "$sha" 2>/dev/null; then
			git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
			note "$name ${sha:0:9} from $url"
			return
		fi
		warn "$name: $url did not give ${sha:0:9}"
	done
	die "could not fetch $name at $sha"
}

# copy_tree SRC DST: a fresh working copy of a fetched git tree (patches are applied to copies, never to src/).
copy_tree() {
	rm -rf "$2"
	git clone -q --shared --no-checkout "$1" "$2"
	git -C "$2" -c advice.detachedHead=false checkout -q "$(git -C "$1" rev-parse HEAD)"
}

# Rust's llvm-tools (llvm-as, llvm-dis, llvm-link: LLVM 21+, which reads the AIR the fixtures and Apple's compiler write)
rust_bin() {
	local host
	host=$(rustup run "$RUST_VERSION" rustc -vV | sed -n 's/^host: //p')
	echo "$(rustup run "$RUST_VERSION" rustc --print sysroot)/lib/rustlib/$host/bin"
}

sdk_path() {
	[ -L "$WORK/sdk/current" ] || die "no SDK prepared yet: ./run.sh sdk [PATH]"
	readlink -f "$WORK/sdk/current"
}
