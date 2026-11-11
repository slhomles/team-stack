#!/usr/bin/env bash
# Chạy MỘT LẦN trên VM (Ubuntu 24.04) bằng: sudo bash setup-vm.sh git@github.com:<user>/<repo>.git
set -euo pipefail
REPO_URL="${1:?Cách dùng: sudo bash setup-vm.sh git@github.com:<user>/<repo>.git}"

# 1. Docker + công cụ
apt-get update && apt-get install -y git jq curl
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh

# Giới hạn log container — không có cái này, log sẽ âm thầm làm đầy ổ đĩa
cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "20m", "max-file": "3" } }
JSON
systemctl restart docker

# 2. Thư mục secrets: chỉ root đọc được, nằm ngoài repo
mkdir -p /opt/stack/secrets && chmod 700 /opt/stack/secrets

# 3. Deploy key chỉ-đọc để VM kéo repo
if [[ ! -f /opt/stack/deploy_key ]]; then
  ssh-keygen -t ed25519 -N "" -f /opt/stack/deploy_key -C "team-stack-vm"
  echo
  echo ">>> Thêm public key dưới đây vào GitHub: repo > Settings > Deploy keys (KHÔNG tick write access):"
  cat /opt/stack/deploy_key.pub
  read -rp ">>> Thêm xong thì nhấn Enter..."
fi
mkdir -p /root/.ssh && ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null

if [[ ! -d /opt/stack/repo/.git ]]; then
  GIT_SSH_COMMAND="ssh -i /opt/stack/deploy_key -o IdentitiesOnly=yes" \
    git clone "$REPO_URL" /opt/stack/repo
  git -C /opt/stack/repo config core.sshCommand "ssh -i /opt/stack/deploy_key -o IdentitiesOnly=yes"
fi

# 4. Mạng dùng chung + timer đồng bộ
docker network inspect shared >/dev/null 2>&1 || docker network create shared
install -m 755 /opt/stack/repo/vm/stack-sync.sh /usr/local/bin/stack-sync
cp /opt/stack/repo/vm/stack-sync.service /opt/stack/repo/vm/stack-sync.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now stack-sync.timer

echo
echo "Xong. Việc còn lại:"
echo "  - Tạo secrets, vd: echo 'MARIADB_ROOT_PASSWORD=...' > /opt/stack/secrets/mariadb.env && chmod 600 /opt/stack/secrets/*.env"
echo "  - Deploy ngay: sudo FORCE=1 stack-sync    |  Xem log: journalctl -u stack-sync -f"
echo "  - Cài Tailscale: curl -fsSL https://tailscale.com/install.sh | sh && tailscale up"
