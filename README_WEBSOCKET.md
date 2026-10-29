# Chơi ván mới và chơi lại giữa trận qua LAN

## Hai chức năng khác nhau

### Ván mới — sau khi ván kết thúc

Nút **Ván mới** tiếp tục có vai trò bắt đầu ván kế tiếp sau khi ván hiện tại đã kết thúc. Hai người giữ kết nối, trở về bước xếp tàu và cần xác nhận sẵn sàng để bắt đầu ván mới.

### Chơi lại giữa trận — bỏ ván đang diễn ra

1. Một người nhấn **Chơi lại giữa trận**.
2. Máy chủ ghi nhận yêu cầu và tạm dừng ván hiện tại; các lượt bắn tiếp theo bị từ chối trong lúc chờ xác nhận.
3. Đối thủ nhận thông báo và nhấn **Xác nhận chơi lại**.
4. Khi cả hai đồng ý, máy chủ khởi tạo phòng mới và gửi trạng thái xếp tàu cho cả hai người.
5. Cả hai xếp tàu và xác nhận sẵn sàng như khi bắt đầu ván mới.

Yêu cầu chơi lại không tự động xóa ván ngay khi người đầu tiên nhấn nút. Việc chuyển sang phòng mới chỉ xảy ra khi người thứ hai xác nhận.

## Lịch sử

- `data/match-history.log` được ghi nối tiếp.
- Ván kết thúc bình thường được ghi bằng sự kiện `MATCH END`.
- Ván đang diễn ra bị bỏ để chơi lại được ghi bằng sự kiện `MATCH ABANDONED/RESTARTED` khi cả hai xác nhận.
- `data/active-match.txt` lưu trạng thái trận hiện hành theo cơ chế lưu/nạp của server.

## Build và chạy

Từ thư mục gốc dự án, chạy:

```bash
cabal build all
```

Khởi động Web Server theo lệnh của dự án, rồi mở trang web trên cả hai máy trong cùng mạng LAN bằng địa chỉ IP LAN của máy chạy server và cổng đã cấu hình. Chạy server từ thư mục gốc `battleship` để các đường dẫn `web/` và `data/` được phân giải đúng.

Cần kiểm thử thực tế trên hai máy sau khi build; hướng dẫn này mô tả hành vi dự kiến của chức năng, không thay thế xác nhận kiểm thử LAN.
