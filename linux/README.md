# 🐧 Antigravity Orbit (Linux Edition)

<p align="center">
  <img src="ui/assets/AppIcon1024.png" width="140" height="140" alt="Antigravity Orbit Logo" style="border-radius: 20%;" />
  <br>
  <em>Ứng dụng khay hệ thống (System Tray) tối ưu, tự động giám sát quota và xoay vòng tài khoản Google AI Pro / Ultra cho Antigravity IDE, agy CLI & Antigravity Desktop App trên Linux</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Linux%20(Ubuntu%20%7C%20Debian%20%7C%20Fedora%20%7C%20Arch)-blue?logo=linux" alt="Platform" />
  <img src="https://img.shields.io/badge/Framework-Tauri%20v2-orange?logo=tauri" alt="Tauri v2" />
  <img src="https://img.shields.io/badge/Backend-Rust-red?logo=rust" alt="Rust" />
  <img src="https://img.shields.io/badge/Formats-AppImage%20%7C%20deb%20%7C%20rpm%20%7C%20AUR-green" alt="Formats" />
</p>

---

## 📖 Giới thiệu

**Antigravity Orbit (Linux Edition)** được phát triển dựa trên **Tauri v2** và **Rust**, mang trọn vẹn toàn bộ trải nghiệm từ bản macOS sang các bản phân phối Linux phổ biến:
* **Ubuntu / Debian / Linux Mint / Pop!_OS**
* **Fedora / RHEL / CentOS Stream**
* **Arch Linux / Manjaro / EndeavourOS**
* **Mọi bản Linux khác thông qua gói Universal AppImage**

---

## 🌟 Tính năng nổi bật

1. **System Tray Thông minh (StatusNotifierItem / Ayatana AppIndicator)**:
   * Hiển thị phần trăm quota và chấm màu trạng thái (`70% 🟢`, `25% 🟡`, `8% 🔴`).
   * Tooltip chi tiết khi rê chuột: Email, model AI đang active, hạn mức 5 giờ và hạn mức tuần.
   * Menu phân cấp 1-click chuyển đổi tài khoản, xoay vòng ngay lập tức (`Ctrl+R`), làm mới quota.
2. **Đồng bộ 3 chiều (3-Way Target Sync)**:
   * **Antigravity IDE**: Cập nhật tức thời `~/.gemini/antigravity/antigravity_state.pbtxt`, `google_accounts.json`, `oauth_creds.json`.
   * **agy CLI & Go**: Tự động lưu mật mã vào **Freedesktop Secret Service** (Keyring) qua D-Bus (`service: gemini`, `account: antigravity`), giúp CLI nhận token mới không bị gián đoạn.
   * **Antigravity Desktop App**: Đồng bộ phiên làm việc.
3. **Cơ chế Xoay vòng Round-Robin & Tự động Làm mới Token (Proactive Refresh)**:
   * Tự động quét và chuyển tài khoản khi quota $\le$ ngưỡng thiết lập.
   * Tự động làm mới access token khi sắp hết hạn ($\le 120$s) hoặc gặp mã lỗi 401.
4. **Giao diện Cài đặt (Settings Dashboard)**:
   * Quản lý danh sách tài khoản: Import 1-click từ IDE, Đăng nhập tài khoản mới bằng Google OAuth (loopback server), Xóa tài khoản.
   * Cấu hình ngưỡng xoay vòng và chu kỳ quét.
   * Hỗ trợ đa ngôn ngữ (10 ngôn ngữ).
   * Khởi động cùng hệ thống thông qua chuẩn **XDG Autostart** (`~/.config/autostart`).

---

## 📦 Hướng dẫn cài đặt theo từng Distro

### 1. Ubuntu / Debian / Linux Mint (.deb)
```bash
# Cài đặt thư viện phụ thuộc (nếu chưa có)
sudo apt update
sudo apt install -y libayatana-appindicator3-1 libsecret-1-0 libwebkit2gtk-4.1-0

# Cài đặt gói .deb
sudo dpkg -i antigravity-orbit_1.0.0_amd64.deb
```
> *Lưu ý trên GNOME*: Để hiển thị tray icon trên GNOME (mặc định trên Ubuntu/Debian), hãy đảm bảo extension **AppIndicator and KStatusNotifierItem Support** đã được bật:
> ```bash
> sudo apt install gnome-shell-extension-appindicator
> ```

---

### 2. Fedora / RHEL (.rpm)
```bash
# Cài đặt thư viện phụ thuộc
sudo dnf install -y libayatana-appindicator-gtk3 libsecret webkit2gtk4.1

# Cài đặt gói .rpm
sudo dnf install antigravity-orbit-1.0.0.x86_64.rpm
```

---

### 3. Arch Linux / Manjaro (AUR & PKGBUILD)
```bash
# Cài đặt qua AUR helper (yay / paru)
yay -S antigravity-orbit-bin

# Hoặc build thủ công từ PKGBUILD
cd packaging/arch
makepkg -si
```

---

### 4. Mọi Distro Linux (Universal AppImage)
```bash
chmod +x Antigravity-Orbit-1.0.0.AppImage
./Antigravity-Orbit-1.0.0.AppImage
```

---

## 🛠 Hướng dẫn Build từ Mã nguồn

### Yêu cầu:
* Rust & Cargo: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
* Node.js / Bun: `curl -fsSL https://bun.sh/install | bash`
* Các gói dev hệ thống:
  * **Ubuntu/Debian**: `sudo apt install libayatana-appindicator3-dev libwebkit2gtk-4.1-dev libsecret-1-dev build-essential`
  * **Fedora**: `sudo dnf install libayatana-appindicator-gtk3-devel webkit2gtk4.1-devel libsecret-devel`
  * **Arch**: `sudo pacman -S libayatana-appindicator webkit2gtk-4.1 libsecret base-devel`

### Lệnh build:
```bash
# 1. Build binary phát triển & đóng gói tarball
./build.sh

# 2. Cài đặt trực tiếp vào ~/.local/bin/ và tạo shortcut menu
./build.sh install

# 3. Đóng gói đầy đủ các định dạng (.deb, .rpm, .AppImage)
./build.sh bundle
```

