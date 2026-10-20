#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Exercise the real configuration preambles, never the build/sign/install steps.
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts"
if [[ -f scripts/signing-config.sh ]]; then
  cp scripts/signing-config.sh "$fixture/scripts/"
fi
failures=0
checks=0

check_config() {
  local label="$1" expected="$2"
  shift 2
  local actual
  actual="$(env -i PATH="$PATH" "$@" bash "$fixture/scripts/probe.sh")"
  # The notarization script launches build-app in a child shell. Its resolved
  # configuration must be identical, including file-provided fallback values.
  expected="$expected"$'\n'"$expected"
  checks=$((checks + 1))
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $script / $label: expected [$expected], got [$actual]" >&2
    failures=$((failures + 1))
  fi
}

for script in build-app.sh notarize.sh; do
  # Stop before either script's first operational command or required-value check.
  awk '/^swift build / || /^: / { exit } { print }' "scripts/$script" >"$fixture/scripts/probe.sh"
  cat >>"$fixture/scripts/probe.sh" <<'PROBE'
printf '%s|%s|%s' "${SIGNING_IDENTITY:-}" "${TEAM_ID:-}" "${NOTARY_PROFILE:-}"
printf '\n'
bash -c 'printf "%s|%s|%s" "${SIGNING_IDENTITY:-}" "${TEAM_ID:-}" "${NOTARY_PROFILE:-}"'
PROBE
  cat >"$fixture/scripts/signing.env" <<'CONFIG'
SIGNING_IDENTITY="Developer ID Application: Fixture"
TEAM_ID=FILETEAM01
NOTARY_PROFILE="$(printf '%s' fixture-profile)"
CONFIG

  check_config identity-only 'environment identity|FILETEAM01|fixture-profile' SIGNING_IDENTITY='environment identity'
  check_config team-only 'Developer ID Application: Fixture|ENVTEAM001|fixture-profile' TEAM_ID=ENVTEAM001
  check_config profile-only 'Developer ID Application: Fixture|FILETEAM01|environment profile' NOTARY_PROFILE='environment profile'
  check_config no-overrides 'Developer ID Application: Fixture|FILETEAM01|fixture-profile'
  check_config all-overrides 'environment identity|ENVTEAM001|environment profile' SIGNING_IDENTITY='environment identity' TEAM_ID=ENVTEAM001 NOTARY_PROFILE='environment profile'
  check_config empty-overrides 'Developer ID Application: Fixture|FILETEAM01|fixture-profile' SIGNING_IDENTITY= TEAM_ID= NOTARY_PROFILE=

  rm "$fixture/scripts/signing.env"
  check_config absent-config '||'
  check_config absent-config-overrides 'environment identity|ENVTEAM001|environment profile' SIGNING_IDENTITY='environment identity' TEAM_ID=ENVTEAM001 NOTARY_PROFILE='environment profile'
done

if [[ "$failures" != 0 ]]; then
  echo "$failures of $checks signing configuration checks failed." >&2
  exit 1
fi
echo "Passed $checks signing configuration checks."
