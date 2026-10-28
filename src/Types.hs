-- | Types.hs
--
-- Toàn bộ kiểu dữ liệu dùng chung của project. Đây là "hợp đồng" giữa các
-- module: Engine, Parser, Protocol, Session, Render... đều chỉ nói chuyện
-- với nhau qua các kiểu ở đây.
--
-- Ý tưởng thiết kế quan trọng nhất (Chương 3 và 6):
--
--   * 'Board'        : bàn cờ ĐẦY ĐỦ của một người (có vị trí tàu). Không bao
--                      giờ được gửi cho đối thủ.
--   * 'PublicBoard'  : những gì đối thủ ĐƯỢC PHÉP thấy (chỉ các ô đã bị bắn).
--
--   Hai kiểu khác nhau nên trình biên dịch buộc ta phải đi qua hàm
--   'Engine.publicView' trước khi gửi dữ liệu đi. Quên che vị trí tàu địch
--   sẽ là lỗi biên dịch, không phải lỗi lúc chạy.
module Types where

import Data.Map.Strict (Map)
import Data.Set (Set)

-- ---------------------------------------------------------------------------
-- Hình học và tàu

-- | Kích thước bàn cờ (10 x 10).
boardSize :: Int
boardSize = 10

-- | Một ô: hàng và cột, đánh số từ 0. Người chơi gõ "B7" = hàng 1, cột 6.
data Coord = Coord { cRow :: !Int, cCol :: !Int }
  deriving (Eq, Ord, Show)

data Orientation = Horizontal | Vertical
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Năm loại tàu. 'Enum' + 'Bounded' cho phép viết [minBound .. maxBound]
-- để lấy cả hạm đội mà không phải liệt kê tay.
data ShipType = Carrier | Battleship | Cruiser | Submarine | Destroyer
  deriving (Eq, Ord, Show, Enum, Bounded)

data Player = P1 | P2
  deriving (Eq, Ord, Show, Enum, Bounded)

other :: Player -> Player
other P1 = P2
other P2 = P1

players :: [Player]
players = [minBound .. maxBound]

-- ---------------------------------------------------------------------------
-- Bàn cờ và ván đấu

-- | Bàn cờ đầy đủ của một người: tàu ở đâu, và những ô nào đã bị bắn vào.
-- Việc "tàu nào đã chìm" được TÍNH ra từ hai trường này chứ không lưu riêng,
-- nên không thể xảy ra trạng thái mâu thuẫn.
data Board = Board
  { bShips :: Map ShipType (Set Coord)
  , bShots :: Set Coord
  } deriving (Eq, Show)

-- | Kết quả của một phát bắn.
data ShotResult = Miss | Hit | Sunk ShipType
  deriving (Eq, Show)

-- | Một ô trên bàn cờ mà đối thủ nhìn thấy.
data PublicCell = PMiss | PHit | PSunk ShipType
  deriving (Eq, Show)

-- | Phần bàn cờ công khai: chỉ chứa các ô ĐÃ bị bắn.
newtype PublicBoard = PublicBoard (Map Coord PublicCell)
  deriving (Eq, Show)

-- | Ván đấu đang diễn ra (sau khi cả hai đã xếp tàu xong).
data Game = Game
  { gBoard1 :: Board
  , gBoard2 :: Board
  , gTurn   :: Player
  } deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Lỗi (dùng Either thay cho exception: lỗi là một giá trị bình thường)

data PlaceError
  = PlaceOutOfBounds
  | PlaceOverlap
  | PlaceDuplicate ShipType
  deriving (Eq, Show)

data FireError
  = FireOutOfRange
  | FireAlreadyShot
  | FireNotYourTurn
  | FireGameOver
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Giao tiếp người chơi <-> server

-- | Lệnh người chơi gõ vào.
data Command
  = Fire Coord
  | Place ShipType Coord Orientation
  | RandomFleet
  | Reset
  | Ready
  | Help
  | Quit
  deriving (Eq, Show)

data Phase = Placing | Playing | Over Player
  deriving (Eq, Show)

-- | Ảnh chụp trạng thái ván đấu TỪ GÓC NHÌN của một người chơi.
-- Chú ý 'vEnemy' có kiểu 'PublicBoard': không có chỗ nào để lọt vị trí tàu địch.
data View = View
  { vPhase :: Phase
  , vTurn  :: Maybe Player   -- ^ Nothing khi chưa bắt đầu bắn
  , vOwn   :: Board
  , vEnemy :: PublicBoard
  } deriving (Eq, Show)

-- | Thông điệp server gửi cho người chơi.
data ServerMsg
  = SWelcome Player
  | SInfo String
  | SError String
  | SView View
  | SShot Player Coord ShotResult   -- ^ ai bắn ô nào, kết quả gì
  | SGameOver Player                -- ^ người thắng
  deriving (Eq, Show)
