# Battleship — Haskell và giao diện Web LAN

## Giới thiệu

Dự án Battleship có chế độ chơi với máy và chế độ hai người qua mạng LAN. Giao diện web nằm tại `web/index.html`; phần luật chơi và quản lý phiên LAN nằm trong mã nguồn Haskell tại `src/`.

## Chạy dự án

Mở terminal tại thư mục gốc `battleship`.

```bash
cabal build all
```
```bash
cabal run battleship -- web +RTS -N -RTS
```

Sau khi build thành công, chạy server bằng lệnh khởi động Web Server mà dự án đang sử dụng. Server cần được chạy từ thư mục gốc để có thể đọc `web/index.html` và ghi dữ liệu trong `data/`. Hai máy phải ở cùng mạng LAN; máy khách mở địa chỉ IP LAN của máy chạy server cùng cổng đã cấu hình.

## Điều khiển trong chế độ LAN

- **Ván mới**: giữ nguyên chức năng chơi ván tiếp theo sau khi ván hiện tại đã kết thúc. Hai người xác nhận xếp tàu để bắt đầu ván kế tiếp.
- **Chơi lại giữa trận**: cho phép đề nghị bỏ ván đang diễn ra để bắt đầu ván mới mà không cần chơi đến khi có người thắng.
- Khi một người nhấn **Chơi lại giữa trận**, trận đấu tạm dừng và các lượt bắn không được xử lý trong lúc chờ. Người còn lại phải xác nhận yêu cầu.
- Khi cả hai đồng ý, phòng đấu được khởi tạo lại và cả hai trở về bước xếp tàu. Mỗi người cần xếp đủ tàu và xác nhận sẵn sàng để bắt đầu ván mới.
- Nếu đối thủ đã gửi yêu cầu, nút tương ứng trên giao diện đổi thành **Xác nhận chơi lại**.
- Trong chế độ ngoại tuyến, **Ván mới** vẫn bắt đầu một ván mới với máy; nút chơi lại giữa trận không được dùng để điều khiển chế độ ngoại tuyến.

## Lưu lịch sử và trạng thái

- `data/match-history.log`: nhật ký nối tiếp các lệnh và sự kiện của trận đấu.
- Khi trận kết thúc bình thường, lịch sử ghi sự kiện `MATCH END`.
- Khi hai người xác nhận bỏ một ván đang diễn ra để chơi lại, lịch sử ghi sự kiện `MATCH ABANDONED/RESTARTED`, phân biệt với ván đã hoàn tất.
- `data/active-match.txt`: lưu trạng thái trận hiện hành để server có thể khôi phục theo cơ chế lưu/nạp hiện có.
- Nên sao lưu thư mục `data/` trước khi thử nghiệm thay đổi định dạng dữ liệu hoặc chạy phiên bản mã nguồn khác.

## Các file chính liên quan đến chức năng chơi lại

- `web/index.html`: nút **Ván mới**, **Chơi lại giữa trận**, thông báo và xác nhận trên giao diện.
- `src/Session.hs`: trạng thái phòng, yêu cầu chơi lại, tạm dừng bắn và tạo lại phòng khi cả hai đồng ý.
- `src/WebServer.hs`: xử lý lệnh WebSocket, lưu trạng thái trận và ghi sự kiện vào lịch sử.

## Kiểm tra

Chạy `cabal build all` từ thư mục gốc. Build thành công không thay thế cho việc kiểm thử thực tế trên hai trình duyệt/máy LAN; cần kiểm tra cả luồng kết thúc bình thường lẫn luồng chơi lại giữa trận.
