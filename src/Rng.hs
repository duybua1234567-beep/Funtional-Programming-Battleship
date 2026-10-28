-- | Rng.hs
--
-- Số ngẫu nhiên THUẦN (Chương 7: State monad).
--
-- Vấn đề: hàm thuần không được "lấy số ngẫu nhiên" vì mỗi lần gọi phải cho
-- cùng kết quả. Giải pháp: biến bộ sinh số thành một giá trị (Seed) và để mỗi
-- lần dùng trả về Seed mới. Monad 'State' che đi việc chuyền Seed bằng tay.
--
-- Ta tự viết 'State' (thay vì dùng thư viện mtl) để thấy rõ Functor,
-- Applicative và Monad hoạt động thế nào. Lợi ích phụ: cùng một Seed luôn cho
-- cùng một ván đấu, nên test và gỡ lỗi lặp lại được.
module Rng
  ( State (..)
  , evalState
  , Seed
  , mkSeed
  , freshSeed
  , nextInt
  , pickOne
  ) where

import Data.Bits (shiftR)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)

-- | Một phép tính có trạng thái: nhận trạng thái cũ, trả (kết quả, trạng thái mới).
newtype State s a = State { runState :: s -> (a, s) }

instance Functor (State s) where
  fmap f (State g) = State $ \s ->
    let (a, s') = g s in (f a, s')

instance Applicative (State s) where
  pure a = State $ \s -> (a, s)
  State f <*> State g = State $ \s ->
    let (h, s1) = f s
        (a, s2) = g s1
    in (h a, s2)

instance Monad (State s) where
  State g >>= f = State $ \s ->
    let (a, s1) = g s
    in runState (f a) s1

evalState :: State s a -> s -> a
evalState m = fst . runState m

type Seed = Word64

-- | Trộn một số nguyên bất kỳ thành Seed.
mkSeed :: Int -> Seed
mkSeed n = fromIntegral n * 0x9E3779B97F4A7C15 + 1

-- | Seed lấy từ đồng hồ; đây là chỗ DUY NHẤT có IO trong module này.
freshSeed :: IO Seed
freshSeed = do
  t <- getPOSIXTime
  pure (mkSeed (round (t * 1000000)))

-- | Bộ sinh đồng dư tuyến tính (LCG), lấy các bit cao vì bit thấp kém ngẫu nhiên.
nextWord :: State Seed Word64
nextWord = State $ \s ->
  let s' = s * 6364136223846793005 + 1442695040888963407
  in (s' `shiftR` 33, s')

-- | Số nguyên ngẫu nhiên trong [0, n).
nextInt :: Int -> State Seed Int
nextInt n
  | n <= 1    = State $ \s -> (0, s)
  | otherwise = (\w -> fromIntegral w `mod` n) <$> nextWord

-- | Chọn ngẫu nhiên một phần tử; danh sách rỗng thì trả giá trị mặc định.
pickOne :: a -> [a] -> State Seed a
pickOne def [] = pure def
pickOne _ xs   = (xs !!) <$> nextInt (length xs)
