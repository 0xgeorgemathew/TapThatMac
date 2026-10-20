#!/bin/bash
# Tap That Mac installer.
#
#   curl -fsSL https://raw.githubusercontent.com/0xgeorgemathew/tapthatmac/main/install.sh | bash
#
# Checks that this Mac has the motion sensor, downloads the newest release (betas included),
# verifies its checksum, removes the download quarantine (the app is signed but not notarized),
# installs Tap That Mac.app to /Applications and opens it.
#
# Options:
#   bash -s -- --version v0.1.0-beta.1   install a specific release
#   bash -s -- --force                   install even if no motion sensor is found
#   bash -s -- --uninstall               remove the app (keeps your settings and calibration)
#   bash -s -- --uninstall --purge       also remove settings, calibration and permission grants
#
# Written for the bash 3.2 that ships with macOS.
set -euo pipefail

REPO="0xgeorgemathew/tapthatmac"
APP_NAME="Tap That Mac.app"
PROCESS="TapThatMac"
BUNDLE_ID="com.tapthatmac.app"
HELPER_LABEL="com.tapthatmac.sensor"
DATA_DIR="$HOME/Library/Application Support/Tap That Mac"
LEGACY_APP="TapThatX.app"

version=""
uninstall=0
purge=0
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --uninstall) uninstall=1; shift ;;
    --purge) purge=1; shift ;;
    --force) force=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

# ── Look ──────────────────────────────────────────────────────────────────────────────────────
# Drawn from the Live graph: cyan is motion, violet is a tap still being confirmed, gold is the
# threshold a tap has to cross, and rose means something went wrong. Pipes, CI and NO_COLOR get
# plain lines.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then fancy=1; else fancy=0; fi

RESET="" BOLD="" DIM="" CYAN="" VIOLET="" GOLD="" ROSE=""
if [ "$fancy" = 1 ]; then
  RESET=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m'
  case "${COLORTERM:-}" in
    truecolor|24bit)
      CYAN=$'\033[38;2;127;211;247m' VIOLET=$'\033[38;2;185;166;255m'
      GOLD=$'\033[38;2;233;185;73m' ROSE=$'\033[38;2;255;111;134m' ;;
    *) # Terminal.app before macOS 26 has no 24-bit color; these are the nearest 256-color cells.
      CYAN=$'\033[38;5;117m' VIOLET=$'\033[38;5;147m' GOLD=$'\033[38;5;179m' ROSE=$'\033[38;5;204m' ;;
  esac
fi
GHOST="$RESET$DIM"

cols=""
[ "$fancy" = 1 ] && { cols=$(stty size 2>/dev/null </dev/tty | awk '{print $2}') || true; }
[ "${cols:-0}" -gt 0 ] 2>/dev/null || cols=${COLUMNS:-80}

# The mark: a motion trace with two taps rising through the gold threshold.
mark() {
  local subtitle=$1
  [ "$fancy" = 1 ] || { printf '\nTap That Mac · %s\n\n' "$subtitle"; return; }
  printf '\n'
  printf '  %s        ▅       ▅%s\n' "$CYAN" "$RESET"
  printf '  %s        █       █%s\n' "$CYAN" "$RESET"
  printf '  %s┄┄┄┄┄┄┄┄%s█%s┄┄┄┄┄┄┄%s█%s┄┄┄┄┄┄┄┄%s    %sTap That Mac%s\n' \
    "$GOLD" "$CYAN" "$GOLD" "$CYAN" "$GOLD" "$RESET" "$BOLD" "$RESET"
  printf '  %s▁▂▁▁▂▃▅▆%s█%s▅▂▁▂▃▆▇%s█%s▄▂▁▁▂▁▁▂%s    %s%s%s\n\n' \
    "$GHOST$CYAN" "$RESET$CYAN" "$GHOST$CYAN" "$RESET$CYAN" "$GHOST$CYAN" "$RESET" "$DIM" "$subtitle" "$RESET"
}

# ── Steps ─────────────────────────────────────────────────────────────────────────────────────
# One line per step: a cell, what happened, and a dim detail. While a step runs, its cell is a
# violet tap impulse, rising and settling like a pending tap; when it ends, the line is
# rewritten in place.

FRAMES=(▁ ▃ ▇ █ ▆ ▄ ▂ ▁ ▁ ▁ ▁ ▁)
active=""  # label of the step on screen, if any
worker=""  # background job the current step is waiting on

# Columns: two spaces, the cell, two spaces, a 32-wide label, then the detail.
LABEL=32
line() { # color glyph label detail
  printf '  %s%s%s  %-*s %s%s%s' "$1" "$2" "$RESET" "$LABEL" "$3" "$DIM" "$4" "$RESET"
}

