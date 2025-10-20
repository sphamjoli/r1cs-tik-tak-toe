#!/usr/bin/env bash
set -euo pipefail

VERSION="v2.2.2"
BASE="https://github.com/iden3/circom/releases/download/${VERSION}/"
mkdir -p bin

case "$(uname -s)" in
  Linux*)   FILE="circom-linux-amd64" ;;
  Darwin*)  FILE="circom-macos-amd64" ;;
  MINGW*|MSYS*|CYGWIN*) FILE="circom-windows-amd64.exe" ;;
  *) echo "Unsupported OS: $(uname -s)" && exit 1 ;;
esac

echo "Downloading $FILE ..."
curl -fsSL -o "bin/${FILE}" "${BASE}${FILE}"

if [[ "$FILE" == *.exe ]]; then
  mv "bin/${FILE}" "bin/circom.exe"
  chmod +x "bin/circom.exe"
  cat > bin/circom <<'SH'
#!/usr/bin/env bash
exec "$(dirname "$0")/circom.exe" "$@"
SH
  chmod +x bin/circom
else
  mv "bin/${FILE}" "bin/circom"
  chmod +x bin/circom
fi

echo "Circom 2.2.2 installed in ./bin"
bin/circom --version || true
