#!/usr/bin/env bash
# Cài vào /usr/local/bin/stack-sync (nằm NGOÀI repo, vì repo bị reset trong lúc chạy).
# Kéo nhánh main; chỉ deploy khi có commit mới (hoặc FORCE=1).
set -euo pipefail
cd /opt/stack/repo

git fetch --quiet origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" || "${FORCE:-0}" == 1 ]]; then
  echo "Có thay đổi: $(git rev-parse --short HEAD) -> $(git rev-parse --short origin/main)"
  git reset --hard origin/main
  exec ./scripts/deploy.sh
fi