# Trims a plain detail to the window so finished lines don't wrap; very narrow windows drop it.
fit() {
  local room=$((cols - LABEL - 6)) text=$1
  if [ "$room" -lt 8 ]; then return; fi
  [ "${#text}" -le "$room" ] || text="${text:0:$((room - 1))}…"
  printf '%s' "$text"
}

begin() { # label
  active=$1
  [ "$fancy" = 1 ] && line "$VIOLET" "${FRAMES[0]}" "$active" ""
  return 0
}

# Waits for a background job, animating the active step. An optional function supplies a live
# detail (the download meter). Returns the job's exit status.
await() { # pid [detail-fn]
  local pid=$1 fn=${2:-} i=0 detail=""
  worker=$pid
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$fancy" = 1 ]; then
      # The line is redrawn with \r, so it must never wrap: narrow windows get no live detail.
      [ -n "$fn" ] && [ "$cols" -ge $((LABEL + 22)) ] && detail=$($fn)
      printf '\r\033[2K'; line "$VIOLET" "${FRAMES[$((i % ${#FRAMES[@]}))]}" "$active" "$detail"
    fi
    i=$((i + 1))
    sleep 0.07
  done
  worker=""
  wait "$pid"
}

finish() { # color glyph label detail
  if [ "$fancy" = 1 ]; then
    printf '\r\033[2K'; line "$1" "$2" "$3" "$(fit "$4")"; printf '\n'
  else
    printf '  %s %-*s %s\n' "$2" "$LABEL" "$3" "$4"
  fi
  active=""
}
done_() { finish "$CYAN" "✓" "$1" "${2:-}"; }
warn() { finish "$GOLD" "!" "$1" "${2:-}"; }

# Ends the install: what went wrong, then how to fix it.
fail() { # headline hint
  if [ "$fancy" = 1 ]; then
    [ -n "$active" ] && printf '\r\033[2K'
    printf '  %s✕%s  %s%s%s\n' "$ROSE" "$RESET" "$BOLD" "$1" "$RESET" >&2
    [ -n "${2:-}" ] && printf '     %s%s%s\n' "$DIM" "$2" "$RESET" >&2
    printf '\n' >&2
  else
    printf '  ✕ %s\n' "$1" >&2
    [ -n "${2:-}" ] && printf '    %s\n' "$2" >&2
  fi
  active=""
  exit 1
}

tmp=""
cleanup() {
  [ -n "$worker" ] && kill "$worker" 2>/dev/null
  if [ "$fancy" = 1 ]; then
    [ -n "$active" ] && printf '\n'
    printf '\033[?25h'
  fi
  [ -n "$tmp" ] && rm -rf "$tmp"
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM
[ "$fancy" = 1 ] && printf '\033[?25l'

# ── Helpers ───────────────────────────────────────────────────────────────────────────────────

# curl has no timeouts by default, so a stalled connection would hang the install with no
# output. Slow connects are retried; small requests get a hard cap; the download aborts if it
# stays under 1 KB/s for 30 seconds.
fetch() { curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 1 "$@"; }
download() { curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 30 --retry 3 --retry-delay 1 "$@"; }

megabytes() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1000000 }'; }
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

quit_app() {
  pgrep -x "$PROCESS" >/dev/null || return 0
  # Ask politely in the background: the Apple event can sit behind an Automation prompt.
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
  local asker=$!
  for _ in 1 2 3 4 5; do pgrep -x "$PROCESS" >/dev/null || break; sleep 1; done
  kill "$asker" >/dev/null 2>&1 || true
  pkill -x "$PROCESS" >/dev/null 2>&1 || true
}

installed_app() {
  for dir in /Applications "$HOME/Applications"; do
    [ -d "$dir/$APP_NAME" ] && { echo "$dir/$APP_NAME"; return 0; }
  done
  return 1
}

# The same match the app uses: an Apple SPU HID device on vendor page 0xFF00, usage 3.
has_motion_sensor() {
  ioreg -c AppleSPUHIDDevice -r -d 1 2>/dev/null | awk '
    /\+-o/ { page = ""; usage = "" }
    /"PrimaryUsagePage" = / { page = $NF }
    /"PrimaryUsage" = / { usage = $NF }
    page == "65280" && usage == "3" { found = 1 }
    END { exit found ? 0 : 1 }'
}

helper_registered() { launchctl print "system/$HELPER_LABEL" >/dev/null 2>&1; }

# ── Uninstall ─────────────────────────────────────────────────────────────────────────────────

