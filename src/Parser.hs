-- | Parser.hs
--
-- Bộ kết hợp phân tích cú pháp (parser combinators) tự viết (Chương 8).
--
-- Ý tưởng: một parser là MỘT HÀM  String -> Maybe (kết quả, phần chuỗi còn lại).
-- Parser nhỏ ghép thành parser lớn bằng các phép toán của Functor,
-- Applicative, Monad và Alternative:
--
--   * '<$>' / '<*>' : chạy lần lượt, gom kết quả
--   * '>>='         : kết quả bước trước quyết định bước sau
--   * '<|>'         : thử bên trái, hỏng thì thử bên phải (có quay lui)
--
-- Lưu ý: '<|>' là lựa chọn THEO THỨ TỰ. Khi một nhánh đã thành công thì
-- không quay lại thử nhánh khác. Vì vậy phải đặt nhánh DÀI trước nhánh ngắn
-- (ví dụ "horizontal" trước "h"), nếu không "h" sẽ ăn mất chữ đầu.
module Parser
  ( -- * Lõi
    Parser
  , runParser
  , parse
  , satisfy
  , char
  , string
  , ciString
  , spaces
  , spaces1
  , digit
  , number
  , sepBy
  , sepBy1
  , choice
  , rest
    -- * Cú pháp của game
  , coordP
  , shipTypeP
  , orientationP
  , commandP
  , parseCommand
  , showCommand
  , showCoord
  ) where

import Control.Applicative
import Control.Monad (guard)
import Data.Char (isDigit, isSpace, toLower, toUpper)

import Types

-- ---------------------------------------------------------------------------
-- Lõi

newtype Parser a = Parser { runParser :: String -> Maybe (a, String) }

instance Functor Parser where
  fmap f (Parser p) = Parser $ \s -> case p s of
    Nothing      -> Nothing
    Just (a, s') -> Just (f a, s')

instance Applicative Parser where
  pure a = Parser $ \s -> Just (a, s)
  Parser pf <*> Parser pa = Parser $ \s -> case pf s of
    Nothing      -> Nothing
    Just (f, s1) -> case pa s1 of
      Nothing      -> Nothing
      Just (a, s2) -> Just (f a, s2)

