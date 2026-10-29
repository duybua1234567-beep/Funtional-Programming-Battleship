{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module WebServer (runWebServer) where

import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception
import Control.Monad
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as BL
import Text.Read (readMaybe)
import Network.HTTP.Types (status200, status404)
import Network.Socket (SockAddr(..), hostAddressToTuple)
import Network.Wai
import Network.Wai.Handler.Warp (defaultSettings, setPort, setHost, runSettings)
import Network.Wai.Handler.WebSockets (websocketsOr)
import Network.WebSockets
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile)
import System.FilePath ((</>))
import Data.Time (getCurrentTime, formatTime, defaultTimeLocale)

import Parser (parseCommand)
import Protocol (encodeServerMsg)
import Rng (freshSeed)
import Session
import Types

type Pending = (Connection, MVar (), String)

data SavedMatch = SavedMatch
  { savedRoom :: Room
  , savedP1IP :: String
  , savedP2IP :: String
  } deriving (Read, Show)

runWebServer :: Int -> IO ()
runWebServer port = do
  waiting <- newChan
  peerIPs <- newChan
  historyLock <- newMVar ()
  savedMatchVar <- newMVar Nothing
  let historyFile = "data" </> "match-history.log"
      activeFile = "data" </> "active-match.txt"
  createDirectoryIfMissing True "data"
  historyExists <- doesFileExist historyFile
  unless historyExists (writeFile historyFile "")
  historyText <- withMVar historyLock (\_ -> do
    contents <- readFile historyFile
    _ <- evaluate (length contents)
    pure contents)
  activeExists <- doesFileExist activeFile
  saved <- if activeExists then do
      raw <- readFile activeFile
      _ <- evaluate (length raw)
      pure (readMaybe raw :: Maybe SavedMatch)
    else pure Nothing
  modifyMVar_ savedMatchVar (const (pure saved))
  putStrLn ("Đã nạp lịch sử từ tệp: " ++ show (length (lines historyText)) ++ " dòng.")
  case saved of
    Just match -> putStrLn ("Đã khôi phục trạng thái trận đang chơi. Chờ hai máy có IP " ++ savedP1IP match ++ " và " ++ savedP2IP match ++ " kết nối lại.")
    Nothing -> putStrLn "Không có trận đang chơi cần khôi phục."
  _ <- forkIO (pairPlayers historyFile historyLock activeFile savedMatchVar waiting)
  let wsApp = handleConnection waiting peerIPs savedMatchVar
      httpApp req respond
        | pathInfo req == ["ws"] = respond (responseLBS status404 [] "WebSocket endpoint only")
        | pathInfo req == ["history"] = do
            result <- try (withMVar historyLock (\_ -> do
              contents <- readFile historyFile
              _ <- evaluate (length contents)
              pure contents))
              :: IO (Either IOException String)
            case result of
              Left _ -> respond (responseLBS status404 [("Content-Type", "text/plain; charset=utf-8")] "Chưa có lịch sử trận đấu.")
              Right contents -> respond (responseLBS status200 [("Content-Type", "text/plain; charset=utf-8")] (BL.fromStrict (TE.encodeUtf8 (T.pack contents))))
        | pathInfo req == [] || pathInfo req == ["index.html"] = do
            let file = "web" </> "index.html"
            exists <- doesFileExist file
            if exists
              then do
                body <- BL.readFile file
                respond (responseLBS status200 [("Content-Type", "text/html; charset=utf-8")] body)
              else respond (responseLBS status404 [("Content-Type", "text/plain; charset=utf-8")] "Không tìm thấy web/index.html. Hãy chạy server từ thư mục gốc battleship.")
        | otherwise = respond (responseLBS status404 [("Content-Type", "text/plain; charset=utf-8")] "Not found")
      baseApp = websocketsOr defaultConnectionOptions wsApp httpApp
      app req respond = do
        when (pathInfo req == ["ws"]) (writeChan peerIPs (peerIp (remoteHost req)))
        baseApp req respond
      settings = setPort port (setHost "0.0.0.0" defaultSettings)
  putStrLn ("Battleship Web Server đang chạy tại http://0.0.0.0:" ++ show port)
  putStrLn "Nếu server bị tắt giữa trận, hãy khởi động lại và cho đúng hai máy kết nối lại bằng IP LAN cũ."
  putStrLn "Nhấn Ctrl+C để dừng."
  runSettings settings app

