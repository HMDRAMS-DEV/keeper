#!/bin/zsh
# Ships the version in project.yml: builds the disk image, notarizes it, signs it for Sparkle, publishes the GitHub release, adds it to the appcast, and deploys the site.
#
#     scripts/release.sh "What changed, in a sentence or two."
#
# Bump CFBundleShortVersionString and CFBundleVersion in project.yml and commit first. Sparkle
# compares CFBundleVersion, so it must go up every release.
#
# One-time setup on a new Mac:
#   - The Sparkle signing key must be in the login keychain. Export it from the old Mac with
#     `generate_keys -x key.txt` and import it with `generate_keys -f key.txt`.
#   - The HMDFV Inc. Developer ID Application certificate must be in the login keychain, and a
#     notarytool profile named "ramihmd-notary" must exist:
#     `xcrun notarytool store-credentials ramihmd-notary --apple-id <id> --team-id 8Z6WRF99H5`
set -euo pipefail

app=Keeper
repo=HMDRAMS-DEV/keeper
site=https://keeper.ramihmd.com
notary=ramihmd-notary

cd "$(dirname "$0")/.."
notes="${1:?Usage: scripts/release.sh \"release notes\"}"
version=$(awk -F'"' '/CFBundleShortVersionString/{print $2; exit}' project.yml)
build=$(awk -F'"' '/CFBundleVersion/{print $2; exit}' project.yml)
tag="v$version"
dmg="site/downloads/$app.dmg"

[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first."; exit 1; }
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then echo "$tag is already released."; exit 1; fi
if grep -q "<sparkle:version>$build</sparkle:version>" site/appcast.xml; then echo "Build $build is already in the appcast. Bump CFBundleVersion."; exit 1; fi

xcodegen generate >/dev/null
scripts/make-dmg.sh "$dmg"

# Stapling fails unless Apple accepted the image, which stops the release there.
xcrun notarytool submit "$dmg" --keychain-profile "$notary" --wait
xcrun stapler staple "$dmg"

# Sign after stapling, since stapling changes the file.
products=$(xcodebuild -project "$app.xcodeproj" -scheme "$app" -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILD_DIR /{print $2; exit}')
sparkle="${products%/Build/Products}/SourcePackages/artifacts/sparkle/Sparkle/bin"
# generate_keys created the key, so it can read it without a keychain prompt. The copy lives only
# as long as the signing does.
key=$(mktemp -d)
trap 'rm -rf "$key"' EXIT
"$sparkle/generate_keys" -x "$key/private" >/dev/null
signature=$("$sparkle/sign_update" --ed-key-file "$key/private" "$dmg")
rm -rf "$key"

gh release create "$tag" "$dmg" -R "$repo" --target main --title "$app $version" --notes "$notes"

# Newest first, right after the marker. The download is the GitHub asset, which never changes.
item="    <item>
      <title>$app $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$notes</p>]]></description>
      <enclosure url=\"https://github.com/$repo/releases/download/$tag/$app.dmg\" type=\"application/octet-stream\" $signature/>
    </item>"
ITEM="$item" perl -0pi -e 's/(    <!-- releases -->\n)/$1$ENV{ITEM}\n/' site/appcast.xml
grep -q "<sparkle:version>$build</sparkle:version>" site/appcast.xml || { echo "Couldn't add the release to site/appcast.xml."; exit 1; }

git add site/appcast.xml
git commit -q -m "Release $app $version"
git push -q origin main
(cd site && vercel deploy --prod -y --scope almaknowsfood >/dev/null)

sleep 5
curl -fsS "$site/appcast.xml?release=$build" | grep -q "<sparkle:version>$build</sparkle:version>" \
  && echo "Released $app $version. $site/appcast.xml lists build $build." \
  || echo "Deployed, but $site/appcast.xml doesn't list build $build yet. Check it."
