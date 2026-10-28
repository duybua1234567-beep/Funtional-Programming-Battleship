-- | Server.hs
--
-- Server TCP cho trận 2 người (Chương 9: đa tiến trình, socket; Chương 8: STM).
--
-- Mỗi trận gồm: 2 client kết nối -> chơi -> kết thúc -> server quay lại chờ
-- cặp người chơi tiếp theo.
--
-- Sơ đồ luồng (thread) cho một trận:
--
--     client 1 <--socket--> [reader P1] --+            +--> [writer P1] --> client 1
--                                         |  TVar Room |
--     client 2 <--socket--> [reader P2] --+            +--> [writer P2] --> client 2
--
--   * Mỗi người chơi có một luồng ĐỌC (đọc lệnh, cập nhật Room) và một luồng
--     GHI (lấy thông điệp từ hàng đợi rồi gửi đi).
--   * Trạng thái chung nằm trong một 'TVar Room'. Cập nhật nó bằng STM nên hai
--     người gõ lệnh cùng lúc cũng không làm hỏng trạng thái (không cần khóa
--     thủ công, không lo deadlock).
--   * Luật chơi KHÔNG nằm ở đây: server chỉ gọi hàm thuần 'Session.stepRoom'.
module Server (runServer) where

import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception
import Control.Monad
import qualified Data.Map.Strict as Map
import Network.Socket
import System.IO

import Parser (parseCommand)
import Protocol (encodeServerMsg)
import Rng (freshSeed)
import Session
import Types

type Queues = Map.Map Player (TQueue ServerMsg)

-- | Mở cổng và phục vụ các trận liên tiếp, mãi mãi.
runServer :: Int -> IO ()
runServer port = do
  sock <- listenOn port
  putStrLn ("Server Battleship đang lắng nghe ở cổng " ++ show port ++ ". Nhấn Ctrl+C để dừng.")
  forever (runMatch sock)

listenOn :: Int -> IO Socket
listenOn port = do
  sock <- socket AF_INET Stream defaultProtocol
  setSocketOption sock ReuseAddr 1
  bind sock (SockAddrInet (fromIntegral port) 0)
  listen sock 4
  pure sock

acceptPlayer :: Socket -> Player -> IO Handle
acceptPlayer sock p = do
  (conn, addr) <- accept sock
  h <- socketToHandle conn ReadWriteMode
  hSetBuffering h LineBuffering
  hSetEncoding h utf8
  hSetNewlineMode h noNewlineTranslation
  putStrLn (show p ++ " đã kết nối từ " ++ show addr)
  pure h

sendNow :: Handle -> ServerMsg -> IO ()
sendNow h = hPutStrLn h . encodeServerMsg

-- | Một trận đấu từ lúc đủ hai người đến lúc kết thúc.
runMatch :: Socket -> IO ()
runMatch sock = do
  h1 <- acceptPlayer sock P1
  sendNow h1 (SWelcome P1)
  sendNow h1 (SInfo "Đang chờ đối thủ kết nối...")
  h2 <- acceptPlayer sock P2
  sendNow h2 (SWelcome P2)

  seed    <- freshSeed
  roomVar <- newTVarIO (initialRoom seed)
  q1 <- newTQueueIO
  q2 <- newTQueueIO
  let queues = Map.fromList [(P1, q1), (P2, q2)]
  done <- newEmptyMVar

  atomically $ forM_ players $ \p ->
    forM_ (Map.lookup p queues) $ \q -> do
      writeTQueue q (SInfo "Đã đủ hai người chơi. Hãy xếp tàu!")
      room <- readTVar roomVar
      writeTQueue q (SView (viewFor p room))

  tids <- sequence
    [ forkIO (writer h1 q1)
    , forkIO (writer h2 q2)
    , forkIO (reader P1 h1 roomVar queues done)
    , forkIO (reader P2 h2 roomVar queues done)
    ]

  takeMVar done                    -- chờ cho tới khi trận kết thúc
  threadDelay 300000               -- cho luồng ghi kịp gửi thông điệp cuối
  mapM_ killThread tids
  mapM_ (\h -> hClose h `catch` ignoreIO) [h1, h2]
  putStrLn "Trận đấu kết thúc. Đang chờ cặp người chơi tiếp theo..."

-- | Luồng ghi: lấy thông điệp từ hàng đợi và gửi cho client.
writer :: Handle -> TQueue ServerMsg -> IO ()
writer h q = forever $ do
  msg <- atomically (readTQueue q)
  sendNow h msg `catch` ignoreIO

-- | Luồng đọc của một người chơi.
reader :: Player -> Handle -> TVar Room -> Queues -> MVar () -> IO ()
reader p h roomVar queues done = (loop `catch` ignoreIO) `finally` farewell
  where
    loop = do
      line <- hGetLine h
      case parseCommand line of
        Left err       -> atomically (tell p (SError err)) >> loop
        Right Quit     -> pure ()
        Right cmd      -> do
          over <- atomically $ do
            dispatch cmd
            isOver <$> readTVar roomVar
          unless over loop

    -- Một giao dịch STM: chạy hàm thuần rồi đẩy thông điệp vào hàng đợi.
    dispatch cmd = do
      room <- readTVar roomVar
      let (room', outs) = stepRoom p cmd room
      writeTVar roomVar room'
      forM_ outs (uncurry tell)

    tell to msg = forM_ (Map.lookup to queues) (`writeTQueue` msg)

    farewell = do
      atomically $ do
        room <- readTVar roomVar
        unless (isOver room) $
          tell (other p) (SInfo "Đối thủ đã thoát. Ván đấu kết thúc.")
      void (tryPutMVar done ())

ignoreIO :: IOException -> IO ()
ignoreIO _ = pure ()