peerIp :: SockAddr -> String
peerIp addr = case addr of
  SockAddrInet _ host -> show (hostAddressToTuple host)
  SockAddrInet6 _ _ host _ -> show host
  SockAddrUnix path -> path
  _ -> show addr

handleConnection :: Chan Pending -> Chan String -> MVar (Maybe SavedMatch) -> ServerApp
handleConnection waiting peerIPs savedMatchVar pending = do
  conn <- acceptRequest pending
  ip <- readChan peerIPs
  done <- newEmptyMVar
  saved <- readMVar savedMatchVar
  case saved of
    Just match | ip /= savedP1IP match && ip /= savedP2IP match -> do
      sendTextData conn (T.pack "INFO Đang có ván đấu cần khôi phục. Hãy kết nối bằng đúng hai máy đã tham gia ván trước.")
      finishPending (conn, done, ip)
    _ -> writeChan waiting (conn, done, ip)
  takeMVar done

pairPlayers :: FilePath -> MVar () -> FilePath -> MVar (Maybe SavedMatch) -> Chan Pending -> IO ()
pairPlayers historyFile historyLock activeFile savedMatchVar waiting = forever $ do
  first <- readChan waiting
  firstAlive <- probePending first
  if not firstAlive
    then finishPending first
    else do
      second <- readChan waiting
      firstStillAlive <- probePending first
      secondAlive <- probePending second
      saved <- readMVar savedMatchVar
      if not firstStillAlive
        then do
          finishPending first
          when secondAlive (writeChan waiting second)
        else if not secondAlive
          then do
            finishPending second
            writeChan waiting first
          else case saved of
            Just match
              | pendingIP first == pendingIP second -> do
                  finishPending second
                  writeChan waiting first
              | isExpectedPair match (pendingIP first) (pendingIP second) -> do
                  let (p1Pending, p2Pending) = if pendingIP first == savedP1IP match then (first, second) else (second, first)
                  putStrLn "Hai máy đã kết nối lại đúng IP; đang khôi phục ván đấu đã lưu."
                  launchMatch (savedRoom match) (pendingIP p1Pending) (pendingIP p2Pending) p1Pending p2Pending
              | otherwise -> do
                  finishPending second
                  writeChan waiting first
            Nothing -> do
              seed <- freshSeed
              let room = initialRoom seed
                  match = SavedMatch room (pendingIP first) (pendingIP second)
              saveActiveMatch activeFile savedMatchVar match
              putStrLn "Đã ghép hai người chơi mới."
              launchMatch room (pendingIP first) (pendingIP second) first second
  where
    launchMatch room ip1 ip2 p1 p2 = do
      _ <- forkIO $ (runMatchWS historyFile historyLock activeFile savedMatchVar room ip1 ip2 (pendingConn p1) (pendingConn p2))
            `catch` (\e -> putStrLn ("Lỗi trận đấu: " ++ show (e :: SomeException)))
            `finally` (finishPending p1 >> finishPending p2)
      pure ()

pendingConn :: Pending -> Connection
pendingConn (conn, _, _) = conn

pendingIP :: Pending -> String
pendingIP (_, _, ip) = ip

isExpectedPair :: SavedMatch -> String -> String -> Bool
isExpectedPair match ip1 ip2 =
  (ip1 == savedP1IP match && ip2 == savedP2IP match) ||
  (ip2 == savedP1IP match && ip1 == savedP2IP match)

probePending :: Pending -> IO Bool
probePending (conn, _, _) = do
  result <- try (sendTextData conn (T.pack "INFO Đang kiểm tra kết nối trước khi ghép trận..."))
    :: IO (Either SomeException ())
  pure (case result of
    Left _ -> False
    Right _ -> True)

finishPending :: Pending -> IO ()
finishPending (_, done, _) = void (tryPutMVar done ())

