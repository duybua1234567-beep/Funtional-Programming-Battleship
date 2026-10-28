-- | Client.hs
--
-- Client terminal cho trận qua mạng. Client rất "mỏng": gửi nguyên dòng người
-- dùng gõ lên server, và vẽ lại những gì server gửi về (dùng 'Render').
-- Mọi luật chơi nằm ở server nên client không thể gian lận.
module Client (runClient) where

import Control.Concurrent (ThreadId, forkIO, myThreadId)
import Control.Exception
import Control.Monad (unless)
import Data.IORef
import Network.Socket
import System.Exit (ExitCode (..))
import System.IO

import Parser (parseCommand)
import Protocol (decodeServerMsg)
import Render
import Types

runClient :: Theme -> String -> Int -> IO ()
runClient th host port = do
  h <- connectTo host port
  mainTid <- myThreadId
  meRef   <- newIORef P1
  quitRef <- newIORef False
  _ <- forkIO (receiveLoop th h meRef quitRef mainTid)
  putStrLn ("Đã kết nối tới " ++ host ++ ":" ++ show port ++ ".")
  inputLoop h quitRef

-- | Kết nối TCP. "localhost" có thể phân giải ra cả IPv6 lẫn IPv4 nên thử lần lượt.
connectTo :: String -> Int -> IO Handle
connectTo host port = do
  addrs <- getAddrInfo (Just defaultHints { addrSocketType = Stream })
                       (Just host) (Just (show port))
  sock <- firstSuccess (map open addrs)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  hSetEncoding h utf8
  hSetNewlineMode h noNewlineTranslation
  pure h
  where
    open a = do
      s <- socket (addrFamily a) (addrSocketType a) (addrProtocol a)
      connect s (addrAddress a) `onException` close s
      pure s

firstSuccess :: [IO a] -> IO a
firstSuccess []       = ioError (userError "Không kết nối được tới server.")
firstSuccess [a]      = a
firstSuccess (a : as) = a `catch` \e -> const (firstSuccess as) (e :: IOException)

-- | Luồng nhận: đọc từng dòng từ server, giải mã và in ra.
receiveLoop :: Theme -> Handle -> IORef Player -> IORef Bool -> ThreadId -> IO ()
receiveLoop th h meRef quitRef mainTid = loop
  where
    loop = do
      r <- try (hGetLine h) :: IO (Either IOException String)
      case r of
        Left _     -> lost
        Right line -> handleLine line >> loop

    handleLine line = case decodeServerMsg line of
      Nothing  -> putStrLn ("[server] " ++ line)
      Just msg -> do
        case msg of
          SWelcome p -> writeIORef meRef p
          _          -> pure ()
        me <- readIORef meRef
        mapM_ putStrLn (renderMsg th me msg)

    lost = do
      quitting <- readIORef quitRef
      unless quitting $ do
        putStrLn "Mất kết nối với server."
        hFlush stdout
        throwTo mainTid ExitSuccess

-- | Luồng chính: đọc dòng người dùng gõ và gửi lên server.
inputLoop :: Handle -> IORef Bool -> IO ()
inputLoop h quitRef = do
  eof <- isEOF
  if eof then hClose h else do
    line <- getLine
    r <- try (hPutStrLn h line) :: IO (Either IOException ())
    case r of
      Left _  -> putStrLn "Không gửi được lệnh (mất kết nối)."
      Right () -> case parseCommand line of
        Right Quit -> do
          writeIORef quitRef True
          putStrLn "Tạm biệt!"
          hClose h
        _ -> inputLoop h quitRef
