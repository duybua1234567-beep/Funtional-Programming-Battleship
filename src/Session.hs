-- | Session.hs
--
-- "Phòng chơi": trạng thái của một trận đấu giữa hai người, và MỘT hàm thuần
-- duy nhất 'stepRoom' mô tả mọi chuyện xảy ra khi có người gõ lệnh:
--
--   stepRoom :: Player -> Command -> Room -> (Room, [Outgoing])
--
-- Nhận phòng cũ + lệnh, trả phòng mới + danh sách thông điệp cần gửi cho ai.
-- Server mạng và chế độ chơi với máy đều dùng chung hàm này; chúng chỉ là lớp
-- vỏ IO mỏng bao quanh. Đây là nguyên tắc "lõi thuần, vỏ IO mỏng" (Chương 1, 9).
module Session
  ( Room (..)
  , Outgoing
  , initialRoom
  , stepRoom
  , viewFor
  , isOver
  , helpLines
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Set (Set)
import qualified Data.Set as Set

import Engine
import Rng
import Types

data Room = Room
  { rBoards :: Map Player Board   -- ^ bàn cờ (đang xếp) của từng người
  , rReady  :: Set Player         -- ^ ai đã bấm ready
  , rGame   :: Maybe Game         -- ^ Just khi cả hai đã sẵn sàng
  , rSeed   :: !Seed              -- ^ nguồn ngẫu nhiên cho lệnh 'random'
  } deriving (Show)

-- | (gửi cho ai, nội dung)
type Outgoing = (Player, ServerMsg)

initialRoom :: Seed -> Room
initialRoom = Room Map.empty Set.empty Nothing

boardIn :: Player -> Room -> Board
boardIn p = Map.findWithDefault emptyBoard p . rBoards

setBoardIn :: Player -> Board -> Room -> Room
setBoardIn p b room = room { rBoards = Map.insert p b (rBoards room) }

isOver :: Room -> Bool
isOver room = maybe False (isJust . winner) (rGame room)

-- | Trạng thái nhìn từ một người chơi. Nhờ 'publicView', người chơi KHÔNG
-- BAO GIỜ nhận được vị trí tàu của đối thủ (kể cả khi đang xếp tàu).
viewFor :: Player -> Room -> View
viewFor p room = View
  { vPhase = phase
  , vTurn  = gTurn <$> rGame room
  , vOwn   = own
  , vEnemy = publicView foe
  }
  where
    (own, foe) = case rGame room of
      Just g  -> (boardOf p g, boardOf (other p) g)
      Nothing -> (boardIn p room, emptyBoard)   -- chưa bắt đầu: đối thủ trống
    phase = case rGame room of
      Nothing -> Placing
      Just g  -> maybe Playing Over (winner g)

-- | Xử lý một lệnh của một người chơi.
stepRoom :: Player -> Command -> Room -> (Room, [Outgoing])
stepRoom p cmd room = case cmd of
  Help        -> (room, [(p, SInfo l) | l <- helpLines])
  Quit        -> (room, [])

  Place st c o -> whilePlacing $ \b ->
    case placeShip st c o b of
      Left e   -> (room, [err (describePlaceError e)])
      Right b' ->
        let room' = setBoardIn p b' room
            hint  = [ (p, SInfo "Đã đủ 5 tàu. Gõ ready để xác nhận, hoặc reset để xếp lại.")
                    | fleetComplete b' ]
        in (room', (p, SView (viewFor p room')) : hint)

  RandomFleet -> whilePlacing $ \_ ->
    let (b', seed') = runState randomBoard (rSeed room)
        room'       = (setBoardIn p b' room) { rSeed = seed' }
    in (room', [ (p, SView (viewFor p room'))
               , (p, SInfo "Đã xếp ngẫu nhiên. Gõ ready để xác nhận, hoặc random/reset để làm lại.") ])

  Reset -> whilePlacing $ \_ ->
    let room' = setBoardIn p emptyBoard room
    in (room', [(p, SView (viewFor p room'))])

  Ready
    | isJust (rGame room)           -> (room, [err "Ván đấu đã bắt đầu."])
    | p `Set.member` rReady room    -> (room, [err "Bạn đã sẵn sàng rồi, đang chờ đối thủ."])
    | not (fleetComplete (boardIn p room)) -> (room, [err "Bạn chưa xếp đủ 5 tàu."])
    | Set.size ready' == 2          -> startGame room1
    | otherwise                     -> (room1, [(p, SInfo "Đã sẵn sàng. Đang chờ đối thủ...")])
    where
      ready' = Set.insert p (rReady room)
      room1  = room { rReady = ready' }

  Fire c -> case rGame room of
    Nothing -> (room, [err "Ván đấu chưa bắt đầu. Hãy xếp tàu và gõ ready."])
    Just g  -> case fire p c g of
      Left e -> (room, [err (describeFireError e)])
      Right (res, g') ->
        let room'  = room { rGame = Just g' }
            shots  = [(q, SShot p c res) | q <- players]
            views  = [(q, SView (viewFor q room')) | q <- players]
            ending = case winner g' of
              Just w  -> [(q, SGameOver w) | q <- players]
              Nothing -> []
        in (room', shots ++ views ++ ending)
  where
    err msg = (p, SError msg)

    -- Các lệnh xếp tàu chỉ hợp lệ trước khi bấm ready.
    whilePlacing k
      | isJust (rGame room) || p `Set.member` rReady room =
          (room, [err "Bạn không thể xếp tàu lúc này."])
      | otherwise = k (boardIn p room)

    startGame r =
      let g  = newGame (boardIn P1 r) (boardIn P2 r)
          r' = r { rGame = Just g }
      in ( r'
         , concat [ [ (q, SInfo "Bắt đầu! Người chơi 1 bắn trước.")
                    , (q, SView (viewFor q r')) ]
                  | q <- players ] )

describePlaceError :: PlaceError -> String
describePlaceError PlaceOutOfBounds   = "Tàu vượt ra ngoài bàn cờ."
describePlaceError PlaceOverlap       = "Tàu bị chồng lên một tàu khác."
describePlaceError (PlaceDuplicate s) = show s ++ " đã được xếp rồi (gõ reset để xếp lại)."

describeFireError :: FireError -> String
describeFireError FireOutOfRange  = "Ô nằm ngoài bàn cờ."
describeFireError FireAlreadyShot = "Bạn đã bắn ô này rồi, hãy chọn ô khác."
describeFireError FireNotYourTurn = "Chưa đến lượt bạn."
describeFireError FireGameOver    = "Ván đấu đã kết thúc."

helpLines :: [String]
helpLines =
  [ "Các lệnh:"
  , "  place <tàu> <ô> <h|v>   xếp tàu, ví dụ: place carrier a1 h   (h = ngang, v = dọc)"
  , "  random                  xếp ngẫu nhiên cả hạm đội"
  , "  reset                   xóa các tàu đã xếp"
  , "  ready                   xác nhận xếp xong"
  , "  fire <ô>                bắn, ví dụ: fire b7 (chỉ gõ b7 cũng được)"
  , "  help / quit"
  , "Tàu: carrier(5) battleship(4) cruiser(3) submarine(3) destroyer(2)"
  , "Ô: chữ A-J là hàng, số 1-10 là cột."
  ]
