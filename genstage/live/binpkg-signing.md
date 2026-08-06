# Binary package signing for live images

The live profiles can consume the build host's binpkg cache
(`PROF_LIVE_FEATURES="... getbinpkg binpkg-request-signature ..."` +
`PROF_LIVE_BINPKGS_DIR`). With `binpkg-request-signature` set, every package
must carry a valid gpkg signature — unsigned leftovers are refused and
rebuilt. This documents how to bootstrap `/etc/portage/gnupg` on the build
host so that works. Replace `<host>` with the build host's hostname
throughout.

## 1. Verification side (every machine that consumes signed binpkgs)

Never create `/etc/portage/gnupg` by hand — bootstrap it with getuto:

```sh
emerge -av app-portage/getuto    # pulls sec-keys/openpgp-keys-gentoo-* too
getuto                           # as root
```

This single command creates the GNUPGHOME at `/etc/portage/gnupg`, generates
a local **Portage Local Trust Key** (`portage@localhost`, passphrase written
to `pass`), and imports + locally-signs the official Gentoo release/binhost
keys so portage accepts Gentoo's signed gpkgs. Re-running `getuto` refreshes
the anchors (stamp file `.getuto.last`). Portage also runs it automatically
on the first emerge when `binpkg-request-signature` is in FEATURES.

## 2. Signing side (build host only)

Generate a dedicated sign-only key inside the portage GNUPGHOME, reusing the
`pass` file getuto already created:

```sh
export GNUPGHOME=/etc/portage/gnupg
gpg --batch --pinentry-mode loopback --passphrase-file "$GNUPGHOME/pass" \
    --quick-generate-key "<host> binpkg signing <binpkg@<host>>" ed25519 sign never
gpg --list-keys --keyid-format long "binpkg@<host>"   # note the fingerprint
echo "<FPR>:6:" | gpg --import-ownertrust             # ultimate trust for own key
```

Then in the host's `make.conf`:

```sh
FEATURES="${FEATURES} buildpkg binpkg-signing"
BINPKG_FORMAT="gpkg"
BINPKG_GPG_SIGNING_DIGEST="SHA512"
BINPKG_GPG_SIGNING_GPG_HOME="/etc/portage/gnupg"
BINPKG_GPG_SIGNING_KEY="0x<FPR>!"
BINPKG_GPG_SIGNING_BASE_COMMAND="/usr/bin/flock /run/lock/portage-binpkg-gpg.lock /usr/bin/gpg --sign --armor --batch --no-tty --yes --pinentry-mode loopback --passphrase-file /etc/portage/gnupg/pass [PORTAGE_CONFIG]"
```

From then on every emerge archives and signs a gpkg. Verify end-to-end:

```sh
quickpkg sys-apps/which
tar -tf /var/cache/binpkgs/sys-apps/which-*.gpkg.tar   # expect *.sig members
```

## 3. Trusting a foreign binhost key on a consumer

If a machine consumes `<host>`'s packages, import the public key and
local-sign it with the consumer's Portage Local Trust Key:

```sh
export GNUPGHOME=/etc/portage/gnupg
gpg --import <host>-binpkg.pub.asc
gpg --pinentry-mode loopback --passphrase-file "$GNUPGHOME/pass" \
    --default-key "<local-trust-key-FPR>" --lsign-key "<FPR>"
```

## How the live images get this for free

None of the above is manual for images built here:

- `xstage <profile> conf` seeds the image's `/etc/portage/gnupg` from the
  host's when `binpkg-request-signature` is in the profile's FEATURES —
  **public material only** (rsync excludes `private-keys-v1.d`, `pass`,
  `openpgp-revocs.d`, `tofu.db`, sockets). The image can verify, never sign.
- `app-portage/getuto` in the profile's package list lets the installed
  system refresh Gentoo anchors on its own later.
- The private key, passphrase and revocation certs exist in exactly one
  place: the build host's `/etc/portage/gnupg` (root-owned). They never
  enter the build tree, the squashfs, or this repository.
