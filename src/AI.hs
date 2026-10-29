
module AI (chooseShot, candidates) where

import qualified Data.Map.Strict as Map

import Engine (allCoords, inBounds)
import Rng
import Types

-- | Chọn ô bắn tiếp theo (và Seed mới).
chooseShot :: PublicBoard -> Seed -> (Coord, Seed)
chooseShot pb = runState (pickOne (Coord 0 0) (candidates pb))

-- | Danh sách ô đáng bắn nhất, theo thứ tự ưu tiên giảm dần: lấy nhóm đầu
-- tiên không rỗng.
candidates :: PublicBoard -> [Coord]
candidates (PublicBoard m) =
  case filter (not . null) [lineExtension, nextToHit, parityHunt, untried] of
    (group : _) -> group
    []          -> []
  where
    known c = Map.member c m
    free  c = inBounds c && not (known c)

    untried = [c | c <- allCoords, not (known c)]

    -- Các ô trúng mà tàu chưa chìm (ô của tàu đã chìm là PSunk nên bị loại).
    hits = [c | (c, PHit) <- Map.toList m]

    directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]
    move (Coord r c) (dr, dc) = Coord (r + dr) (c + dc)

    nextToHit =
      [n | h <- hits, d <- directions, let n = move h d, free n]

    -- Ô n kề ô trúng h, và ô đối diện phía sau h cũng là ô trúng => đang bắn dọc một tàu.
    lineExtension =
      [ n
      | h <- hits
      , d@(dr, dc) <- directions
      , let n = move h d
      , free n
      , Map.lookup (move h (negate dr, negate dc)) m == Just PHit
      ]

    parityHunt = [c | c@(Coord r k) <- untried, even (r + k)]