instance Monad Parser where
  Parser p >>= f = Parser $ \s -> case p s of
    Nothing      -> Nothing
    Just (a, s') -> runParser (f a) s'

instance Alternative Parser where
  empty = Parser (const Nothing)
  Parser p <|> Parser q = Parser $ \s -> case p s of
    Nothing -> q s
    result  -> result

-- | Chạy parser và đòi hỏi phải ăn hết chuỗi.
parse :: Parser a -> String -> Maybe a
parse p s = case runParser p s of
  Just (a, "") -> Just a
  _            -> Nothing

satisfy :: (Char -> Bool) -> Parser Char
satisfy ok = Parser $ \s -> case s of
  (c : cs) | ok c -> Just (c, cs)
  _               -> Nothing

char :: Char -> Parser Char
char c = satisfy (== c)

-- | Khớp đúng chuỗi.
string :: String -> Parser String
string = traverse char

-- | Khớp chuỗi không phân biệt hoa thường.
ciString :: String -> Parser String
ciString str = Parser $ \s ->
  let (pre, post) = splitAt (length str) s
  in if map toLower pre == map toLower str then Just (pre, post) else Nothing

spaces :: Parser ()
spaces = () <$ many (satisfy isSpace)

spaces1 :: Parser ()
spaces1 = () <$ some (satisfy isSpace)

digit :: Parser Char
digit = satisfy isDigit

-- | Số nguyên không âm, tối đa 3 chữ số (tránh tràn số với input lạ).
number :: Parser Int
number = do
  ds <- some digit
  guard (length ds <= 3)
  pure (read ds)

sepBy1 :: Parser a -> Parser b -> Parser [a]
sepBy1 p sep = (:) <$> p <*> many (sep *> p)

sepBy :: Parser a -> Parser b -> Parser [a]
sepBy p sep = sepBy1 p sep <|> pure []

-- | Thử lần lượt các parser, lấy cái đầu tiên thành công.
choice :: [Parser a] -> Parser a
choice = asum

-- | Phần còn lại của dòng.
rest :: Parser String
rest = many (satisfy (const True))

-- ---------------------------------------------------------------------------
-- Cú pháp của game

-- | Ô cờ dạng "B7": chữ cái A-J là hàng, số 1-10 là cột.
coordP :: Parser Coord
coordP = do
  l <- satisfy isRowLetter
  n <- number
  guard (n >= 1 && n <= boardSize)
  pure (Coord (fromEnum (toUpper l) - fromEnum 'A') (n - 1))
  where
    isRowLetter x =
      let u = toUpper x
      in u >= 'A' && fromEnum u < fromEnum 'A' + boardSize

-- | Viết một ô thành chuỗi, ngược với 'coordP'.
showCoord :: Coord -> String
showCoord (Coord r c) = toEnum (fromEnum 'A' + r) : show (c + 1)

-- | Tên tàu, không phân biệt hoa thường. Không tên nào là tiền tố của tên khác
-- nên thứ tự thử không quan trọng ở đây.
shipTypeP :: Parser ShipType
shipTypeP = choice [st <$ ciString (show st) | st <- [minBound .. maxBound]]

-- | Hướng đặt tàu. Nhánh dài đặt trước nhánh ngắn (xem ghi chú đầu file).
orientationP :: Parser Orientation
orientationP = choice
  [ Horizontal <$ ciString "horizontal"
  , Horizontal <$ ciString "ngang"
  , Horizontal <$ ciString "h"
  , Vertical   <$ ciString "vertical"
  , Vertical   <$ ciString "dọc"
  , Vertical   <$ ciString "doc"
  , Vertical   <$ ciString "v"
  ]

-- | Một dòng lệnh của người chơi.
commandP :: Parser Command
commandP = spaces *> choice
  [ Place <$> (ciString "place" *> spaces1 *> shipTypeP)
          <*> (spaces1 *> coordP)
          <*> (spaces1 *> orientationP)
  , Fire <$> (ciString "fire" *> spaces1 *> coordP)
  , Fire <$> coordP                              -- chỉ gõ "b7" cũng được
  , RandomFleet <$ (ciString "random" <|> ciString "auto")
  , Reset       <$ (ciString "reset"  <|> ciString "clear")
  , Ready       <$ (ciString "ready"  <|> ciString "done")
  , Help        <$ (ciString "help"   <|> ciString "?")
  , Quit        <$ (ciString "quit"   <|> ciString "exit")
  ] <* spaces

-- | Phân tích một dòng người dùng gõ; lỗi thì trả câu giải thích thân thiện.
parseCommand :: String -> Either String Command
parseCommand input =
  maybe (Left (explain (words (map toLower input)))) Right
        (parse commandP (map toLower input))
  where
    explain ("place" : _) =
      "Cú pháp: place <tàu> <ô> <h|v>   ví dụ: place carrier a1 h"
    explain ("fire" : _) =
      "Ô không hợp lệ. Dùng chữ A-J và số 1-10, ví dụ: fire b7"
    explain _ = "Không hiểu lệnh. Gõ help để xem hướng dẫn."

-- | Ngược với 'parseCommand' (dùng cho test vòng lặp parse <-> show).
showCommand :: Command -> String
showCommand cmd = case cmd of
  Fire c        -> "fire " ++ showCoord c
  Place st c o  -> unwords ["place", map toLower (show st), showCoord c, orient o]
  RandomFleet   -> "random"
  Reset         -> "reset"
  Ready         -> "ready"
  Help          -> "help"
  Quit          -> "quit"
  where
    orient Horizontal = "h"
    orient Vertical   = "v"
