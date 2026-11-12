#!/usr/bin/env bash
# Chạy trên VM (do stack-sync gọi). Dựng mọi dịch vụ trong services/,
# gỡ dịch vụ đã bị xoá khỏi repo. Mỗi dịch vụ là một compose project riêng
# nên một dịch vụ lỗi không chặn các dịch vụ khác.
set -uo pipefail
umask 077                                   # file secrets giải mã ra: chỉ root đọc được

REPO_DIR="${REPO_DIR:-/opt/stack/repo}"
SECRETS_DIR="${SECRETS_DIR:-/opt/stack/secrets}"
AGE_KEY="${AGE_KEY:-/opt/stack/age.key}"
NETWORK="shared"
PREFIX="svc-"

cd "$REPO_DIR" || exit 1
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK"

failed=0
declare -A wanted=()

for dir in services/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue            # bỏ qua _template
  [[ -f "$dir/compose.yaml" ]] || continue
  project="$PREFIX$name"
  wanted["$project"]=1
  echo "==> $name"

  # Secrets đã mã hoá trong repo -> giải mã ra /opt/stack/secrets/<tên>.env
  if [[ -f "$dir/secrets.env.age" ]]; then
    tmp="$SECRETS_DIR/.$name.env.tmp"
    if age -d -i "$AGE_KEY" -o "$tmp" "$dir/secrets.env.age"; then
      sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' "$tmp"   # bỏ BOM/CRLF nếu soạn trên Windows
      mv "$tmp" "$SECRETS_DIR/$name.env"
    else
      rm -f "$tmp"
      echo "!! $name: không giải mã được secrets.env.age — bỏ qua dịch vụ này" >&2
      failed=1
      continue
    fi
  fi

  if ! docker compose -p "$project" -f "$dir/compose.yaml" up -d --build --remove-orphans; then
    echo "!! $name lỗi — bỏ qua, các dịch vụ khác vẫn chạy" >&2
    failed=1
  fi
done

# Gỡ project svc-* không còn thư mục trong repo.
# Dùng "down" KHÔNG có -v: volume (dữ liệu) vẫn được giữ lại.
while read -r project; do
  [[ -z "$project" || -n "${wanted[$project]:-}" ]] && continue
  echo "==> gỡ $project (đã bị xoá khỏi repo, dữ liệu vẫn giữ)"
  docker compose -p "$project" down --remove-orphans || failed=1
done < <(docker compose ls -a --format json | jq -r '.[].Name' | grep "^$PREFIX" || true)

exit "$failed"
