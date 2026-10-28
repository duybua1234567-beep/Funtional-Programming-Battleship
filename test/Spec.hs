{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}
-- | Spec.hs
--
-- Kiểm thử dựa trên THUỘC TÍNH (QuickCheck). Thay vì viết vài ví dụ cố định,
-- ta phát biểu một quy luật "với mọi đầu vào thì ... đúng" và để QuickCheck tự
-- sinh hàng trăm đầu vào ngẫu nhiên để tìm phản ví dụ. Cách này chỉ khả thi
-- vì lõi game là hàm thuần: cùng đầu vào luôn cho cùng kết quả.
module Main (main) where

import Control.Monad (unless)
import Data.Char (toUpper)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word64)
import System.Exit (exitFailure)
import System.IO (hSetEncoding, stdout, utf8)
import Test.QuickCheck

import AI
import Engine
import Parser
import Protocol
import Rng
import Session
import Types

-- ---------------------------------------------------------------------------
-- Bộ sinh dữ liệu ngẫu nhiên

instance Arbitrary ShipType where arbitrary = arbitraryBoundedEnum
instance Arbitrary Orientation where arbitrary = arbitraryBoundedEnum
instance Arbitrary Player where arbitrary = arbitraryBoundedEnum

-- | Ô bất kỳ, kể cả ô NGOÀI bàn cờ (để thử các trường hợp biên).
instance Arbitrary Coord where
  arbitrary = Coord <$> choose (-1, boardSize) <*> choose (-1, boardSize)

-- | Ô hợp lệ trong bàn cờ.
genCoord :: Gen Coord
genCoord = Coord <$> choose (0, boardSize - 1) <*> choose (0, boardSize - 1)

genResult :: Gen ShotResult
genResult = oneof [pure Miss, pure Hit, Sunk <$> arbitrary]

genCell :: Gen PublicCell
genCell = oneof [pure PMiss, pure PHit, PSunk <$> arbitrary]

genCommand :: Gen Command
genCommand = oneof
  [ Fire <$> genCoord
  , Place <$> arbitrary <*> genCoord <*> arbitrary
  , elements [RandomFleet, Reset, Ready, Help, Quit]
  ]

genBoard :: Gen Board
genBoard = do
  seed  <- arbitrary
  shots <- listOf genCoord
  pure (evalState randomBoard seed) { bShots = Set.fromList shots }

genPublic :: Gen PublicBoard
genPublic = PublicBoard . Map.fromList <$> listOf ((,) <$> genCoord <*> genCell)

genPhase :: Gen Phase
genPhase = oneof [pure Placing, pure Playing, Over <$> arbitrary]

genView :: Gen View
genView = View <$> genPhase
               <*> oneof [pure Nothing, Just <$> arbitrary]
               <*> genBoard
               <*> genPublic

-- | Văn bản một dòng, có cả ký tự đặc biệt của giao thức và chữ tiếng Việt.
genText :: Gen String
genText = listOf (elements (['a' .. 'z'] ++ ['A' .. 'Z'] ++ " |:;,=ăâêôơưđ"))

genMsg :: Gen ServerMsg
genMsg = oneof
  [ SWelcome <$> arbitrary
  , SInfo <$> genText
  , SError <$> genText
  , SView <$> genView
  , SShot <$> arbitrary <*> genCoord <*> genResult
  , SGameOver <$> arbitrary
  ]

-- ---------------------------------------------------------------------------
-- Engine

prop_shipCellsLength :: ShipType -> Coord -> Orientation -> Bool
prop_shipCellsLength st c o = length (shipCells st c o) == shipSize st

-- | Đặt tàu theo bất kỳ chuỗi yêu cầu nào (kể cả sai luật): bàn cờ luôn hợp
-- lệ, tàu không chồng nhau và không ra ngoài.
prop_placementKeepsInvariant :: [(ShipType, Coord, Orientation)] -> Bool
prop_placementKeepsInvariant reqs = valid (foldl step emptyBoard reqs)
  where
    step b (st, c, o) = either (const b) id (placeShip st c o b)
    valid b = all inBounds (Set.toList (occupied b))
           && Set.size (occupied b) == sum [shipSize st | st <- Map.keys (bShips b)]