if [ "$uninstall" = 1 ]; then
  mark "Uninstalling"
  if pgrep -x "$PROCESS" >/dev/null; then
    begin "Quitting Tap That Mac"
    quit_app & await $! || true
    done_ "Quit Tap That Mac"
  fi
  if helper_registered; then
    warn "The sensor helper is registered" "remove it in System Settings › General › Login Items"
  fi
  if app=$(installed_app); then
    rm -rf "$app"
    done_ "Removed the app" "$(tilde "$app")"
  else
    done_ "No app to remove" "not in Applications"
  fi
  if [ "$purge" = 1 ]; then
    rm -rf "$DATA_DIR"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    done_ "Removed settings and calibration" "$(tilde "$DATA_DIR")"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
    done_ "Reset permission grants" "Accessibility · Input Monitoring"
  fi
  printf '\n  %sTap That Mac is uninstalled.%s\n' "$BOLD" "$RESET"
  if [ "$purge" != 1 ]; then
    printf '  %sYour settings and calibration are still in %s.%s\n' "$DIM" "$(tilde "$DATA_DIR")" "$RESET"
    printf '  %sTo remove them too, run the uninstall again with --purge.%s\n' "$DIM" "$RESET"
  fi
  printf '\n'
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────────────────────

mark "Double-tap your Mac."

begin "Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || fail "Tap That Mac runs on macOS" "This computer runs $(uname -s)."
[ "$(uname -m)" = "arm64" ] || fail "Tap That Mac needs a Mac with Apple silicon" "This Mac has an Intel processor."
os=$(sw_vers -productVersion)
major=${os%%.*}
[ "$major" -ge 14 ] || fail "Tap That Mac needs macOS 14 or later" "This Mac runs macOS $os. Update it in System Settings › General › Software Update."
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple silicon")
done_ "Checked this Mac" "macOS $os · $chip"

begin "Looking for the motion sensor"
if has_motion_sensor; then
  done_ "Found the motion sensor" "built-in accelerometer"
elif [ "$force" = 1 ]; then
  warn "No motion sensor found" "installing anyway (--force)"
else
  fail "This Mac has no motion sensor Tap That Mac can read" \
    "It needs a MacBook with Apple silicon. To install anyway, add --force: … | bash -s -- --force"
fi

tmp=$(mktemp -d)

if [ -n "$version" ]; then
  begin "Finding Tap That Mac $version"
  api="https://api.github.com/repos/$REPO/releases/tags/$version"
else
  begin "Finding the latest release"
  api="https://api.github.com/repos/$REPO/releases?per_page=1"
fi
fetch -H "Accept: application/vnd.github+json" "$api" -o "$tmp/release.json" 2>/dev/null & await $! \
  || fail "Couldn't reach GitHub" "Check your connection and run the installer again in a minute."
# Each asset lists its size just before its download URL; pair them and keep the app zip.
size="" url=""
read -r size url < <(grep -oE '"(size|browser_download_url)": *("[^"]*"|[0-9]+)' "$tmp/release.json" \
  | sed -E 's/^"[a-z_]+": *"?//; s/"$//' | paste - - | grep -E '/TapThatMac-[^/]*\.zip$' | head -1) || true
