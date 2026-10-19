#!/bin/bash
# 05-xp-binpkg-march.sh — refuse binary packages built for a CPU this machine cannot run.
#
# 'xp <profile> binhost' serves one profile's binpkg cache over HTTP, and each cache is
# built for one -march (amdkdehard/nvidiahard: znver3, intelhard: x86-64-v3,
# corehard: x86-64-v2). Portage itself never compares CFLAGS — --binpkg-respect-use
# only checks USE — so a client pointed at the wrong binhost would install code that
# dies with SIGILL. This hook closes that gap for every BINARY merge:
#
#   build -march  = -march= in the package's own build-info/CFLAGS (what it was compiled for)
#   local -march  = -march= in this root's make.conf CFLAGS (what this machine targets)
#   accept        iff gcc's enabled ISA set for the build -march is a subset of the
#                 local one: x86-64-v3 on znver3 is fine, znver3 on x86-64-v3 is not.
#
# A package without -march in its CFLAGS (generic build, or flags stripped by the ebuild)
# passes. A different CHOST is always refused. Source builds are not touched.
# Override for one merge: XP_BINPKG_MARCH_CHECK=no emerge ...
# Shipped by rpilinuxlab genstage/live/common (portage-bashrc-mv drop-in), 2026-10-19.

XpBinpkgMarchIsa() {
	gcc -march="$1" -Q --help=target 2>/dev/null |
		awk '$2=="[enabled]" && $1 ~ /^-m/ {print $1}' | sort -u
}

XpBinpkgMarchOf() {
	local f
	for f in $1; do
		case $f in -march=*) echo "${f#-march=}";; esac
	done | tail -n 1
}

XpBinpkgMarchCheck() {
	[ "${EMERGE_FROM}" = binary ] || return 0
	BashrcdTrue "${XP_BINPKG_MARCH_CHECK:-yes}" || return 0
	local info="${PORTAGE_BUILDDIR}/build-info" mc="${PORTAGE_CONFIGROOT%/}/etc/portage/make.conf"
	local bchost bflags bmarch lflags lmarch missing
	[ -r "${info}/CFLAGS" ] || return 0
	bchost=$(cat "${info}/CHOST" 2>/dev/null)
	if [ -n "${bchost}" ] && [ -n "${CHOST}" ] && [ "${bchost}" != "${CHOST}" ]; then
		die "xp binpkg guard: ${CATEGORY}/${PF} was built for CHOST=${bchost}, this root is ${CHOST}"
	fi
	bflags=$(cat "${info}/CFLAGS")
	bmarch=$(XpBinpkgMarchOf "${bflags}")
	[ -n "${bmarch}" ] || return 0
	# a clean shell: inside the ebuild environment some make.conf assignments hit
	# readonly variables and abort the source before the line that sets -march
	lflags=$(env -i /bin/bash -c '. "$1" >/dev/null 2>&1; echo "${CFLAGS}"' _ "${mc}")
	lmarch=$(XpBinpkgMarchOf "${lflags}")
	[ -n "${lmarch}" ] || lmarch=x86-64
	[ "${bmarch}" = "${lmarch}" ] && return 0
	missing=$(comm -23 <(XpBinpkgMarchIsa "${bmarch}") <(XpBinpkgMarchIsa "${lmarch}") | tr '\n' ' ')
	if [ -n "${missing}" ]; then
		eerror "xp binpkg guard: ${CATEGORY}/${PF} was built with -march=${bmarch},"
		eerror "this root's make.conf targets -march=${lmarch}, which lacks: ${missing}"
		eerror "Wrong binhost? 'xp <profile> binhost' serves one -march per cache."
		die "binary package -march=${bmarch} is not runnable on -march=${lmarch}"
	fi
	einfo "xp binpkg guard: -march=${bmarch} is a subset of -march=${lmarch}, accepted"
}

BashrcdPhase setup XpBinpkgMarchCheck
