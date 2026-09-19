#!/bin/sh

set -eu

case "$(uname -s)" in
    Linux|Darwin) ;;
    *)
        echo "This check is only for non-Windows hosts." >&2
        exit 1
        ;;
esac

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/swift-windowsappsdk-check.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

cd "$repo_root"

"${CC:-clang}" \
    -c Sources/CWinAppSDK/delayloadhelper.c \
    -o "$work_dir/delayloadhelper.o"

"${CC:-clang}" \
    -c Sources/CWinAppSDK/modulehandle.c \
    -o "$work_dir/modulehandle.o"

swiftc \
    -parse-as-library \
    -emit-module \
    -module-name WinAppSDK \
    Sources/WinAppSDK/*.swift \
    Sources/WinAppSDK/Generated/*.swift \
    -emit-module-path "$work_dir/WinAppSDK.swiftmodule"

printf '%s\n' \
    'import CWinAppSDK' \
    'import WinAppSDK' \
    > "$work_dir/ImportCheck.swift"

swiftc \
    -typecheck \
    -I "$work_dir" \
    -I Sources/CWinAppSDK/include \
    "$work_dir/ImportCheck.swift"
