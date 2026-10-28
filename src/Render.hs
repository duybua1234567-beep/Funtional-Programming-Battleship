-- | Render.hs
--
-- Vẽ bàn cờ ra terminal (Chương 4: type class).
--
-- 'Renderable' là một type class: "kiểu nào biết tự vẽ mình thành các dòng
-- chữ". Logic game không hề biết chuyện vẽ; muốn đổi sang giao diện khác
-- (web, đồ họa) chỉ cần viết instance mới, không sửa Engine.
--
-- Quyết định UX (xem docs/design.md):
--   * Mọi trạng thái có KÝ HIỆU riêng chứ không chỉ khác màu, để người mù màu
--     vẫn phân biệt được:  ~ nước   # tàu mình   o trượt   X trúng   @ chìm.
--   * Hai bàn cờ đặt cạnh nhau, có tiêu đề, nhãn hàng/cột, chú thích.
--   * Dòng trạng thái luôn nói rõ "bây giờ đến lượt ai, mình cần làm gì".
module Render
  ( Theme (..)
  , Renderable (..)
  , renderView
  , renderMsg
  , paint
  , visibleLength
  ) where

import Data.List (nub, (\\))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Engine
import Parser (showCoord)
import Types

-- | Có dùng màu ANSI hay không.
data Theme = Plain | Color
  deriving (Eq, Show)

class Renderable a where
  render :: Theme -> a -> [String]

-- | Tô màu bằng mã ANSI (chỉ khi theme là Color).
paint :: Theme -> String -> String -> String
paint Plain _    s = s
paint Color code s = "\ESC[" ++ code ++ "m" ++ s ++ "\ESC[0m"

-- | Độ dài hiển thị của một chuỗi, bỏ qua các mã màu ESC[...m.
visibleLength :: String -> Int
visibleLength []                   = 0
visibleLength ('\ESC' : '[' : xs)  = visibleLength (drop 1 (dropWhile (/= 'm') xs))
visibleLength (_ : xs)             = 1 + visibleLength xs

padLeft :: Int -> String -> String
padLeft n s = replicate (n - length s) ' ' ++ s

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - visibleLength s) ' '

-- ---------------------------------------------------------------------------
-- Lưới

data Glyph = GWater | GShip | GMiss | GHit | GSunk

paintGlyph :: Theme -> Glyph -> String
paintGlyph th g = case g of
  GWater -> paint th "36"   "~"
  GShip  -> paint th "32"   "#"
  GMiss  -> paint th "33"   "o"
  GHit   -> paint th "31"   "X"
  GSunk  -> paint th "1;31" "@"

-- | Vẽ lưới 10x10 với nhãn cột (1-10) và nhãn hàng (A-J).
renderGrid :: Theme -> (Coord -> Glyph) -> [String]
renderGrid th at = header : map row [0 .. boardSize - 1]
  where
    header = " " ++ concat [padLeft 3 (show n) | n <- [1 .. boardSize]]
    row r  = rowLabel r : concat [ "  " ++ paintGlyph th (at (Coord r c))
                                 | c <- [0 .. boardSize - 1] ]
    rowLabel r = toEnum (fromEnum 'A' + r)

-- | Bàn cờ của MÌNH: thấy cả tàu.
instance Renderable Board where
  render th b = renderGrid th glyph
    where
      glyph c = case [st | (st, cs) <- Map.toList (bShips b), c `Set.member` cs] of
        (st : _) | c `Set.member` bShots b -> if isSunk st b then GSunk else GHit
                 | otherwise               -> GShip
        []       | c `Set.member` bShots b -> GMiss
                 | otherwise               -> GWater

-- | Bàn cờ của ĐỐI THỦ: chỉ thấy các ô đã bắn.
instance Renderable PublicBoard where
  render th (PublicBoard m) = renderGrid th glyph
    where
      glyph c = case Map.lookup c m of
        Nothing         -> GWater
        Just PMiss      -> GMiss
        Just PHit       -> GHit
        Just (PSunk _)  -> GSunk

-- ---------------------------------------------------------------------------
-- Màn hình đầy đủ

-- | Vẽ toàn bộ trạng thái, từ góc nhìn của người chơi @me@.
renderView :: Theme -> Player -> View -> [String]
renderView th me v =
  [""] ++ body ++ ["", legend] ++ fleetLine ++ status
  where
    left  = paint th "1" "HẠM ĐỘI CỦA BẠN" : render th (vOwn v)
    right = paint th "1" "VÙNG BIỂN ĐỊCH"  : render th (vEnemy v)
    width = maximum (map visibleLength left) + 4
    body  = zipWith (\l r -> padRight width l ++ r) left right

    legend = "Chú thích: ~ nước   # tàu của bạn   o bắn trượt   X trúng   @ tàu đã chìm"

    PublicBoard pm = vEnemy v
    ownShips   = vOwn v
    sunkByUs   = nub [st | PSunk st <- Map.elems pm]
    afloat     = length (unsunkShips ownShips)

    fleetLine = case vPhase v of
      Placing -> []
      _       -> [ "Tàu của bạn còn nổi: " ++ show afloat ++ "/" ++ show (length [minBound .. maxBound :: ShipType])
                   ++ "   |   Tàu địch đã chìm: "
                   ++ (if null sunkByUs then "chưa có" else unwords (map show sunkByUs)) ]

    missing = [minBound .. maxBound] \\ Map.keys (bShips ownShips)

    status = case vPhase v of
      Placing
        | null missing -> [paint th "1;32" "Đã đủ 5 tàu: gõ ready để xác nhận (hoặc reset để xếp lại)."]
        | otherwise    -> [ "Giai đoạn xếp tàu. Còn phải xếp: "
                            ++ unwords [show st ++ "(" ++ show (shipSize st) ++ ")" | st <- missing]
                          , "Gõ: place <tàu> <ô> <h|v>   hoặc   random   (help để xem thêm)" ]
      Playing
        | vTurn v == Just me -> [paint th "1;32" ">>> ĐẾN LƯỢT BẠN: gõ ô muốn bắn (ví dụ: b7)"]
        | otherwise          -> ["Đang chờ đối thủ bắn..."]
      Over w
        | w == me   -> [paint th "1;32" "*** BẠN THẮNG! ***"]
        | otherwise -> [paint th "1;31" "*** BẠN THUA. Chúc may mắn lần sau! ***"]

-- | Chuyển một thông điệp của server thành các dòng chữ cho người chơi @me@.
renderMsg :: Theme -> Player -> ServerMsg -> [String]
renderMsg th me msg = case msg of
  SWelcome p ->
    [ "Bạn là " ++ playerName p ++ "."
    , "Gõ help để xem các lệnh." ]
  SInfo s    -> [s]
  SError s   -> [paint th "31" ("Lỗi: " ++ s)]
  SView v    -> renderView th me v
  SShot p c r ->
    [ (if p == me then "Bạn" else "Đối thủ") ++ " bắn " ++ showCoord c ++ ": " ++ describe r ]
  SGameOver w ->
    [ if w == me then "Bạn đã thắng ván này!" else "Đối thủ đã thắng ván này." ]
  where
    describe Miss     = "trượt."
    describe Hit      = paint th "31" "TRÚNG!"
    describe (Sunk s) = paint th "1;31" ("TRÚNG và ĐÁNH CHÌM " ++ show s ++ "!")

playerName :: Player -> String
playerName P1 = "Người chơi 1"
playerName P2 = "Người chơi 2"