prop_randomBoardIsValid :: Word64 -> Bool
prop_randomBoardIsValid seed =
  fleetComplete b && Set.size (occupied b) == 17 && all inBounds (Set.toList (occupied b))
  where b = evalState randomBoard seed

prop_cannotShootTwice :: Word64 -> Property
prop_cannotShootTwice seed = forAll genCoord $ \c ->
  case receiveShot c (evalState randomBoard seed) of
    Left _        -> False
    Right (_, b') -> fmap fst (receiveShot c b') == Left FireAlreadyShot

-- | Bàn công khai chỉ chứa ĐÚNG những ô đã bị bắn, không hơn, không kém.
prop_publicViewOnlyShotCells :: Property
prop_publicViewOnlyShotCells = forAll genBoard $ \b ->
  let PublicBoard m = publicView b
  in Map.keysSet m == bShots b

-- ---------------------------------------------------------------------------
-- Parser và giao thức

prop_commandRoundTrip :: Property
prop_commandRoundTrip = forAll genCommand $ \c ->
  parseCommand (showCommand c) == Right c

prop_commandCaseInsensitive :: Property
prop_commandCaseInsensitive = forAll genCommand $ \c ->
  parseCommand (map toUpper (showCommand c)) == Right c

prop_garbageNeverCrashes :: String -> Bool
prop_garbageNeverCrashes s = case parseCommand s of
  Left _  -> True
  Right _ -> True

prop_protocolRoundTrip :: Property
prop_protocolRoundTrip = forAll genMsg $ \m ->
  decodeServerMsg (encodeServerMsg m) == Just m

-- ---------------------------------------------------------------------------
-- AI

-- | Có một ô trúng đơn độc thì AI phải bắn vào ô kề nó.
prop_aiTargetsNeighbour :: Word64 -> Property
prop_aiTargetsNeighbour seed = forAll genCoord $ \c ->
  let (shot, _) = chooseShot (PublicBoard (Map.singleton c PHit)) seed
      dist = abs (cRow shot - cRow c) + abs (cCol shot - cCol c)
  in dist == 1

-- ---------------------------------------------------------------------------
-- Cả một ván đấu qua Session: hai AI đấu với nhau

data Sim = Sim { simRoom :: Room, simOuts :: [Outgoing], simSteps :: Int }

-- | Phòng đã xếp tàu ngẫu nhiên và cả hai đã ready.
startedRoom :: Word64 -> Room
startedRoom seed = foldl (\r (p, c) -> fst (stepRoom p c r)) (initialRoom seed)
  [(P1, RandomFleet), (P1, Ready), (P2, RandomFleet), (P2, Ready)]

