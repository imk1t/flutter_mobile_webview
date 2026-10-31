#!/usr/bin/env bash
# Print true only when the exact version is present in valid pub.dev metadata.
set -euo pipefail

package="${1:?Usage: pub-dev-version-published.sh PACKAGE VERSION}"
version="${2:?Usage: pub-dev-version-published.sh PACKAGE VERSION}"
response="$(mktemp)"
trap 'rm -f "$response"' EXIT

if ! status="$(curl --silent --show-error --location \
  --retry 3 --retry-max-time 90 --connect-timeout 10 --max-time 30 \
  --header 'Accept: application/vnd.pub.v2+json' \
  --output "$response" --write-out '%{http_code}' \
  "https://pub.dev/api/packages/$package")"; then
  echo "::error::Could not query pub.dev for $package" >&2
  exit 1
fi

case "$status" in
  200)
    if ! jq -se --arg package "$package" '
      length == 1 and (.[0] |
        type == "object" and .name == $package and
        (.versions | type == "array") and
        all(.versions[]; type == "object" and (.version | type == "string")))
    ' "$response" > /dev/null; then
      echo "::error::Invalid pub.dev package metadata for $package" >&2
      exit 1
    fi
    jq -r --arg version "$version" \
      'any(.versions[]; .version == $version)' "$response"
    ;;
  404)
    # A missing package has no published versions; use the normal publish path.
    echo false
    ;;
  *)
    echo "::error::Unexpected pub.dev HTTP status $status for $package" >&2
    exit 1
    ;;
esac
