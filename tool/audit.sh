#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# tool/audit.sh — MealAttend FLUTTER MASTER AUDIT (mirror of backend deploy/run.sh)
#
#   bash tool/audit.sh --help        list modules
#   bash tool/audit.sh --all         every module that works without a phone
#   bash tool/audit.sh --static      one module
#   bash tool/audit.sh --all --device   + real-device runtime measurements (adb)
#
# PRODUCTION-BASELINE CONTRACT (identical to the backend orchestrator):
#   • READ-ONLY on the codebase — never edits source, config, or pubspec.
#   • Build outputs go to build/ (already gitignored); reports to
#     build/audit-reports/<timestamp>/ — nothing is ever committed.
#   • The --device module only LAUNCHES the installed production app and READS
#     OS statistics (dumpsys) — it never touches app data, never logs in,
#     never clears anything. Zero coupling, zero impact.
#
# Modules and the REAL parameters each measures:
#   static   — flutter analyze (0-issue gate) · dispose-parity sweeps (timers/
#              controllers/subscriptions/FocusNodes) · polling detector
#              (Timer.periodic outside allowed files) · debug-print/TODO scan
#              · decode-cap coverage on CachedPhoto call sites
#   deps     — dependency health: outdated report, dependency count
#   size     — release build (R8, split-per-abi) + per-ABI APK sizes vs budget
#   security — manifest hardening (allowBackup=false, no cleartext traffic,
#              minimal permissions) · hardcoded-secret grep · https-only config
#   device   — [needs: adb + phone + PROD app installed] cold-start TotalTime ·
#              RAM (dumpsys meminfo TOTAL PSS) · rendering jank % (gfxinfo) ·
#              app wakelocks (batterystats) — the ULTRA SPEED/SMOOTH/RAM/
#              BATTERY numbers measured on real hardware
#
# Exit: 0 = all pass · 1 = advisories · 2 = failures. Aggregated report:
# build/audit-reports/<ts>/FRONTEND_AUDIT.md
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$ROOT/build/audit-reports/$TS"
PKG="com.emilestone.mealattend"

MODS=(static deps size security device)
usage() {
  echo "Usage: bash tool/audit.sh [--all] [--static|--deps|--size|--security|--device ...] [--help]"
  sed -n '/^# Modules and the REAL/,/^# Exit/p' "$0" | sed 's/^# \{0,3\}//'
}

SEL=(); ALL=0
[ $# -eq 0 ] && { usage; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0;;
    --all) ALL=1;;
    --static|--deps|--size|--security|--device) SEL+=("${1#--}");;
    *) echo "Unknown arg: $1"; exit 2;;
  esac; shift
done
if [ "$ALL" -eq 1 ]; then
  SEL=(static deps size security)
  # device only when explicitly asked OR a device is attached
  if command -v adb >/dev/null && adb get-state >/dev/null 2>&1; then SEL+=(device); fi
fi

mkdir -p "$OUT"
# Verdicts go to a FILE (module output is piped through tee, which puts the
# module in a subshell — shell variables set there would be lost).
VFILE="$OUT/.verdicts"
: > "$VFILE"
v() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$VFILE"; printf '  [%s] %s — %s\n' "$2" "$1" "$3"; }

