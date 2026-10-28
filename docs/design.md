# Thiết kế Battleship

Tài liệu này giải thích **vì sao** project được thiết kế như vậy, để cả nhóm trả lời được khi bảo vệ.

## 1. Kiến trúc: lõi thuần, vỏ IO mỏng

```
        ┌────────────── THUẦN (không IO) ──────────────┐
        │  Types · Engine · Parser · Protocol          │
        │  AI · Render · Rng · Session                 │
        └───────────────▲──────────────────────────────┘
                        │ gọi
   ┌────────────────────┼────────────────────┐
   │ Solo (stdin/stdout)│ Server (TCP, STM)  │ Client (TCP, stdin)
   └────────────────────┴────────────────────┘
                     IO (mỏng)
```

Mọi chuyện xảy ra khi người chơi gõ lệnh được mô tả bằng **một hàm thuần**:

```haskell
stepRoom :: Player -> Command -> Room -> (Room, [Outgoing])
```

Nhận phòng cũ và lệnh, trả phòng mới và danh sách thông điệp cần gửi. `Solo` (chơi với máy) và `Server` (chơi qua mạng) đều chỉ gọi hàm này, nên hai chế độ cư xử y hệt nhau mà không phải viết lại luật. Máy chơi chỉ là "người chơi 2" gửi lệnh `Fire` vào đúng hàm đó.

**Vì sao hay:** hàm thuần cùng đầu vào luôn cho cùng kết quả, nên test bằng QuickCheck dễ, gỡ lỗi lặp lại được, và không có lỗi "trạng thái toàn cục bị sửa ở đâu đó".

## 2. Bảo vệ thông tin ẩn bằng hệ thống kiểu

Battleship là game thông tin ẩn: không ai được thấy tàu của đối thủ. Thay vì dặn nhau "nhớ đừng gửi vị trí tàu", ta để **kiểu dữ liệu ép buộc**:

- `Board`: bàn cờ đầy đủ (có tàu), chỉ ở server/Session.
- `PublicBoard`: chỉ chứa các ô đã bị bắn.
- Cầu nối duy nhất là `Engine.publicView :: Board -> PublicBoard`.
- `View` (thứ gửi cho người chơi) chứa `vEnemy :: PublicBoard`, nên không có chỗ nào để lọt vị trí tàu địch. Máy (`AI`) cũng chỉ nhìn thấy `PublicBoard`, nên không thể gian lận.

Test `prop_viewNeverLeaks` kiểm tra điều này trên cả ván đấu. Để chắc test thật sự "cắn", ta đã thử cố ý phá `publicView` cho lộ tàu, và nhiều test lập tức báo lỗi.

## 3. Ánh xạ nội dung môn học

| Chương | Xuất hiện ở đâu | Điểm đáng nói khi bảo vệ |
|---|---|---|
| 1. Tổng quan | Toàn project: `Engine`/`Session` không có IO | So với bản mệnh lệnh: không có biến bị sửa tại chỗ, mỗi nước đi tạo giá trị mới |
| 2. Biểu thức, rút gọn | Mọi hàm của `Engine` | Ví dụ rút gọn bên dưới |
| 3. Kiểu và đa hình | `Board` vs `PublicBoard`; `State s a`; `Parser a` | Đa hình tham số: `State s a` dùng cho Seed, `Parser a` cho mọi loại kết quả |
| 4. Type class | `Renderable` (tự định nghĩa); `Eq/Ord/Show/Enum/Bounded` (derive); instance `Functor/Applicative/Monad/Alternative` cho `State` và `Parser` | `[minBound .. maxBound]` lấy cả hạm đội nhờ `Enum` + `Bounded` |
| 5. Đệ quy, hàm bậc cao | `foldM`, `foldl`, `map`, `filter`, list comprehension; `placeRandom` đệ quy | `candidates` trong `AI.hs` toàn list comprehension |
| 6. Kiểu đại số, quy nạp | `Command`, `ServerMsg`, `ShotResult`, `Phase`... | Lập luận quy nạp ở mục 5 bên dưới |
| 7. Lazy, Functor/Applicative/Monad | `State` (Rng), `Either` trong `fire`, lazy trong `AI.candidates` | Mục 4 bên dưới |
| 8. Monad, Parser, song song | `Parser.hs` tự viết; `Protocol.hs` dùng lại; `STM` trong `Server.hs` | Parser dùng cho CẢ lệnh người chơi lẫn giao thức mạng |
| 9. Module, đa tiến trình, mạng | 11 module; `forkIO`, `TVar`, `TQueue`, `MVar`; socket TCP | Mỗi người chơi 2 luồng (đọc/ghi) + một `TVar Room` chung |

### Ví dụ rút gọn biểu thức (Chương 2)

```
shipCells Destroyer (Coord 0 0) Horizontal
= [step i | i <- [0 .. shipSize Destroyer - 1]]
= [step i | i <- [0 .. 2 - 1]]
= [step i | i <- [0 .. 1]]
= [step 0, step 1]
= [Coord 0 (0+0), Coord 0 (0+1)]
= [Coord 0 0, Coord 0 1]
```

## 4. Điểm kỹ thuật đáng nhấn mạnh

**Monad `Either` trong `fire`.** Mỗi bước kiểm tra (game đã kết thúc? đúng lượt? ô hợp lệ? chưa bắn?) có thể thất bại. Dùng `do` trong monad `Either` thì bước nào lỗi, cả hàm trả đúng lỗi đó, không cần `if/else` lồng nhau và không cần exception.

