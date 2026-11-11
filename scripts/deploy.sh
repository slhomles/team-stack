#!/usr/bin/env bash
# Chạy trên VM (do stack-sync gọi). Dựng mọi dịch vụ trong services/,
# gỡ dịch vụ đã bị xoá khỏi repo. Mỗi dịch vụ là một compose project riêng
# nên một dịch vụ lỗi không chặn các dịch vụ khác.
set -uo pipefail

REPO_DIR="${REPO_DIR:-/opt/stack/repo}"
NETWORK="shared"
PREFIX="svc-"

cd "$REPO_DIR" || exit 1
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK"

failed=0
declare -A wanted=()

for dir in services/*/; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue            # bỏ qua _template
  [[ -f "$dir/compose.yaml" ]] || continue
  project="$PREFIX$name"
  wanted["$project"]=1
  echo "==> $name"
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
