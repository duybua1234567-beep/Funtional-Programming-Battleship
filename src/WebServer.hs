{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module WebServer (runWebServer) where

import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception
import Control.Monad
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import Network.HTTP.Types (status200, status404)
import Network.Wai
import Network.Wai.Handler.Warp (defaultSettings, setPort, setHost, runSettings)
import Network.Wai.Handler.WebSockets (websocketsOr)
import Network.WebSockets
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import Parser (parseCommand)
import Protocol (encodeServerMsg)
import Rng (freshSeed)
import Session
import Types

type Pending = (Connection, MVar ())

runWebServer :: Int -> IO ()
runWebServer port = do
  waiting <- newChan
  _ <- forkIO (pairPlayers waiting)
  let wsApp = handleConnection waiting
      httpApp req respond
        | pathInfo req == ["ws"] = respond (responseLBS status404 [] "WebSocket endpoint only")
        | pathInfo req == [] || pathInfo req == ["index.html"] = do
            let file = "web" </> "index.html"
            exists <- doesFileExist file
            if exists
              then do
                body <- BL.readFile file
                respond (responseLBS status200 [("Content-Type", "text/html; charset=utf-8")] body)
              else respond (responseLBS status404 [("Content-Type", "text/plain; charset=utf-8")] "Không tìm thấy web/index.html. Hãy chạy server từ thư mục gốc battleship.")
        | otherwise = respond (responseLBS status404 [("Content-Type", "text/plain; charset=utf-8")] "Not found")
      app = websocketsOr defaultConnectionOptions wsApp httpApp
      settings = setPort port (setHost "0.0.0.0" defaultSettings)
  putStrLn ("Battleship Web Server đang chạy tại http://0.0.0.0:" ++ show port)
  putStrLn "Mở URL này trên máy chủ, hoặc dùng IPv4 của máy chủ trên thiết bị khác trong cùng LAN."
  putStrLn "Nhấn Ctrl+C để dừng."
  runSettings settings app

handleConnection :: Chan Pending -> ServerApp
handleConnection waiting pending = do
  conn <- acceptRequest pending
  done <- newEmptyMVar
  writeChan waiting (conn, done)
  putStrLn "Một trình duyệt đã kết nối WebSocket; đang chờ ghép trận."
  takeMVar done

pairPlayers :: Chan Pending -> IO ()
pairPlayers waiting = forever $ do
  first <- readChan waiting
  firstAlive <- probePending first
  if not firstAlive
    then finishPending first
    else do
      second <- readChan waiting
      firstStillAlive <- probePending first
      secondAlive <- probePending second
      if firstStillAlive && secondAlive
        then do
          putStrLn "Đã ghép hai người chơi."
          _ <- forkIO $ (runMatchWS (fst first) (fst second))
                `catch` (\e -> putStrLn ("Lỗi trận đấu: " ++ show (e :: SomeException)))
                `finally` (finishPending first >> finishPending second)
          pure ()
        else do
          unless firstStillAlive (finishPending first)
          unless secondAlive (finishPending second)
          when firstStillAlive (writeChan waiting first)
          when secondAlive (writeChan waiting second)

probePending :: Pending -> IO Bool
probePending (conn, _) = do
  result <- try (sendTextData conn (T.pack "INFO Đang kiểm tra kết nối trước khi ghép trận..."))
    :: IO (Either SomeException ())
  pure (case result of
    Left _ -> False
    Right _ -> True)

finishPending :: Pending -> IO ()
finishPending (_, done) = void (tryPutMVar done ())

runMatchWS :: Connection -> Connection -> IO ()
runMatchWS c1 c2 = do
  seed <- freshSeed
  roomVar <- newTVarIO (initialRoom seed)
  q1 <- newTQueueIO
  q2 <- newTQueueIO
  let queues = Map.fromList [(P1, q1), (P2, q2)]
  atomically $ do
    writeTQueue q1 (SWelcome P1)
    writeTQueue q1 (SInfo "Đã ghép trận. Hãy xếp tàu.")
    writeTQueue q1 (SView (viewFor P1 (initialRoom seed)))
    writeTQueue q2 (SWelcome P2)
    writeTQueue q2 (SInfo "Đã ghép trận. Hãy xếp tàu.")
    writeTQueue q2 (SView (viewFor P2 (initialRoom seed)))
  done <- newEmptyMVar
  tids <- sequence
    [ forkIO (writer c1 q1)
    , forkIO (writer c2 q2)
    , forkIO (reader P1 c1 roomVar queues done)
    , forkIO (reader P2 c2 roomVar queues done)
    ]
  takeMVar done
  threadDelay 250000
  mapM_ killThread tids
  putStrLn "Trận WebSocket kết thúc; chờ cặp tiếp theo."

writer :: Connection -> TQueue ServerMsg -> IO ()
writer conn queue = forever $ do
  msg <- atomically (readTQueue queue)
  sendTextData conn (T.pack (encodeServerMsg msg))

reader :: Player -> Connection -> TVar Room -> Map.Map Player (TQueue ServerMsg) -> MVar () -> IO ()
reader p conn roomVar queues done =
  (loop `catch` (\(_ :: SomeException) -> pure ())) `finally` (void (tryPutMVar done ()))
  where
    loop = do
      raw <- receiveData conn :: IO T.Text
      case parseCommand (T.unpack raw) of
        Left err -> atomically (tell p (SError err)) >> loop
        Right Quit -> pure ()
        Right cmd -> do
          over <- atomically $ do
            room <- readTVar roomVar
            let (room', outs) = stepRoom p cmd room
            writeTVar roomVar room'
            forM_ outs (uncurry tell)
            isOver <$> readTVar roomVar
          unless over loop
    tell to msg = forM_ (Map.lookup to queues) (`writeTQueue` msg)
