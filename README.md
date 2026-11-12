# team-stack

Một VM Google Cloud chạy Docker cho cả nhóm. **Repo này là nguồn sự thật duy nhất**: VM tự kéo nhánh `main` mỗi 2 phút và deploy. Không ai (kể cả Phúc) sửa container trực tiếp trên VM.

```
services/
  _template/compose.yaml   ← mẫu để copy
  mariadb/compose.yaml     ← mỗi dịch vụ = 1 thư mục = 1 compose project riêng
scripts/validate.py        ← CI kiểm tra quy tắc
scripts/deploy.sh          ← VM chạy sau mỗi lần main thay đổi
vm/                        ← cài đặt VM một lần
```

## Thêm dịch vụ mới — không cần duyệt

1. Tạo nhánh mới.
2. Copy `services/_template` thành `services/<ten-dich-vu>` và sửa `compose.yaml` (tên service = tên thư mục).
3. Nếu cần mật khẩu/token: mã hoá thành `services/<ten-dich-vu>/secrets.env.age` theo mục "Secrets" cuối README. **Không** commit file `.env` gốc.
4. Mở Pull Request. Khi check `validate` xanh thì tự bấm Merge.
5. Khoảng 2 phút sau dịch vụ chạy trên VM.

Các dịch vụ cùng mạng `shared` gọi nhau bằng tên, ví dụ từ dịch vụ của bạn kết nối MariaDB với host `mariadb`, cổng `3306`.

## Sửa / xoá dịch vụ đã có — cần Phúc duyệt

Vẫn mở Pull Request như trên. Vì thư mục đó có tên trong `.github/CODEOWNERS`, GitHub sẽ chặn nút Merge cho tới khi Phúc approve.

Xoá thư mục dịch vụ = gỡ container trên VM; **dữ liệu (named volume) vẫn được giữ lại**.

## Quy tắc (CI tự kiểm tra)

| Quy tắc | Vì sao |
|---|---|
| Tên service là `<thư mục>` hoặc `<thư mục>-xxx`, không đặt `container_name` | Trên mạng chung, tên service là tên DNS. Hai dịch vụ cùng tên `db` thì không biết gọi vào đâu. |
| Cổng host không trùng với dịch vụ khác | Trùng cổng thì dịch vụ deploy sau sẽ không lên được, hoặc chiếm cổng của dịch vụ cũ. |
| Bắt buộc `mem_limit` | Một dịch vụ rò rỉ RAM có thể khiến cả VM bị OOM, kéo sập MariaDB. |
| Image ghi rõ tag, không `:latest` | `:latest` có thể đổi phiên bản mà không ai sửa gì, rất khó tìm lỗi. |
| Dữ liệu dùng named volume; bind mount chỉ cho file cấu hình trong thư mục mình và phải `:ro` | Named volume được Docker đặt tên theo project (`svc-<tên>_...`) nên không thể đụng dữ liệu của nhau. |
| Không `external` volume, không network ngoài nào khác `shared` | Đây là cách duy nhất để chạm vào dữ liệu/mạng của dịch vụ khác. |
| Không `privileged`, `network_mode/pid/ipc: host`, `cap_add`, `devices`, không mount `docker.sock` | Mỗi thứ này đều cho container quyền gần như root trên VM, tức là vượt qua mọi quy tắc duyệt. |

Cần ngoại lệ? Mở PR sửa `scripts/validate.py` — PR đó sẽ cần Phúc duyệt.

## Kết nối tới dịch vụ

