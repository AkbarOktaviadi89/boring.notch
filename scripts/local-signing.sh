#!/bin/bash
# Signs local builds with one self-signed certificate that stays the same from build to build.
#
# Ad-hoc signed builds get a new identity each time, so macOS forgets the Camera, Automation and
# other permissions after every rebuild. With this certificate the app's designated requirement is
# "identifier + certificate leaf", which stays put, and permissions survive rebuilds.
#
# The certificate and its key live only on this Mac, in their own keychain (not the login keychain).
#
#   scripts/local-signing.sh setup        create the keychain and certificate (once)
#   scripts/local-signing.sh sign <app>   re-sign a built app with it (skipped when not set up)

set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/BoringNotchLocalSigning.keychain-db"
NAME="Boring Notch Local Signing"

identity_hash() {
	security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | awk -v name="\"$NAME\"" 'index($0, name) { print $2; exit }'
}

in_search_list() {
	security list-keychains -d user | grep -qF "$KEYCHAIN"
}

setup() {
	if [ -f "$KEYCHAIN" ] && [ -n "$(identity_hash)" ]; then
		echo "Signing identity already set up: $(identity_hash)"
	else
		work=$(mktemp -d)
		trap 'rm -rf "$work"' EXIT
		cat > "$work/cert.cnf" <<-EOF
			[req]
			distinguished_name = dn
			x509_extensions = ext
			prompt = no
			[dn]
			CN = $NAME
			[ext]
			basicConstraints = critical,CA:false
			keyUsage = critical,digitalSignature
			extendedKeyUsage = critical,codeSigning
		EOF
		openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" \
			-days 7300 -config "$work/cert.cnf" 2>/dev/null
		# macOS only reads PKCS#12 files made with the older algorithms
		openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" \
			-passout pass:import -name "$NAME" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

		[ -f "$KEYCHAIN" ] || security create-keychain -p "" "$KEYCHAIN"
		security set-keychain-settings "$KEYCHAIN"
		security unlock-keychain -p "" "$KEYCHAIN"
		security import "$work/id.p12" -k "$KEYCHAIN" -P import -T /usr/bin/codesign >/dev/null
		# Lets codesign use the key without a password prompt
		security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null
		echo "Created signing identity $(identity_hash)"
	fi

	# codesign only finds identities in keychains on the search list
	if ! in_search_list; then
		existing=()
		while IFS= read -r line; do
			line="${line#"${line%%[![:space:]]*}"}"
			existing+=("${line//\"/}")
		done < <(security list-keychains -d user)
		security list-keychains -d user -s "${existing[@]}" "$KEYCHAIN"
	fi
}

sign() {
	app="$1"
	hash=$(identity_hash)
	if [ -z "$hash" ] || ! in_search_list; then
		echo "No local signing identity; the build stays ad hoc (run: scripts/local-signing.sh setup)"
		return 0
	fi
	security unlock-keychain -p "" "$KEYCHAIN"

	# Inside out: the XPC helper first, then the app. Each keeps the entitlements Xcode gave it.
	for code in "$app/Contents/XPCServices/"*.xpc "$app"; do
		[ -e "$code" ] || continue
		codesign --force --sign "$hash" --keychain "$KEYCHAIN" \
			--preserve-metadata=identifier,entitlements,flags "$code"
	done
	codesign --verify --deep --strict "$app"
	echo "Signed with the local identity: $(codesign -d -r- "$app" 2>&1 | grep designated)"
}

case "${1:-}" in
	setup) setup ;;
	sign) sign "$2" ;;
	*) echo "usage: $0 setup | sign <app>" >&2; exit 2 ;;
esac