simulate :: Word64 -> Sim
simulate seed = go (Sim (startedRoom seed) [] 0) (seed * 7 + 3)
  where
    go s aiSeed
      | isOver (simRoom s) || simSteps s > 300 = s
      | otherwise = case rGame (simRoom s) of
          Nothing -> s
          Just g ->
            let p              = gTurn g
                (c, aiSeed')   = chooseShot (vEnemy (viewFor p (simRoom s))) aiSeed
                (room', outs)  = stepRoom p (Fire c) (simRoom s)
            in go (Sim room' (simOuts s ++ outs) (simSteps s + 1)) aiSeed'

-- | Ván đấu luôn kết thúc, trong tối đa 200 phát bắn (mỗi bên 100 ô).
prop_gameTerminates :: Word64 -> Bool
prop_gameTerminates seed = let s = simulate seed in isOver (simRoom s) && simSteps s <= 200

-- | AI không bao giờ bắn trùng ô hay ra ngoài bàn (nếu có thì Session đã trả SError).
prop_noErrorsInGame :: Word64 -> Bool
prop_noErrorsInGame seed = null [() | (_, SError _) <- simOuts (simulate seed)]

-- | Mỗi người nhận đúng một thông báo kết thúc, cùng một người thắng, và
-- người thắng đã đánh chìm hết tàu đối phương.
prop_exactlyOneWinner :: Word64 -> Bool
prop_exactlyOneWinner seed =
  case rGame (simRoom s) of
    Nothing -> False
    Just g  ->
      let winners = [(to, w) | (to, SGameOver w) <- simOuts s]
      in case winner g of
           Nothing -> False
           Just w  -> map fst winners == players
                   && all ((== w) . snd) winners
                   && allSunk (boardOf (other w) g)
                   && not (allSunk (boardOf w g))
  where s = simulate seed

-- | Quyền riêng tư: ở MỌI thời điểm, thứ người chơi thấy về bàn đối thủ đúng
-- bằng tập ô đã bị bắn, không có thông tin nào về tàu chưa trúng.
prop_viewNeverLeaks :: Word64 -> Bool
prop_viewNeverLeaks seed = all ok players
  where
    room = simRoom (simulate seed)
    ok p = case rGame room of
      Nothing -> False
      Just g  -> let PublicBoard m = vEnemy (viewFor p room)
                 in Map.keysSet m == bShots (boardOf (other p) g)

-- | Khi đang xếp tàu, đối thủ hoàn toàn trống (chưa có gì để lộ).
prop_noLeakWhilePlacing :: Word64 -> Bool
prop_noLeakWhilePlacing seed = Map.null m && vPhase v == Placing
  where
    (room, _) = stepRoom P2 RandomFleet (initialRoom seed)
    v = viewFor P1 room
    PublicBoard m = vEnemy v

prop_cannotFireOutOfTurn :: Word64 -> Bool
prop_cannotFireOutOfTurn seed =
  let room = startedRoom seed       -- người chơi 1 đi trước
      (room', outs) = stepRoom P2 (Fire (Coord 0 0)) room
  in not (null [() | (P2, SError _) <- outs]) && rGame room' == rGame room

prop_cannotFireBeforeStart :: Word64 -> Bool
prop_cannotFireBeforeStart seed =
  let (_, outs) = stepRoom P1 (Fire (Coord 0 0)) (initialRoom seed)
  in not (null [() | (_, SError _) <- outs])

-- ---------------------------------------------------------------------------
-- Chạy

run :: Testable p => String -> p -> IO Bool
run name p = do
  putStr (name ++ ": ")
  r <- quickCheckWithResult stdArgs { maxSuccess = 200 } p
  pure (isSuccess r)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  results <- sequence
    [ run "Engine: tàu có đúng độ dài"                prop_shipCellsLength
    , run "Engine: đặt tàu luôn giữ bàn cờ hợp lệ"    prop_placementKeepsInvariant
    , run "Engine: xếp ngẫu nhiên luôn hợp lệ"        prop_randomBoardIsValid
    , run "Engine: không bắn trùng một ô được"        prop_cannotShootTwice
    , run "Engine: bàn công khai chỉ gồm ô đã bắn"    prop_publicViewOnlyShotCells
    , run "Parser: show rồi parse ra đúng lệnh cũ"    prop_commandRoundTrip
    , run "Parser: không phân biệt hoa thường"        prop_commandCaseInsensitive
    , run "Parser: chuỗi rác không làm sập"           prop_garbageNeverCrashes
    , run "Protocol: encode rồi decode ra đúng tin"   prop_protocolRoundTrip
    , run "AI: có ô trúng thì bắn ô kề"               prop_aiTargetsNeighbour
    , run "Session: ván đấu luôn kết thúc"            prop_gameTerminates
    , run "Session: không phát sinh lỗi trong ván"    prop_noErrorsInGame
    , run "Session: đúng một người thắng"             prop_exactlyOneWinner
    , run "Session: không lộ vị trí tàu"              prop_viewNeverLeaks
    , run "Session: lúc xếp tàu đối thủ trống"        prop_noLeakWhilePlacing
    , run "Session: không bắn sai lượt được"          prop_cannotFireOutOfTurn
    , run "Session: không bắn trước khi bắt đầu"      prop_cannotFireBeforeStart
    ]
  unless (and results) exitFailure