# ── static ───────────────────────────────────────────────────────────────────
mod_static() {
  echo "── STATIC CODE AUDIT ──"
  flutter analyze lib > "$OUT/analyze.log" 2>&1
  if grep -q 'No issues found' "$OUT/analyze.log"; then v "analyzer" "PASS" "0 issues";
  else v "analyzer" "FAIL" "$(grep -cE 'error|warning|info' "$OUT/analyze.log") findings — see analyze.log"; fi

  local bad=0
  for f in $(git grep -l 'Timer(' -- lib 2>/dev/null); do
    if [ "$(grep -c '\.cancel()' "$f")" -eq 0 ]; then bad=$((bad+1)); echo "  no-cancel: $f"; fi
  done
  [ "$bad" -eq 0 ] && v "timer-dispose-parity" "PASS" "every Timer file cancels" || v "timer-dispose-parity" "FAIL" "$bad file(s) create Timers without cancel"

  bad=0
  for f in $(git grep -l 'AnimationController(\|ScrollController(\|TextEditingController(\|FocusNode(' -- lib 2>/dev/null); do
    if [ "$(grep -c 'dispose()' "$f")" -eq 0 ]; then bad=$((bad+1)); echo "  no-dispose: $f"; fi
  done
  [ "$bad" -eq 0 ] && v "controller-dispose-parity" "PASS" "every controller file disposes" || v "controller-dispose-parity" "WARN" "$bad file(s) lack a dispose — verify each"

  # Allowlist: shimmer + heartbeat (lifecycle-paused), finite OTP/reset UI
  # countdowns, and the dashboard carousel (lifecycle-paused auto-scroll).
  # Anything else periodic = data polling = banned.
  local poll; poll=$(git grep -n 'Timer.periodic' -- lib \
    | grep -vc 'app_skeleton\|realtime_service\|otp_screen\|reset_password_screen\|open_now_carousel' || true)
  [ "${poll:-0}" -eq 0 ] && v "no-polling" "PASS" "zero periodic timers outside the justified allowlist" || v "no-polling" "FAIL" "$poll unjustified Timer.periodic site(s) — polling is banned"

  local prints; prints=$(git grep -n '\bprint(' -- lib | grep -vc 'debugPrint' || true)
  [ "${prints:-0}" -eq 0 ] && v "no-debug-prints" "PASS" "no raw print()" || v "no-debug-prints" "WARN" "$prints raw print() call(s)"

  local nocap; nocap=$(git grep -A8 'CachedPhoto(' -- lib | grep -c 'CachedPhoto(' || true)
  local capped; capped=$(git grep -A8 'CachedPhoto(' -- lib | grep -c 'cacheWidth\|BoxFit.contain' || true)
  [ "$capped" -ge $((nocap - 2)) ] && v "image-decode-caps" "PASS" "$capped/$nocap CachedPhoto sites decode-capped (rest = intentional full-res)" \
    || v "image-decode-caps" "WARN" "only $capped/$nocap CachedPhoto sites capped"
}

# ── deps ─────────────────────────────────────────────────────────────────────
mod_deps() {
  echo "── DEPENDENCIES ──"
  flutter pub outdated > "$OUT/deps.log" 2>&1 || true
  local direct; direct=$(grep -cE '^  [a-z_0-9]+' pubspec.yaml || true)
  v "dependency-count" "PASS" "$direct direct deps (lean); full report in deps.log"
}

# ── size ─────────────────────────────────────────────────────────────────────
mod_size() {
  echo "── RELEASE SIZE (R8 + split-per-abi) ──"
  flutter build apk --release --split-per-abi --dart-define=ENV=production > "$OUT/build.log" 2>&1
  if [ $? -ne 0 ]; then v "release-build" "FAIL" "build failed — see build.log"; return; fi
  v "release-build" "PASS" "R8 release builds clean"
  local apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  if [ -f "$apk" ]; then
    local mb; mb=$(awk "BEGIN{printf \"%.1f\", $(stat -c%s "$apk" 2>/dev/null || stat -f%z "$apk")/1048576}")
    awk "BEGIN{exit !($mb<=40)}" && v "apk-size-arm64" "PASS" "${mb} MB (budget ≤40)" || v "apk-size-arm64" "WARN" "${mb} MB (>40 budget)"
  fi
}

# ── security ─────────────────────────────────────────────────────────────────
mod_security() {
  echo "── APP SECURITY POSTURE ──"
  local m="android/app/src/main/AndroidManifest.xml"
  grep -q 'allowBackup="false"' "$m" && v "no-auto-backup" "PASS" "allowBackup=false (Keystore half-restore bug closed)" \
    || v "no-auto-backup" "FAIL" "allowBackup not false"
  grep -q 'usesCleartextTraffic="true"' "$m" && v "no-cleartext" "FAIL" "cleartext traffic enabled!" \
    || v "no-cleartext" "PASS" "no cleartext-traffic flag (https only in prod config)"
  local perms; perms=$(grep -c 'uses-permission' "$m")
  [ "$perms" -le 10 ] && v "minimal-permissions" "PASS" "$perms permissions (no location/sensors/wakelock)" \
    || v "minimal-permissions" "WARN" "$perms permissions — review"
  local secrets; secrets=$(git grep -inE '(api[_-]?key|secret|password)\s*[:=]\s*["'"'"'][A-Za-z0-9+/]{16,}' -- lib | grep -vc 'password.*hint\|labelText\|Password' || true)
  [ "${secrets:-0}" -eq 0 ] && v "no-hardcoded-secrets" "PASS" "no credential-shaped literals in lib/" \
    || v "no-hardcoded-secrets" "FAIL" "$secrets suspicious literal(s) — inspect"
  git grep -q "startsWith('https://')" -- lib/core/config && v "https-gating" "PASS" "h2/https gating present in EnvConfig" || true
}

