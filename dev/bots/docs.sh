#!/bin/bash
set -e

function deploy {
  local total_tries="$1"
  local remaining_tries=$(($total_tries - 1))
  shift
  while [[ "$remaining_tries" > 0 ]]; do
    (cd "$FLUTTER_ROOT/dev/docs" && firebase deploy --token "$FIREBASE_TOKEN" --project "$@") && break
    remaining_tries=$(($remaining_tries - 1))
    echo "Error: Unable to deploy documentation to Firebase. Retrying in five seconds... ($remaining_tries tries left)"
    sleep 5
  done

  [[ "$remaining_tries" == 0 ]] && {
    echo "Command still failed after $total_tries tries: '$@'"
    return 1
  }
  return 0
}

function script_location() {
  local script_location="${BASH_SOURCE[0]}"
  # Resolve symlinks
  while [[ -h "$script_location" ]]; do
    DIR="$(cd -P "$( dirname "$script_location")" >/dev/null && pwd)"
    script_location="$(readlink "$script_location")"
    [[ "$script_location" != /* ]] && script_location="$DIR/$script_location"
  done
  echo "$(cd -P "$(dirname "$script_location")" >/dev/null && pwd)"
}

# So that users can run this script from anywhere and it will work as expected.
SCRIPT_LOCATION="$(script_location)"
# Sets the Flutter root to be "$(script_location)/../..": This script assumes
# that it resides two directory levels down from the root, so if that changes,
# then this line will need to as well.
FLUTTER_ROOT="$(dirname "$(dirname "$SCRIPT_LOCATION")")"

echo "Running docs.sh"

if [[ ! -d "$FLUTTER_ROOT" || ! -f "$FLUTTER_ROOT/bin/flutter" ]]; then
  echo "Unable to locate the Flutter installation (using FLUTTER_ROOT: $FLUTTER_ROOT)"
  exit 1
fi

FLUTTER_BIN="$FLUTTER_ROOT/bin"
DART_BIN="$FLUTTER_ROOT/bin/cache/dart-sdk/bin"
FLUTTER="$FLUTTER_BIN/flutter"
DART="$DART_BIN/dart"
PUB="$DART_BIN/pub"
export PATH="$FLUTTER_BIN:$DART_BIN:$PATH"

# Make sure dart is installed by invoking flutter to download it.
"$FLUTTER" --version

# If the pub cache directory exists in the root, then use that.
FLUTTER_PUB_CACHE="$FLUTTER_ROOT/.pub-cache"
if [[ -d "$FLUTTER_PUB_CACHE" ]]; then
  # This has to be exported, because pub interprets setting it
  # to the empty string in the same way as setting it to ".".
  export PUB_CACHE="${PUB_CACHE:-"$FLUTTER_PUB_CACHE"}"
fi

# Install and activate dartdoc.
"$PUB" global activate dartdoc 0.21.1

# This script generates a unified doc set, and creates
# a custom index.html, placing everything into dev/docs/doc.
(cd "$FLUTTER_ROOT/dev/tools" && "$FLUTTER" packages get)
(cd "$FLUTTER_ROOT/dev/tools" && "$PUB" get)
(cd "$FLUTTER_ROOT" && "$DART" "$FLUTTER_ROOT/dev/tools/dartdoc.dart")
(cd "$FLUTTER_ROOT" && "$DART" "$FLUTTER_ROOT/dev/tools/java_and_objc_doc.dart")

# Ensure google webmaster tools can verify our site.
cp "$FLUTTER_ROOT/dev/docs/google2ed1af765c529f57.html" "$FLUTTER_ROOT/dev/docs/doc"

# Upload new API docs when running on Cirrus
if [[ -n "$CIRRUS_CI" && -z "$CIRRUS_PR" ]]; then
  echo "This is not a pull request; considering whether to upload docs... (branch=$CIRRUS_BRANCH)"
  if [[ "$CIRRUS_BRANCH" == "master" || "$CIRRUS_BRANCH" == "beta" ]]; then
    if [[ "$CIRRUS_BRANCH" == "master" ]]; then
      echo "Updating master docs: https://master-docs-flutter-io.firebaseapp.com/"
      # Disable search indexing on the master staging site so searches get only
      # the beta site.
      echo -e "User-agent: *\nDisallow: /" > "$FLUTTER_ROOT/dev/docs/doc/robots.txt"
      export FIREBASE_TOKEN="$FIREBASE_MASTER_TOKEN"
      deploy 5 master-docs-flutter-io
    fi

    if [[ "$CIRRUS_BRANCH" == "beta" ]]; then
      echo "Updating beta docs: https://docs.flutter.io/"
      export FIREBASE_TOKEN="$FIREBASE_PUBLIC_TOKEN"
      deploy 5 docs-flutter-io
    fi
  fi
fi