[ -n "$url" ] || fail "Couldn't find a Tap That Mac release" "github.com/$REPO has no release${version:+ named $version} with an app to download."
tag=$(grep -oE '"tag_name": *"[^"]*"' "$tmp/release.json" | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
published=$(grep -oE '"published_at": *"[^"]*"' "$tmp/release.json" | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
released=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$published" "+%b %e" 2>/dev/null | tr -s ' ') || true
done_ "Found Tap That Mac ${tag#v}" "${released:+released $released · }$(megabytes "${size:-0}")"

# The live detail while downloading: a trace that fills in, its newest cell a violet tap.
progress() {
  local got total=${size:-0} width lit i bar=""
  got=$(stat -f%z "$tmp/TapThatMac.zip" 2>/dev/null || echo 0)
  [ "$got" -gt 0 ] || { printf 'Connecting to GitHub…'; return; }
  [ "$total" -gt 0 ] 2>/dev/null || { megabytes "$got"; return; }
  width=$((cols - LABEL - 22)); [ "$width" -gt 24 ] && width=24
  if [ "$width" -ge 8 ]; then
    lit=$((got * width / total)); [ "$lit" -gt "$width" ] && lit=$width
    # Braces matter here: bash 3.2 reads a multibyte character right after $NAME as part of it.
    for ((i = 0; i < width; i++)); do
      if [ "$i" -lt $((lit - 1)) ]; then bar+="${RESET}${CYAN}▅"; elif [ "$i" -eq $((lit - 1)) ]; then bar+="${RESET}${VIOLET}█"; else bar+="${GHOST}▁"; fi
    done
    bar+="$RESET$DIM  "
  fi
  printf '%s%s of %s' "$bar" "$(megabytes "$got" | cut -d' ' -f1)" "$(megabytes "$total")"
}
begin "Downloading"
# One curl for both files: the checksum reuses the zip's connection instead of opening its own.
# Its exit status reflects whichever transfer failed last, so judge the files instead.
download "$url" -o "$tmp/TapThatMac.zip" "$url.sha256" -o "$tmp/TapThatMac.zip.sha256" 2>/dev/null & await $! progress || true
got=$(stat -f%z "$tmp/TapThatMac.zip" 2>/dev/null || echo 0)
if [ "$got" -eq 0 ] || { [ -n "$size" ] && [ "$got" -ne "$size" ]; }; then
  fail "The download stalled" "Check your connection and run the installer again. Nothing was changed."
fi
done_ "Downloaded" "$(megabytes "$got")"

begin "Verifying the download"
if grep -qE '^[0-9a-f]{64}' "$tmp/TapThatMac.zip.sha256" 2>/dev/null; then
  expected=$(awk '{print $1}' "$tmp/TapThatMac.zip.sha256")
  actual=$(shasum -a 256 "$tmp/TapThatMac.zip" | awk '{print $1}')
  [ "$expected" = "$actual" ] || fail "The download doesn't match its checksum" \
    "Nothing was installed. Run the installer again; if this keeps happening, open an issue at github.com/$REPO."
  verified=1
else
  verified=0
fi
ditto -x -k "$tmp/TapThatMac.zip" "$tmp/unzipped"
[ -d "$tmp/unzipped/$APP_NAME" ] || fail "The download doesn't contain $APP_NAME" "Open an issue at github.com/$REPO."
# A release may need a newer macOS than the installer does; stop before replacing anything.
needs=$(plutil -extract LSMinimumSystemVersion raw "$tmp/unzipped/$APP_NAME/Contents/Info.plist" 2>/dev/null || echo 0)
[ "$major" -ge "${needs%%.*}" ] || fail "Tap That Mac ${tag#v} needs macOS ${needs%%.*} or later" \
  "This Mac runs macOS $os. Nothing was changed."
if [ "$verified" = 1 ]; then
  done_ "Verified the download" "SHA-256 matches"
else
  warn "Couldn't verify the download" "no checksum published; installing anyway"
fi

# Not notarized: clear the quarantine flag so Gatekeeper doesn't block the first launch.
xattr -dr com.apple.quarantine "$tmp/unzipped/$APP_NAME" 2>/dev/null || true

# Permission grants follow the app's signature and location, so keep it in one place.
dest_dir=/Applications
[ -w "$dest_dir" ] || { dest_dir="$HOME/Applications"; mkdir -p "$dest_dir"; }
app="$dest_dir/$APP_NAME"
begin "Installing"
quit_app & await $! || true
rm -rf "$app"
ditto "$tmp/unzipped/$APP_NAME" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
done_ "Installed" "$(tilde "$app")"

begin "Opening Tap That Mac"
open "$app" 2>/dev/null || fail "Tap That Mac is installed but didn't open" "Open it from $(tilde "$dest_dir") in Finder."
done_ "Opened Tap That Mac"

# What's left is the user's: three approvals and one choice, in this order.
step() { # number text
  if [ "$fancy" = 1 ]; then printf '  %s%s%s  %s\n' "$CYAN" "$1" "$RESET" "$2"; else printf '  %s. %s\n' "$1" "$2"; fi
}
printf '\n  %sTap That Mac is open. Three things left:%s\n\n' "$BOLD" "$RESET"
step 1 "Allow Accessibility, so a double-tap can run an action."
step 2 "Allow Input Monitoring, so taps while you type are ignored."
step 3 "In Actions, choose what a double-tap does. Lock Mac is a good first pick."
printf '\n  %sThe Live view opens the right System Settings page for each permission.%s\n' "$DIM" "$RESET"
printf '  %sThe command ring is pre-alpha. Try it safely with Preview command ring.%s\n' "$DIM" "$RESET"
for dir in /Applications "$HOME/Applications"; do
  if [ -d "$dir/$LEGACY_APP" ]; then
    if [ "$fancy" = 1 ]; then printf '\n  %s!%s  ' "$GOLD" "$RESET"; else printf '\n  ! '; fi
    printf 'The old %s is still in %s. Your settings have moved over;\n' "${LEGACY_APP%.app}" "$(tilde "$dir")"
    printf '     you can drag it to the Trash.\n'
    break
  fi
done
printf '\n'
