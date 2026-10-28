{-# LANGUAGE CPP #-}
-- | Main.hs
--
-- Điểm vào của chương trình. Chỉ có việc đọc tham số dòng lệnh rồi giao cho
-- 'Solo', 'Server' hoặc 'Client'. Toàn bộ phần IO "bẩn" nằm ở rìa như thế này.
module Main (main) where

import Data.List (isPrefixOf, partition)
import Data.Maybe (isJust)
import System.Environment (getArgs, lookupEnv)
import System.Info (os)
import System.IO
import Text.Read (readMaybe)
#if defined(mingw32_HOST_OS)
import Foreign.C.Types (CInt (..), CUInt (..))
#endif

import Client (runClient)
import Render (Theme (..))
import Server (runServer)
import Solo (runSolo)
import WebServer (runWebServer)

defaultPort :: Int
defaultPort = 4000

defaultWebPort :: Int
defaultWebPort = 8080

#if defined(mingw32_HOST_OS)
-- Console Windows mặc định dùng bảng mã cũ nên chữ tiếng Việt UTF-8 bị vỡ
-- ("Tàu" thành "TĂ u"). Gọi thẳng API của Windows để chuyển console sang UTF-8
-- (mã 65001), khỏi bắt người dùng gõ 'chcp 65001'.
foreign import ccall unsafe "windows.h SetConsoleOutputCP"
  c_setConsoleOutputCP :: CUInt -> IO CInt
foreign import ccall unsafe "windows.h SetConsoleCP"
  c_setConsoleCP :: CUInt -> IO CInt

setupConsole :: IO ()
setupConsole = do
  _ <- c_setConsoleOutputCP 65001
  _ <- c_setConsoleCP 65001
  pure ()
#else
setupConsole :: IO ()
setupConsole = pure ()
#endif

main :: IO ()
main = do
  setupConsole
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  hSetEncoding stdin utf8
  hSetBuffering stdout LineBuffering
  args   <- getArgs
  noColr <- isJust <$> lookupEnv "NO_COLOR"
  let (flags, rest) = partition ("--" `isPrefixOf`) args
      -- Console cũ của Windows thường không hiểu mã màu ANSI: mặc định tắt màu ở đó.
      theme
        | "--no-color" `elem` flags || noColr = Plain
        | "--color" `elem` flags              = Color
        | os == "mingw32"                     = Plain
        | otherwise                           = Color
  case rest of
    []                    -> runSolo theme
    ["solo"]              -> runSolo theme
    ["web"]               -> runWebServer defaultWebPort
    ["web", p]            | Just n <- readMaybe p -> runWebServer n
    ["server"]            -> runServer defaultPort
    ["server", p]         | Just n <- readMaybe p -> runServer n
    ["client"]            -> runClient theme "localhost" defaultPort
    ["client", host]      -> runClient theme host defaultPort
    ["client", host, p]   | Just n <- readMaybe p -> runClient theme host n
    _                     -> putStr usage

usage :: String
usage = unlines
  [ "Battleship (Haskell)"
  , ""
  , "Cách dùng:"
  , "  battleship                       chơi với máy (giống 'solo')"
  , "  battleship solo                  chơi với máy"
  , "  battleship web [cổng]             mở giao diện web + WebSocket (mặc định cổng 8080)"
  , "  battleship server [cổng]         mở server TCP cho client console (mặc định cổng 4000)"
  , "  battleship client [host] [cổng]  kết nối tới server (mặc định localhost 4000)"
  , ""
  , "Tùy chọn:  --no-color  tắt màu     --color  ép bật màu"
  ]
