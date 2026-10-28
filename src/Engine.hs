-- | Engine.hs
--
-- Luật chơi Battleship, viết hoàn toàn bằng HÀM THUẦN (Chương 1-2, 5, 6).
-- Không có IO, không có biến toàn cục: mỗi bước đi là một hàm biến trạng thái
-- cũ thành trạng thái mới, nên rất dễ kiểm thử bằng QuickCheck.
module Engine
  ( -- * Tàu và hình học
    shipSize
  , inBounds
  , allCoords
  , shipCells
    -- * Bàn cờ
  , emptyBoard
  , occupied
  , placeShip
  , fleetComplete
  , isSunk
  , allSunk
  , unsunkShips
  , receiveShot
  , publicView
  , randomBoard
    -- * Ván đấu
  , newGame
  , boardOf
  , setBoardOf
  , fire
  , winner
  ) where

import Control.Monad (foldM)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Set (Set)
import qualified Data.Set as Set

import Rng
import Types

-- ---------------------------------------------------------------------------
-- Tàu và hình học

shipSize :: ShipType -> Int
shipSize Carrier    = 5
shipSize Battleship = 4
shipSize Cruiser    = 3
shipSize Submarine  = 3
shipSize Destroyer  = 2

inBounds :: Coord -> Bool
inBounds (Coord r c) = r >= 0 && r < boardSize && c >= 0 && c < boardSize

-- | Mọi ô của bàn cờ (list comprehension).
allCoords :: [Coord]
allCoords = [Coord r c | r <- [0 .. boardSize - 1], c <- [0 .. boardSize - 1]]

-- | Các ô một con tàu chiếm khi đặt tại ô đầu và hướng cho trước.
shipCells :: ShipType -> Coord -> Orientation -> [Coord]
shipCells st (Coord r c) o = [step i | i <- [0 .. shipSize st - 1]]
  where
    step i = case o of
      Horizontal -> Coord r (c + i)
      Vertical   -> Coord (r + i) c

-- ---------------------------------------------------------------------------
-- Bàn cờ

emptyBoard :: Board
emptyBoard = Board Map.empty Set.empty

-- | Mọi ô đang có tàu.
occupied :: Board -> Set Coord
occupied = Set.unions . Map.elems . bShips

-- | Đặt một tàu. Trả 'Left' nếu sai luật; không bao giờ ném exception.
placeShip :: ShipType -> Coord -> Orientation -> Board -> Either PlaceError Board
placeShip st c o b
  | st `Map.member` bShips b             = Left (PlaceDuplicate st)
  | not (all inBounds cells)             = Left PlaceOutOfBounds
  | any (`Set.member` occupied b) cells  = Left PlaceOverlap
  | otherwise = Right b { bShips = Map.insert st (Set.fromList cells) (bShips b) }
  where
    cells = shipCells st c o

-- | Đã xếp đủ cả 5 tàu chưa.
fleetComplete :: Board -> Bool
fleetComplete b = all (`Map.member` bShips b) [minBound .. maxBound]

-- | Tàu chìm khi MỌI ô của nó đã bị bắn (tính ra, không lưu).
isSunk :: ShipType -> Board -> Bool
isSunk st b = case Map.lookup st (bShips b) of
  Nothing    -> False
  Just cells -> cells `Set.isSubsetOf` bShots b

allSunk :: Board -> Bool
allSunk b = fleetComplete b && all (`isSunk` b) (Map.keys (bShips b))

unsunkShips :: Board -> [ShipType]
unsunkShips b = [st | st <- Map.keys (bShips b), not (isSunk st b)]

-- | Ô này (đã bị bắn) hiện ra sao với người ngoài.
classifyShot :: Board -> Coord -> PublicCell
classifyShot b c =
  case [st | (st, cells) <- Map.toList (bShips b), c `Set.member` cells] of
    []       -> PMiss
    (st : _) -> if isSunk st b then PSunk st else PHit

-- | Nhận một phát bắn. Bắn trùng ô hoặc ngoài bàn là lỗi.
receiveShot :: Coord -> Board -> Either FireError (ShotResult, Board)
receiveShot c b
  | not (inBounds c)          = Left FireOutOfRange
  | c `Set.member` bShots b   = Left FireAlreadyShot
  | otherwise                 = Right (toResult (classifyShot b' c), b')
  where
    b' = b { bShots = Set.insert c (bShots b) }
    toResult PMiss      = Miss
    toResult PHit       = Hit
    toResult (PSunk st) = Sunk st

-- | Phần bàn cờ ĐƯỢC PHÉP lộ ra cho đối thủ: chỉ các ô đã bị bắn.
-- Đây là cửa duy nhất để thông tin đi từ 'Board' sang 'PublicBoard'.
publicView :: Board -> PublicBoard
publicView b = PublicBoard (Map.fromSet (classifyShot b) (bShots b))

-- | Xếp ngẫu nhiên cả hạm đội. Dùng 'foldM' trong monad State: duyệt qua từng
-- loại tàu, mỗi lần thử một vị trí ngẫu nhiên cho tới khi hợp lệ.
-- (Luôn dừng vì bàn cờ 100 ô chỉ có 17 ô tàu nên luôn còn chỗ trống.)
randomBoard :: State Seed Board
randomBoard = foldM placeRandom emptyBoard [minBound .. maxBound]

placeRandom :: Board -> ShipType -> State Seed Board
placeRandom b st = do
  r <- nextInt boardSize
  c <- nextInt boardSize
  k <- nextInt 2
  let o = if k == 0 then Horizontal else Vertical
  case placeShip st (Coord r c) o b of
    Right b' -> pure b'
    Left _   -> placeRandom b st

-- ---------------------------------------------------------------------------
-- Ván đấu

-- | Người chơi 1 bắn trước.
newGame :: Board -> Board -> Game
newGame b1 b2 = Game b1 b2 P1

boardOf :: Player -> Game -> Board
boardOf P1 = gBoard1
boardOf P2 = gBoard2

setBoardOf :: Player -> Board -> Game -> Game
setBoardOf P1 b g = g { gBoard1 = b }
setBoardOf P2 b g = g { gBoard2 = b }

-- | Người thắng là người đã đánh chìm hết tàu đối phương.
winner :: Game -> Maybe Player
winner g
  | allSunk (gBoard2 g) = Just P1
  | allSunk (gBoard1 g) = Just P2
  | otherwise           = Nothing

-- | Một lượt bắn. Dùng monad của 'Either' để các bước kiểm tra nối tiếp nhau:
-- bước nào lỗi thì cả hàm trả lỗi đó, không cần if/else lồng nhau.
fire :: Player -> Coord -> Game -> Either FireError (ShotResult, Game)
fire p c g
  | isJust (winner g) = Left FireGameOver
  | p /= gTurn g      = Left FireNotYourTurn
  | otherwise = do
      (res, b') <- receiveShot c (boardOf target g)
      pure (res, (setBoardOf target b' g) { gTurn = target })
  where
    target = other p