VM không mở cổng ra Internet. Cài [Tailscale](https://tailscale.com), đăng nhập vào tailnet Phúc mời, rồi dùng IP `100.x.x.x` của VM:

```
mysql -h <ip-tailscale-cua-vm> -P 3306 -u <user> -p
```

---

## Cài đặt một lần (Phúc)

**1. VM trên Google Cloud.** Compute Engine, region `asia-southeast1` (Singapore, gần Việt Nam), máy `e2-medium` để bắt đầu (nâng sau nếu thiếu RAM), Ubuntu 24.04, ổ 30 GB. Không thêm firewall rule nào.

**2. Repo GitHub.** Push repo này lên dạng private, thay `@slhomles` trong `.github/CODEOWNERS`, mời 2 bạn làm collaborator.

**3. Ruleset cho `main`** (Settings → Rules → Rulesets → New branch ruleset, target: default branch):

- Bật *Restrict deletions* và *Block force pushes*.
- Bật *Require a pull request before merging*: Required approvals = **0**, tick **Require review from Code Owners**, tick **Dismiss stale pull request approvals when new commits are pushed** (nếu không, người khác có thể đẩy thêm thay đổi sau khi đã được duyệt).
- Bật *Require status checks to pass*, thêm check `validate` (cần chạy workflow ít nhất một lần thì mới chọn được).
- Bypass list: Repository admin, để Phúc tự merge thay đổi của mình.

Ruleset và CODEOWNERS trên repo private cần GitHub Pro; sinh viên được miễn phí qua GitHub Student Developer Pack.

Sau khi cài, **thử ngay**: dùng tài khoản của một bạn mở PR sửa `services/mariadb/compose.yaml` → phải bị chặn; mở PR thêm `services/test/` → phải merge được.

**4. Cài VM:**

```
gcloud compute scp vm/setup-vm.sh <ten-vm>:~ --zone <zone>
gcloud compute ssh <ten-vm> --zone <zone>
sudo bash setup-vm.sh git@github.com:<user>/<repo>.git
```

Script sẽ in ra một deploy key — thêm vào repo ở Settings → Deploy keys, **không** tick write access.

**5. Secrets và lần deploy đầu:**

```
echo 'MARIADB_ROOT_PASSWORD=...' | sudo tee /opt/stack/secrets/mariadb.env
sudo chmod 600 /opt/stack/secrets/*.env
sudo FORCE=1 stack-sync
journalctl -u stack-sync -f       # xem log deploy
```

**6. Tailscale trên VM:** `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`, rồi mời 2 bạn vào tailnet hoặc share máy VM cho họ.

## "Khoá" một dịch vụ mới

CODEOWNERS chỉ hiểu đường dẫn, không biết dịch vụ nào "đã có" hay "mới". Vì vậy dịch vụ mới merge xong vẫn tự do sửa cho tới khi Phúc thêm một dòng vào `.github/CODEOWNERS`:

```
/services/<ten-dich-vu>/   @slhomles
```

Coi khoảng thời gian trước khi khoá là giai đoạn để người tạo chỉnh cho dịch vụ chạy ổn.

## Secrets (mật khẩu, token) cho dịch vụ

Mật khẩu được commit vào repo ở dạng **đã mã hoá** bằng [age](https://github.com/FiloSottile/age). File `age-recipients.txt` chứa public key của VM và của Phúc: ai cũng mã hoá được, nhưng chỉ VM (lúc deploy) và Phúc (bản dự phòng) giải mã được.

**Linux** (cài: `sudo apt install age`):

```bash
nano /tmp/ten-dich-vu.env      # soạn NGOÀI repo, mỗi dòng một biến: KEY=gia-tri
age -R age-recipients.txt -o services/ten-dich-vu/secrets.env.age /tmp/ten-dich-vu.env
rm /tmp/ten-dich-vu.env        # sau khi đã lưu bản gốc vào trình quản lý mật khẩu của bạn
```

**Windows PowerShell** (cài: `winget install FiloSottile.age`):

```powershell
notepad $env:TEMP\ten-dich-vu.env
age -R age-recipients.txt -o services\ten-dich-vu\secrets.env.age $env:TEMP\ten-dich-vu.env
Remove-Item $env:TEMP\ten-dich-vu.env
```

Trong `compose.yaml` của dịch vụ, khai báo `env_file: /opt/stack/secrets/ten-dich-vu.env`. Khi deploy, VM tự giải mã `secrets.env.age` ra đúng đường dẫn đó.

- **Không ai giải mã lại được bản trong repo, kể cả người tạo.** Hãy tự giữ bản gốc.
- Đổi mật khẩu: mã hoá file mới, ghi đè `secrets.env.age`, mở PR. Dịch vụ đã khoá thì cần Phúc duyệt.
- CI chặn mọi file `*.env` chưa mã hoá trong `services/`.
