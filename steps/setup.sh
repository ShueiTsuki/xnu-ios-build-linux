# setup: the build machine's tools. Distribution packages (Debian/Ubuntu apt), Rust with the iOS target and
# llvm-tools, meson in a venv (UniXNU's pinned Python requirements), rcodesign for ad-hoc signatures.
# shellcheck shell=bash

APT_PACKAGES="git curl ca-certificates xz-utils unzip python3 python3-venv build-essential pkg-config ninja-build
bison flex glslc spirv-tools glslang-tools xxd file clang-$LLVM_MAJOR lld-$LLVM_MAJOR llvm-$LLVM_MAJOR"

# GitHub reachable? WSL copies Windows' hosts file; a GitHub accelerator there that maps github.com to 127.0.0.1
# works for Windows but points WSL at its own loopback, where nothing listens.
net_check() {
	local ip
	ip=$(getent hosts github.com | awk '{print $1; exit}')
	case $ip in
	127.*|::1)
		warn "github.com resolves to $ip here (an entry in /etc/hosts; under WSL it comes from Windows' hosts file,"
		warn "often a GitHub accelerator). Fix one of: remove that entry, set [network] generateHosts = false in"
		warn "/etc/wsl.conf and restart WSL, or use WSL's mirrored networking. Or point SRC_<NAME> at local checkouts."
		;;
	esac
	if ! curl -sS -o /dev/null --max-time 10 https://github.com 2>/dev/null; then
		warn "cannot reach https://github.com: sources come from there unless SRC_<NAME> names local checkouts"
	fi
}

step_setup() {
	local key="$APT_PACKAGES|$RUST_VERSION|$APPLE_CODESIGN_VERSION|$(cat "$HERE/requirements.txt")"
	if done_with setup "$key" && command -v rcodesign >/dev/null; then
		say "setup: done before"
		return
	fi
	say "setup: build machine tools"
	[ "$(uname -s)" = Linux ] || die "this runs on Linux (WSL 2 on Windows)"
	if command -v apt-get >/dev/null; then
		local missing=() p
		for p in $APT_PACKAGES; do
			dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
		done
		if [ ${#missing[@]} -gt 0 ]; then
			note "installing: ${missing[*]}"
			as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
			as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >/dev/null
		fi
	else
		warn "no apt-get: install these yourself: $APT_PACKAGES"
	fi
	[ -x "$LLVM/clang" ] && [ -x "$LLVM/ld64.lld" ] || die "clang and ld64.lld $LLVM_MAJOR not found in $LLVM (set LLVM=...)"

	if ! command -v rustup >/dev/null; then
		note "installing rustup"
		curl -sSf --max-time 300 https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none >/dev/null
	fi
	rustup toolchain install "$RUST_VERSION" --profile minimal --target aarch64-apple-ios --component llvm-tools 2>&1 | tail -1
	"$(rust_bin)/llvm-as" --version | sed -n 's/^ *LLVM version/    llvm-as (Rust llvm-tools)/p'

	if [ ! -x "$WORK/venv/bin/meson" ] ||
	   [ "$("$WORK/venv/bin/pip" freeze 2>/dev/null | grep -cxF -f "$HERE/requirements.txt")" != "$(grep -c . "$HERE/requirements.txt")" ]; then
		note "meson venv in $WORK/venv"
		python3 -m venv "$WORK/venv"
		"$WORK/venv/bin/pip" install -q -r "$HERE/requirements.txt"
	fi
	note "meson $("$WORK/venv/bin/meson" --version)"

	if [ "$(rcodesign --version 2>/dev/null | awk '{print $2}')" != "$APPLE_CODESIGN_VERSION" ]; then
		note "building rcodesign $APPLE_CODESIGN_VERSION (apple-codesign), once"
		cargo "+$RUST_VERSION" install -q --locked apple-codesign --version "$APPLE_CODESIGN_VERSION" --root "$WORK/tools"
	fi
	note "$(rcodesign --version)"
	mark_done setup "$key"
}
