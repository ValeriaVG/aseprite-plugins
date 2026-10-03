# Aseprite binary used by the test recipe. Override with:
#   just test aseprite=/path/to/aseprite
aseprite := "/Applications/Aseprite.app/Contents/MacOS/aseprite"

# List available recipes.
default:
    @just --list

# Build an installable .aseprite-extension from a plugin folder, into
# dist/<name>-<version>.aseprite-extension (name/version come from the
# plugin's package.json). An Aseprite extension is just a ZIP with
# package.json at the archive root, so this zips the folder *contents*,
# excluding dev-only files like test/.
package plugin="isometrify":
    #!/usr/bin/env sh
    set -eu
    manifest="{{plugin}}/package.json"

    [ -f "$manifest" ] || { echo "error: $manifest not found" >&2; exit 1; }

    # Grab the first "name"/"version" match (top-level fields come before
    # any nested objects in these manifests).
    name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)
    version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)

    if [ -z "$name" ] || [ -z "$version" ]; then
        echo "error: could not read name/version from $manifest" >&2
        exit 1
    fi

    mkdir -p dist
    out="dist/${name}-${version}.aseprite-extension"
    rm -f "$out"

    (cd "{{plugin}}" && zip -rX "../$out" . \
        -x 'test/*' -x '.DS_Store' -x '*.DS_Store' -x '__MACOSX*' -x '.*')

    echo "built $out"

# Run the plugin's headless test suite without the GUI.
test:
    cd isometrify/test && "{{aseprite}}" -b -script test_isometrify.lua
