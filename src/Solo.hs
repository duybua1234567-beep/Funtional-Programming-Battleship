-- | Solo.hs
--
-- Chế độ chơi một mình với máy, ngay trong một tiến trình (không cần mạng).
--
-- Điểm hay: máy chỉ là "người chơi 2" gửi lệnh vào đúng hàm 'Session.stepRoom'
-- mà server mạng cũng dùng. Không có luật chơi nào được viết lại, nên chế độ
-- này và chế độ mạng cư xử y hệt nhau.
module Solo (runSolo) where

import System.IO

import AI (chooseShot)
import Parser (parseCommand)
import Render
import Rng
import Session
import Types

runSolo :: Theme -> IO ()
runSolo th = do
  seed <- freshSeed
  let room0 = initialRoom seed
      -- Máy xếp tàu ngẫu nhiên và sẵn sàng ngay từ đầu.
      room1 = foldl (\r c -> fst (stepRoom P2 c r)) room0 [RandomFleet, Ready]
  putStrLn "=== BATTLESHIP: bạn (Người chơi 1) đấu với máy ==="
  emit th (snd (stepRoom P1 Help room1))
  emit th [(P1, SView (viewFor P1 room1))]
  loop th room1 (seed * 31 + 7)

loop :: Theme -> Room -> Seed -> IO ()
loop th room aiSeed = do
  eof <- isEOF
  if eof then pure () else do
    line <- getLine
    case parseCommand line of
      Left err       -> putStrLn (paint th "31" err) >> loop th room aiSeed
      Right Quit     -> putStrLn "Tạm biệt!"
      Right cmd      -> do
        let (room1, outs1)         = stepRoom P1 cmd room
            (room2, outs2, seed')  = aiMove room1 aiSeed
        emit th (keepLastView (outs1 ++ outs2))
        if isOver room2 then pure () else loop th room2 seed'

-- | Nếu đang đến lượt máy thì máy bắn một phát (nó chỉ nhìn thấy 'PublicBoard').
aiMove :: Room -> Seed -> (Room, [Outgoing], Seed)
aiMove room seed = case rGame room of
  Just g | gTurn g == P2 && not (isOver room) ->
    let (c, seed')    = chooseShot (vEnemy (viewFor P2 room)) seed
        (room', outs) = stepRoom P2 (Fire c) room
    in (room', outs, seed')
  _ -> (room, [], seed)

-- | Sau mỗi vòng chỉ in bàn cờ của người chơi 1 MỘT lần (bản cuối), tránh in
-- hai bàn liên tiếp (một sau lượt của bạn, một sau lượt của máy).
keepLastView :: [Outgoing] -> [Outgoing]
keepLastView outs = [o | (i, o) <- zip [0 :: Int ..] outs, not (isMyView o) || i == lastView]
  where
    isMyView (P1, SView _) = True
    isMyView _             = False
    lastView = maximum (-1 : [i | (i, o) <- zip [0 ..] outs, isMyView o])

-- | In những thông điệp dành cho người chơi 1.
emit :: Theme -> [Outgoing] -> IO ()
emit th outs = mapM_ putStrLn
  [line | (P1, msg) <- outs, line <- renderMsg th P1 msg]
