-- | Protocol.hs
--
-- Giao thức mạng: mỗi 'ServerMsg' là MỘT DÒNG văn bản.
--
--   WELCOME P1
--   INFO <văn bản>
--   ERROR <văn bản>
--   SHOT P1 B7 MISS            (hoặc HIT, hoặc SUNK:Carrier)
--   OVER P1
--   VIEW|<phase>|<lượt>|<tàu của bạn>|<ô đã bị bắn>|<bàn địch>
--
-- Phần giải mã dùng lại chính bộ parser combinators ở "Parser". Ta kiểm tra
-- bằng QuickCheck rằng  decode (encode m) == Just m  với mọi thông điệp m.
--
-- Chiều client -> server không cần định dạng riêng: client gửi thẳng dòng
-- người dùng gõ và server tự phân tích bằng 'Parser.parseCommand'.
module Protocol
  ( encodeServerMsg
  , decodeServerMsg
  ) where

import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Parser
import Types

-- ---------------------------------------------------------------------------
-- Mã hóa

encodeServerMsg :: ServerMsg -> String
encodeServerMsg msg = case msg of
  SWelcome p   -> "WELCOME " ++ show p
  SInfo s      -> "INFO " ++ oneLine s
  SError s     -> "ERROR " ++ oneLine s
  SShot p c r  -> unwords ["SHOT", show p, showCoord c, encodeResult r]
  SGameOver p  -> "OVER " ++ show p
  SView v      -> encodeView v

-- | Xuống dòng sẽ phá giao thức "một thông điệp một dòng", nên bỏ đi.
oneLine :: String -> String
oneLine = map (\c -> if c == '\n' || c == '\r' then ' ' else c)

encodeResult :: ShotResult -> String
encodeResult Miss     = "MISS"
encodeResult Hit      = "HIT"
encodeResult (Sunk s) = "SUNK:" ++ show s

encodeView :: View -> String
encodeView (View ph tn own (PublicBoard pm)) =
  intercalate "|" ["VIEW", phase, turn, ships, shots, enemy]
  where
    phase = case ph of
      Placing -> "placing"
      Playing -> "playing"
      Over p  -> "over:" ++ show p
    turn  = maybe "-" show tn
    ships = intercalate ";"
      [ show st ++ ":" ++ coords cs | (st, cs) <- Map.toList (bShips own) ]
    shots = coords (bShots own)
    enemy = intercalate ","
      [ showCoord c ++ "=" ++ cell x | (c, x) <- Map.toList pm ]
    coords = intercalate "," . map showCoord . Set.toList
    cell PMiss      = "miss"
    cell PHit       = "hit"
    cell (PSunk st) = "sunk:" ++ show st

-- ---------------------------------------------------------------------------
-- Giải mã

decodeServerMsg :: String -> Maybe ServerMsg
decodeServerMsg = parse serverMsgP

serverMsgP :: Parser ServerMsg
serverMsgP = choice
  [ SWelcome  <$> (string "WELCOME " *> playerP)
  , SInfo     <$> (string "INFO "    *> rest)
  , SError    <$> (string "ERROR "   *> rest)
  , SShot     <$> (string "SHOT " *> playerP)
              <*> (char ' ' *> coordP)
              <*> (char ' ' *> resultP)
  , SGameOver <$> (string "OVER " *> playerP)
  , SView     <$> viewP
  ]

playerP :: Parser Player
playerP = choice [P1 <$ string "P1", P2 <$ string "P2"]

resultP :: Parser ShotResult
resultP = choice
  [ Miss <$ string "MISS"
  , Hit  <$ string "HIT"
  , Sunk <$> (string "SUNK:" *> shipTypeP)
  ]

viewP :: Parser View
viewP = do
  _     <- string "VIEW|"
  ph    <- phaseP
  _     <- char '|'
  tn    <- turnP
  _     <- char '|'
  ships <- shipsP
  _     <- char '|'
  shots <- coordsP
  _     <- char '|'
  enemy <- enemyP
  pure (View ph tn (Board ships shots) (PublicBoard enemy))

phaseP :: Parser Phase
phaseP = choice
  [ Placing <$ string "placing"
  , Playing <$ string "playing"
  , Over    <$> (string "over:" *> playerP)
  ]

turnP :: Parser (Maybe Player)
turnP = choice [Nothing <$ char '-', Just <$> playerP]

coordsP :: Parser (Set.Set Coord)
coordsP = Set.fromList <$> sepBy coordP (char ',')

shipsP :: Parser (Map.Map ShipType (Set.Set Coord))
shipsP = Map.fromList <$> sepBy entry (char ';')
  where
    entry = (,) <$> shipTypeP <*> (char ':' *> coordsP)

enemyP :: Parser (Map.Map Coord PublicCell)
enemyP = Map.fromList <$> sepBy entry (char ',')
  where
    entry = (,) <$> coordP <*> (char '=' *> cellP)
    cellP = choice
      [ PMiss <$ string "miss"
      , PHit  <$ string "hit"
      , PSunk <$> (string "sunk:" *> shipTypeP)
      ]