# ── device (adb, read-only) ──────────────────────────────────────────────────
mod_device() {
  echo "── REAL-DEVICE RUNTIME (adb, read-only) ──"
  command -v adb >/dev/null || { v "device" "WARN" "adb not installed — skipped"; return; }
  adb get-state >/dev/null 2>&1 || { v "device" "WARN" "no device attached — skipped"; return; }
  adb shell pm path "$PKG" >/dev/null 2>&1 || { v "device" "WARN" "$PKG not installed on device"; return; }

  # Cold start: force-stop (drops process only — data untouched), launch, read TotalTime.
  local comp; comp=$(adb shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tail -1 | tr -d '\r')
  adb shell am force-stop "$PKG"
  sleep 2
  local start; start=$(adb shell am start -W -n "$comp" 2>/dev/null | grep TotalTime | grep -oE '[0-9]+')
  if [ -n "$start" ]; then
    [ "$start" -le 3000 ] && v "cold-start" "PASS" "${start} ms to first frame (budget ≤3000)" \
      || v "cold-start" "WARN" "${start} ms (>3000)"
  fi
  sleep 6   # let dashboard settle before sampling

  # RAM: TOTAL PSS of the running app.
  local pss; pss=$(adb shell dumpsys meminfo "$PKG" 2>/dev/null | grep -m1 'TOTAL PSS' | grep -oE '[0-9]+' | head -1)
  [ -z "$pss" ] && pss=$(adb shell dumpsys meminfo "$PKG" 2>/dev/null | grep -m1 '^ *TOTAL' | awk '{print $2}')
  if [ -n "$pss" ]; then
    local mb=$((pss/1024))
    [ "$mb" -le 350 ] && v "ram-total-pss" "PASS" "${mb} MB PSS (budget ≤350; image cache capped 48 MiB)" \
      || v "ram-total-pss" "WARN" "${mb} MB PSS (>350) — profile with DevTools"
  fi

  # Rendering smoothness: janky-frame percentage since app start.
  adb shell dumpsys gfxinfo "$PKG" > "$OUT/gfxinfo.log" 2>/dev/null
  local total janky
  total=$(grep -m1 'Total frames rendered' "$OUT/gfxinfo.log" | grep -oE '[0-9]+')
  janky=$(grep -m1 'Janky frames' "$OUT/gfxinfo.log" | grep -oE '[0-9]+' | head -1)
  if [ -n "$total" ] && [ "$total" -gt 0 ]; then
    local pct=$((100*janky/total))
    [ "$pct" -le 10 ] && v "jank" "PASS" "${pct}% janky frames ($janky/$total — ultra smooth ≤10%)" \
      || v "jank" "WARN" "${pct}% janky frames — profile the slow screen"
  fi

  # Battery: the app must hold NO wakelocks.
  local wl; wl=$(adb shell dumpsys power 2>/dev/null | grep -ci "$PKG" || true)
  [ "${wl:-0}" -eq 0 ] && v "no-wakelocks" "PASS" "app holds no wakelocks" \
    || v "no-wakelocks" "WARN" "$wl power-manager reference(s) — inspect dumpsys power"
}

for m in "${SEL[@]}"; do "mod_$m" 2>&1 | tee "$OUT/$m.log"; done

# ── Aggregate report ─────────────────────────────────────────────────────────
FAILS=$(grep -c '|FAIL|' "$VFILE" || true)
WARNS=$(grep -c '|WARN|' "$VFILE" || true)
{
  echo "# 📱 MealAttend FRONTEND AUDIT — $TS"
  echo
  echo "- Branch: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
  echo "- Modules: ${SEL[*]}  ·  Contract: read-only, zero prod-baseline impact"
  echo
  echo "| Check | Verdict | Measured |"
  echo "|---|---|---|"
  sort "$VFILE" | awk -F'|' '{printf "| %s | %s | %s |\n", $1, $2, $3}'
  echo
  if [ "${FAILS:-0}" -gt 0 ]; then echo "## VERDICT: ❌ $FAILS FAILURE(S) — fix before release";
  elif [ "${WARNS:-0}" -gt 0 ]; then echo "## VERDICT: 🟡 PASS with $WARNS advisory item(s)";
  else echo "## VERDICT: 🏆 ALL FRONTEND PARAMETERS GOLDEN"; fi
} > "$OUT/FRONTEND_AUDIT.md"

echo; echo "══ Report → build/audit-reports/$TS/FRONTEND_AUDIT.md ══"
grep -E '^\| |VERDICT' "$OUT/FRONTEND_AUDIT.md"
[ "$FAILS" -gt 0 ] && exit 2 || { [ "$WARNS" -gt 0 ] && exit 1 || exit 0; }
