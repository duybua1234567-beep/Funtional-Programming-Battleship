# Battleship Haskell — WebSocket LAN (chạy bằng Cabal, không cần Stack)

Bản này giữ nguyên mã nguồn Haskell/WebSocket. Do Windows trên một số máy chặn `stack.exe`, hãy dùng `cabal` thay cho `stack`.

## 1. Kiểm tra công cụ

Mở PowerShell tại thư mục dự án (thư mục có `battleship.cabal`) và chạy:

```powershell
ghc --version
cabal --version
```

Nếu `cabal --version` không chạy, cần cài Cabal từ nguồn Haskell chính thức hoặc nhờ quản trị viên cho phép công cụ.

## 2. Cài/cập nhật danh sách thư viện

```powershell
cabal update
```

## 3. Biên dịch

```powershell
cabal build all
```

Lần đầu có thể mất thời gian vì Cabal tải các thư viện phụ thuộc. Nếu lệnh báo lỗi, hãy gửi toàn bộ thông báo lỗi.

## 4. Chạy web server

Chạy từ thư mục gốc dự án, nơi có thư mục `web`:

```powershell
cabal run battleship -- web
```

Mở trình duyệt máy A tại:

`http://localhost:8080`

Để tìm IPv4 của máy A, mở PowerShell khác và chạy:

```powershell
ipconfig
```

Trên máy B cùng mạng LAN, mở:

`http://IP-MAY-A:8080`

Thay `IP-MAY-A` bằng địa chỉ IPv4 thật của máy A. Hai người cùng nhấn **Chơi qua LAN** để ghép trận. Nếu Windows Firewall hỏi, chỉ cho phép trên mạng riêng (Private) mà bạn tin cậy.

## 5. Các chế độ console cũ

```powershell
cabal run battleship
cabal run battleship -- server
cabal run battleship -- client localhost
```

## Lưu ý

- Không cần chạy `stack build` hay `stack run` trong hướng dẫn này.
- `stack.exe` bị Windows Application Control chặn là vấn đề chính sách thực thi, không phải lỗi cú pháp Haskell. Dùng Cabal là đường chạy thay thế, không phải cách vượt qua chính sách bảo mật; nếu Cabal cũng bị chặn, hãy làm việc với quản trị viên.
- Mã nguồn WebSocket trong bản này chưa được xác nhận biên dịch thành công trên máy của bạn. `cabal build all` là bước kiểm tra thực tế đầu tiên.