runMatchWS :: FilePath -> MVar () -> FilePath -> MVar (Maybe SavedMatch) -> Room -> String -> String -> Connection -> Connection -> IO ()
runMatchWS historyFile historyLock activeFile savedMatchVar initial p1IP p2IP c1 c2 = do
  appendHistory historyFile historyLock ("MATCH START/RESUME: P1=" ++ p1IP ++ " P2=" ++ p2IP)
  roomVar <- newTVarIO initial
  roomLock <- newMVar ()
  q1 <- newTQueueIO
  q2 <- newTQueueIO
  let queues = Map.fromList [(P1, q1), (P2, q2)]
  atomically $ do
    writeTQueue q1 (SWelcome P1)
    writeTQueue q1 (SView (viewFor P1 initial))
    writeTQueue q2 (SWelcome P2)
    writeTQueue q2 (SView (viewFor P2 initial))
    when (P1 `elem` readyPlayers initial) (writeTQueue q1 (SInfo "Đã sẵn sàng. Đang chờ đối thủ..."))
    when (P2 `elem` readyPlayers initial) (writeTQueue q2 (SInfo "Đã sẵn sàng. Đang chờ đối thủ..."))
    writeTQueue q1 (SInfo "Đã đồng bộ trạng thái trận đấu từ máy chủ.")
    writeTQueue q2 (SInfo "Đã đồng bộ trạng thái trận đấu từ máy chủ.")
  done <- newEmptyMVar
  tids <- sequence
    [ forkIO (writer c1 q1)
    , forkIO (writer c2 q2)
    , forkIO (reader historyFile historyLock activeFile savedMatchVar roomLock p1IP p2IP P1 c1 roomVar queues done)
    , forkIO (reader historyFile historyLock activeFile savedMatchVar roomLock p1IP p2IP P2 c2 roomVar queues done)
    ]
  takeMVar done
  threadDelay 250000
  mapM_ killThread tids
  putStrLn "Kết nối trận WebSocket đã dừng; trạng thái đang chơi được giữ lại để khôi phục."
  where
    readyPlayers room = [p | p <- players, p `elem` rReady room]

writer :: Connection -> TQueue ServerMsg -> IO ()
writer conn queue = forever $ do
  msg <- atomically (readTQueue queue)
  sendTextData conn (T.pack (encodeServerMsg msg))

reader :: FilePath -> MVar () -> FilePath -> MVar (Maybe SavedMatch) -> MVar () -> String -> String -> Player -> Connection -> TVar Room -> Map.Map Player (TQueue ServerMsg) -> MVar () -> IO ()
reader historyFile historyLock activeFile savedMatchVar roomLock p1IP p2IP p conn roomVar queues done =
  (loop `catch` (\(_ :: SomeException) -> pure ())) `finally` (void (tryPutMVar done ()))
  where
    loop = do
      raw <- receiveData conn :: IO T.Text
      case parseCommand (T.unpack raw) of
        Left err -> atomically (tell p (SError err)) >> loop
        Right Quit -> appendHistory historyFile historyLock (show p ++ " | quit; giữ trạng thái để khôi phục")
        Right cmd -> do
          (wasOver, nowOver) <- withMVar roomLock $ \_ -> do
            current <- readTVarIO roomVar
            let wasOver = isOver current
                (next, outs) = stepRoom p cmd current
                nowOver = isOver next
            atomically $ do
              writeTVar roomVar next
              forM_ outs (uncurry tell)
            persistRoom activeFile savedMatchVar p1IP p2IP next
            pure (wasOver, nowOver)
          appendHistory historyFile historyLock (show p ++ " | " ++ T.unpack raw)
          when (nowOver && not wasOver) $
            appendHistory historyFile historyLock ("MATCH END: P1=" ++ p1IP ++ " P2=" ++ p2IP ++ " | ván cũ đã kết thúc; lịch sử được giữ lại")
          loop
    tell to msg = forM_ (Map.lookup to queues) (`writeTQueue` msg)

persistRoom :: FilePath -> MVar (Maybe SavedMatch) -> String -> String -> Room -> IO ()
persistRoom activeFile savedMatchVar ip1 ip2 room =
  saveActiveMatch activeFile savedMatchVar (SavedMatch room ip1 ip2)

saveActiveMatch :: FilePath -> MVar (Maybe SavedMatch) -> SavedMatch -> IO ()
saveActiveMatch path savedMatchVar match = modifyMVar_ savedMatchVar $ \_ -> do
  writeFile path (show match)
  pure (Just match)

clearActiveMatch :: FilePath -> MVar (Maybe SavedMatch) -> IO ()
clearActiveMatch path savedMatchVar = modifyMVar_ savedMatchVar $ \_ -> do
  exists <- doesFileExist path
  when exists (removeFile path)
  pure Nothing

-- Ghi nhật ký có dấu thời gian; MVar tuần tự hóa các lần ghi từ nhiều luồng.
appendHistory :: FilePath -> MVar () -> String -> IO ()
appendHistory path lock message = do
  now <- getCurrentTime
  let timestamp = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S UTC" now
  withMVar lock $ \_ -> appendFile path (timestamp ++ " | " ++ message ++ "\n")
