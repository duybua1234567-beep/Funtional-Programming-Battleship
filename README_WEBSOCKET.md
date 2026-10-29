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
cabal run battleship -- web +RTS -N -RTS
```

Mở trình duyệt máy A tại:

`http://localhost:8080`

Để tìm IPv4 của máy A, mở PowerShell khác và chạy:

```powershell
ipconfig
```

Trên máy B cùng mạng LAN, mở:

`http://IP-MAY-A:8080`

Thay `IP-MAY-A` bằng địa chỉ IPv4 thật của máy A. Hai người cùng nhấn **Chơi qua LAN** để ghép trận. Tham số `+RTS -N -RTS` bật nhiều capability của GHC để runtime có thể chạy các luồng Haskell song song trên nhiều lõi CPU. Nếu Windows Firewall hỏi, chỉ cho phép trên mạng riêng (Private) mà bạn tin cậy.

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

## 6. Lưu và nạp lịch sử từ tệp

- Khi WebSocket server khởi động, chương trình đọc `data/match-history.log` nếu tệp đã tồn tại; nếu chưa có, chương trình tạo tệp mới.
- Các lệnh hợp lệ của hai người chơi, sự kiện bắt đầu/kết thúc trận được ghi nối tiếp vào tệp, mỗi dòng có dấu thời gian UTC. Một `MVar` bảo vệ thao tác ghi để các luồng không ghi đè dữ liệu của nhau.
- Có thể xem/nạp nội dung lịch sử qua `http://localhost:8080/history` trên máy chủ hoặc `http://IP-MAY-A:8080/history` từ máy khác trong LAN.
- Tệp lịch sử nằm trên máy host tại `data/match-history.log`; đây là nhật ký sự kiện/lệnh để tra cứu, không phải bản snapshot để khôi phục một ván đang chơi dở sau khi máy chủ tắt.
- Kiểm thử: chơi một trận, mở `/history`, dừng rồi khởi động lại máy chủ và mở `/history` lần nữa; các dòng cũ phải còn nguyên và các dòng mới phải có thời gian UTC.


## Khôi phục ván LAN khi máy chủ khởi động lại

Máy chủ lưu ảnh chụp trạng thái trận đang chơi vào `data/active-match.txt` sau mỗi lệnh đã xử lý. Khi khởi động lại, server nạp lại phòng chơi, bàn cờ hai bên, lượt bắn, các ô đã bắn và trạng thái xác nhận. Hai máy cần kết nối lại bằng đúng địa chỉ IP LAN đã dùng trong trận trước; server sẽ ghép chúng lại theo IP và gửi lại góc nhìn riêng của từng người chơi. Khi trận kết thúc bình thường, file trạng thái đang chơi được xóa; nhật ký vẫn nằm ở `data/match-history.log`.

Nếu router cấp IP động, hãy tạo DHCP reservation cho hai máy để giữ IP ổn định. IP là dấu hiệu nhận diện trong mạng LAN, không phải cơ chế xác thực bảo mật mạnh. Bản khôi phục lưu trạng thái gần nhất đã ghi ra đĩa; nếu server mất điện đúng lúc đang ghi file, thao tác cuối cùng có thể chưa được lưu.

Kiểm thử: bắt đầu trận LAN, đặt tàu và bắn ít nhất một lượt; dừng tiến trình server bằng `Ctrl+C` hoặc đóng tiến trình; chạy lại `cabal run battleship -- web`; sau đó mở lại chế độ LAN trên cả hai máy. Kiểm tra terminal thông báo hai IP cần quay lại và xác nhận bàn cờ/lượt bắn được khôi phục.
# Chơi ván mới qua LAN

# Chơi ván mới qua LAN

Đã tận dụng nút **Ván mới** có sẵn trong `web/index.html`. Sau khi ván LAN kết thúc, một người nhấn nút để gửi yêu cầu; người còn lại nhận thông báo và nút đổi thành **Xác nhận ván mới**. Khi người thứ hai xác nhận, server đặt lại phòng trên cùng WebSocket, hai người quay lại bước xếp tàu.

Lệnh `reset` vẫn xóa tàu khi phòng đang ở bước xếp tàu; chỉ khi ván đã kết thúc, `reset` mới được hiểu là yêu cầu/xác nhận chơi lại. Nhật ký `data/match-history.log` tiếp tục được ghi nối tiếp. `data/active-match.txt` giữ trạng thái chờ chơi lại để có thể nạp lại khi server khởi động.

Build kiểm tra bằng `cabal build all` từ thư mục gốc.