**Monad `State` tự viết (`Rng.hs`).** Hàm thuần không "lấy số ngẫu nhiên" được vì mỗi lần gọi phải cho cùng kết quả. Giải pháp: Seed là một giá trị, mỗi lần dùng trả Seed mới. `State` giấu việc chuyền Seed bằng tay, và `foldM` chạy được trong nó vì nó là Monad. Bonus: cùng Seed cho cùng ván đấu, nên lỗi tái hiện được.

**Parser combinators (`Parser.hs`).** Parser là hàm `String -> Maybe (a, String)`. Ghép bằng `<$>`, `<*>`, `>>=`, `<|>`. Lưu ý quan trọng: `<|>` là lựa chọn **theo thứ tự**, nhánh nào thành công trước thì dùng, nên phải đặt nhánh dài trước ngắn (`"horizontal"` trước `"h"`). Đây là chỗ dễ sai nhất khi viết parser.

**Lazy evaluation trong AI.** `candidates` dựng 4 nhóm ô ứng viên rồi lấy nhóm đầu tiên không rỗng: `filter (not . null) [lineExtension, nextToHit, parityHunt, untried]`. Nhờ lazy, các nhóm phía sau (kể cả `untried` quét cả 100 ô) không bao giờ được tính nếu nhóm trước đã có ô.

**STM thay cho khóa (`Server.hs`).** Hai người chơi gõ lệnh cùng lúc đều sửa `TVar Room`. Mỗi lần xử lý lệnh là một giao dịch `atomically` (đọc phòng, chạy hàm thuần `stepRoom`, ghi phòng, đẩy thông điệp vào hàng đợi). STM đảm bảo giao dịch nguyên tử mà không cần khóa thủ công, nên không lo deadlock.

## 5. Lập luận quy nạp: vì sao ván đấu luôn kết thúc

Mỗi lần `fire` thành công thêm đúng một ô vào `bShots` của người bị bắn, và `receiveShot` từ chối ô đã có. Bàn cờ có 100 ô nên mỗi bàn nhận tối đa 100 phát. Theo quy nạp trên số ô chưa bị bắn: nếu còn 0 ô thì mọi ô tàu đã bị bắn, tức hạm đội chìm hết; nếu còn k+1 ô thì mỗi lượt giảm số này đi 1 nên sau hữu hạn bước về 0. Vậy sau tối đa 200 lượt thì có người thắng. Test `prop_gameTerminates` kiểm tra đúng cận 200 này trên hàng trăm ván ngẫu nhiên.

## 6. Giao thức mạng

Mỗi thông điệp server gửi là **một dòng văn bản**:

```
WELCOME P1
INFO <văn bản>
ERROR <văn bản>
SHOT P1 B7 MISS            (hoặc HIT, hoặc SUNK:Carrier)
OVER P1
VIEW|<phase>|<lượt>|<tàu của bạn>|<ô đã bị bắn>|<bàn địch>
```

Ví dụ `VIEW|playing|P1|Carrier:A1,A2,A3,A4,A5;Destroyer:C3,C4|A1,B2|B2=miss,D4=hit`.

Chiều client gửi lên không cần định dạng riêng: client gửi thẳng dòng người dùng gõ, server tự phân tích bằng `parseCommand`. Việc giải mã dùng lại chính `Parser`, và test `prop_protocolRoundTrip` kiểm tra `decode (encode m) == Just m` với mọi thông điệp.

## 7. UI/UX (điểm cộng)

Đã làm trong bản terminal:

- **Không chỉ dựa vào màu:** mỗi trạng thái có ký hiệu riêng (`~ # o X @`), người mù màu vẫn phân biệt được. Màu chỉ là lớp hỗ trợ.
- **Hai bàn cờ cạnh nhau**, có tiêu đề, nhãn hàng/cột, chú thích ký hiệu.
- **Dòng trạng thái luôn nói rõ bước tiếp theo:** "ĐẾN LƯỢT BẠN: gõ ô muốn bắn", "Đang chờ đối thủ", "Còn phải xếp: ...".
- **Lỗi nói rõ lý do và cách sửa:** "Tàu bị chồng lên một tàu khác", "Bạn đã bắn ô này rồi", "Cú pháp: place <tàu> <ô> <h|v>, ví dụ: ...".
- **Nhập liệu thoải mái:** không phân biệt hoa thường, chỉ gõ `b7` cũng bắn được, `random` cho người không muốn xếp tay.
- **Phản hồi sau mỗi phát bắn:** nói rõ trượt/trúng/đánh chìm tàu nào.

Nhờ type class `Renderable`, đổi sang giao diện khác (web, đồ họa) chỉ cần viết instance mới, **không sửa Engine**. Đây là hướng mở rộng tự nhiên nếu nhóm muốn thêm điểm UI/UX: giữ nguyên `Session`/`Protocol`, thay `Client` bằng WebSocket + HTML.

Gợi ý cho báo cáo UI/UX: vẽ wireframe cho bản web, mô tả user flow (kết nối → xếp tàu → ready → bắn → kết thúc), và thử nghiệm với 3-5 bạn cùng lớp theo kịch bản "xếp tàu rồi bắn trong 2 phút, không đọc hướng dẫn", ghi lại chỗ họ vướng (ví dụ cú pháp `place`) để chứng minh quyết định thiết kế.

## 8. Hạn chế đã biết

- Mỗi lần chạy server chỉ phục vụ một trận tại một thời điểm (xong trận thì nhận cặp mới).
- Chưa có chức năng chơi lại (rematch) trong cùng kết nối: muốn chơi lại thì thoát và kết nối lại.
- Giao thức không mã hóa; chỉ dùng trong mạng nội bộ.
- Xếp tàu xong và bấm `ready` thì không đổi được nữa.
