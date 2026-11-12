#!/usr/bin/env python3
"""Kiểm tra mọi dịch vụ trong services/ theo quy tắc chung. CI chạy file này trên mỗi PR.

Mục đích: dịch vụ MỚI được thêm tự do, nhưng không được phép phá dịch vụ CŨ
(trùng cổng, ăn hết RAM, đụng volume/network của người khác, chiếm quyền root máy chủ).
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICES = ROOT / "services"
SHARED_NET = "shared"

errors: list[str] = []
used_ports: dict[tuple[str, str], list[str]] = {}  # (cổng host, giao thức) -> ["thư-mục/service", ...]


def err(where: str, msg: str) -> None:
    errors.append(f"[{where}] {msg}")


def load(svc_dir: Path):
    """Dùng chính docker compose để chuẩn hoá file (giải short syntax, đường dẫn tuyệt đối...)."""
    r = subprocess.run(
        ["docker", "compose", "-p", f"svc-{svc_dir.name}",
         "-f", str(svc_dir / "compose.yaml"), "config", "--format", "json"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        err(svc_dir.name, "compose.yaml không hợp lệ:\n    " + r.stderr.strip())
        return None
    return json.loads(r.stdout)


def inside(path: str, base: Path) -> bool:
    return Path(path).resolve().is_relative_to(base.resolve())


for d in sorted(p for p in SERVICES.iterdir() if p.is_dir() and not p.name.startswith("_")):
    name = d.name
    if not (d / "compose.yaml").is_file():
        err(name, "thiếu file compose.yaml")
        continue
    # Secrets chỉ được commit ở dạng đã mã hoá (secrets.env.age)
    for f in sorted(d.rglob("*")):
        if f.is_file() and f.name.endswith(".env"):
            err(name, f"'{f.relative_to(ROOT)}' trông như secrets CHƯA mã hoá — xoá khỏi git, mã hoá thành secrets.env.age")
    enc = d / "secrets.env.age"
    if enc.is_file():
        head = enc.read_bytes()[:40]
        if not (head.startswith(b"age-encryption.org/v1") or head.startswith(b"-----BEGIN AGE ENCRYPTED FILE-----")):
            err(name, "secrets.env.age không phải file đã mã hoá bằng age")

    cfg = load(d)
    if cfg is None:
        continue

    # --- Network / volume cấp project ---
    for key, net in (cfg.get("networks") or {}).items():
        if net.get("external") and net.get("name") != SHARED_NET:
            err(name, f"network ngoài chỉ được dùng '{SHARED_NET}', không được dùng '{net.get('name')}'")
    for key, vol in (cfg.get("volumes") or {}).items():
        if vol.get("external"):
            err(name, f"volume '{key}' là external — có thể đang đụng dữ liệu của dịch vụ khác")

    # --- Từng container ---
    for sname, s in (cfg.get("services") or {}).items():
        where = f"{name}/{sname}"

        if sname != name and not sname.startswith(name + "-"):
            err(where, f"tên service phải là '{name}' hoặc '{name}-...' (tránh trùng tên DNS trên mạng chung)")
        if "container_name" in s:
            err(where, "không đặt container_name (dễ trùng giữa các dịch vụ)")

        # Những thứ cho container quyền gần như root trên VM
        if s.get("privileged"):
            err(where, "không được privileged: true")
        for key in ("network_mode", "pid", "ipc"):
            if str(s.get(key, "")).startswith("host"):
                err(where, f"không được {key}: host")
        if s.get("cap_add") or s.get("devices"):
            err(where, "cap_add / devices cần Phúc duyệt riêng")

        # Image phải có tag cố định để lần deploy sau không tự đổi phiên bản
        if "build" not in s:
            img = s.get("image", "")
            last = img.rsplit("/", 1)[-1]
            if "@" not in img and (":" not in last or last.endswith(":latest")):
                err(where, f"image '{img}' phải ghi rõ tag, không dùng :latest")
        else:
            ctx = s["build"].get("context", "")
            if ctx and not inside(ctx, d):
                err(where, "build context phải nằm trong thư mục dịch vụ")

        # Giới hạn RAM để một dịch vụ không làm sập cả máy
        limits = ((s.get("deploy") or {}).get("resources") or {}).get("limits") or {}
        if not (s.get("mem_limit") or limits.get("memory")):
            err(where, "thiếu mem_limit (vd: mem_limit: 512m)")

        # Volume: bind mount chỉ cho file cấu hình trong thư mục mình, read-only
        for v in s.get("volumes") or []:
            if v.get("type") == "bind":
                if not inside(v["source"], d):
                    err(where, f"bind mount '{v['source']}' nằm ngoài thư mục dịch vụ (kể cả docker.sock)")
                elif not v.get("read_only"):
                    err(where, f"bind mount tới '{v['target']}' phải thêm :ro — dữ liệu ghi thì dùng named volume")

        # Cổng host không được trùng với bất kỳ dịch vụ nào khác
        for p in s.get("ports") or []:
            pub = p.get("published")
            if not pub:
                continue
            used_ports.setdefault((str(pub), p.get("protocol", "tcp")), []).append(where)

for (port, proto), users in used_ports.items():
    if len(users) > 1:
        err(f"cổng {port}/{proto}", "bị trùng giữa: " + ", ".join(users))

if errors:
    print("❌ Có lỗi:\n" + "\n".join("  " + e for e in errors))
    sys.exit(1)

print("✅ Hợp lệ. Cổng đang dùng:")
for (port, proto), users in sorted(used_ports.items(), key=lambda x: int(x[0][0].split("-")[0])):
    print(f"  {port}/{proto:<4} {users[0]}")
