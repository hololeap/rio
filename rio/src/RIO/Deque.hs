{-# LANGUAGE NoImplicitPrelude #-}
module RIO.Deque
    ( -- * Types
      Deque
    , UDeque
    , SDeque
    , BDeque
      -- * Operations
    , newDeque
    , popFrontDeque
    , popBackDeque
    , pushFrontDeque
    , pushBackDeque
    , foldlDeque
    , foldrDeque
    , dequeToList
      -- * Inference helpers
    , asUDeque
    , asSDeque
    , asBDeque
    ) where

import           RIO.Prelude.Reexports
import           Control.Exception            (assert)
import           Control.Monad                (liftM)
import qualified Data.Vector.Generic.Mutable  as V
import qualified Data.Vector.Mutable          as B
import qualified Data.Vector.Storable.Mutable as S
import qualified Data.Vector.Unboxed.Mutable  as U
import           Data.Primitive.MutVar

data DequeState v s a = DequeState
    !(v s a)
    {-# UNPACK #-} !Int -- start
    {-# UNPACK #-} !Int -- size

-- | A double-ended queue supporting any underlying vector type and any monad.
--
-- This implements a circular double-ended queue with exponential growth.
--
-- @since 0.1.9.0
newtype Deque v s a = Deque (MutVar s (DequeState v s a))

-- | A 'Deque' specialized to unboxed vectors.
--
-- @since 0.1.9.0
type UDeque = Deque U.MVector

-- | A 'Deque' specialized to storable vectors.
--
-- @since 0.1.9.0
type SDeque = Deque S.MVector

-- | A 'Deque' specialized to boxed vectors.
--
-- @since 0.1.9.0
type BDeque = Deque B.MVector

-- | Helper function to assist with type inference, forcing usage of
-- an unboxed vector.
--
-- @since 0.1.9.0
asUDeque :: UDeque s a -> UDeque s a
asUDeque = id

-- | Helper function to assist with type inference, forcing usage of a
-- storable vector.
--
-- @since 0.1.9.0
asSDeque :: SDeque s a -> SDeque s a
asSDeque = id

-- | Helper function to assist with type inference, forcing usage of a
-- boxed vector.
--
-- @since 0.1.9.0
asBDeque :: BDeque s a -> BDeque s a
asBDeque = id

-- | Create a new, empty 'Deque'
--
-- @since 0.1.9.0
newDeque
  :: (V.MVector v a, PrimMonad m)
  => m (Deque v (PrimState m) a)
newDeque = do
    v <- V.new baseSize
    liftM Deque $ newMutVar (DequeState v 0 0)
  where
    baseSize = 32
{-# INLINE newDeque #-}

-- | Pop the first value from the beginning of the 'Deque'
--
-- @since 0.1.9.0
popFrontDeque
  :: (V.MVector v a, PrimMonad m)
  => Deque v (PrimState m) a
  -> m (Maybe a)
popFrontDeque (Deque var) = do
    DequeState v start size <- readMutVar var
    if size == 0
        then return Nothing
        else do
            x <- V.unsafeRead v start
            let start' = start + 1
                start''
                    | start' >= V.length v = 0
                    | otherwise = start'
            writeMutVar var $! DequeState v start'' (size - 1)
            return $! Just x
{-# INLINE popFrontDeque #-}

-- | Pop the first value from the end of the 'Deque'
--
-- @since 0.1.9.0
popBackDeque
  :: (V.MVector v a, PrimMonad m)
  => Deque v (PrimState m) a
  -> m (Maybe a)
popBackDeque (Deque var) = do
    DequeState v start size <- readMutVar var
    if size == 0
        then return Nothing
        else do
            let size' = size - 1
                end = start + size'
                end'
                    | end >= V.length v = end - V.length v
                    | otherwise = end
            x <- V.unsafeRead v end'
            writeMutVar var $! DequeState v start size'
            return $! Just x
{-# INLINE popBackDeque #-}

-- | Push a new value to the beginning of the 'Deque'
--
-- @since 0.1.9.0
pushFrontDeque
  :: (V.MVector v a, PrimMonad m)
  => Deque v (PrimState m) a
  -> a
  -> m ()
pushFrontDeque (Deque var) x = do
    DequeState v start size <- readMutVar var
    inner v start size
  where
    inner v start size = do
        if size >= V.length v
            then newVector v start size inner
            else do
                let size' = size + 1
                    start' = (start - 1) `rem` V.length v
                    start''
                        | start' < 0 = V.length v + start'
                        | otherwise = start'
                V.unsafeWrite v start'' x
                writeMutVar var $! DequeState v start'' size'
{-# INLINE pushFrontDeque #-}

-- | Push a new value to the end of the 'Deque'
--
-- @since 0.1.9.0
pushBackDeque
  :: (V.MVector v a, PrimMonad m)
  => Deque v (PrimState m) a
  -> a
  -> m ()
pushBackDeque (Deque var) x = do
    DequeState v start size <- readMutVar var
    inner v start size
  where
    inner v start size = do
        if size >= V.length v
            then newVector v start size inner
            else do
                let end = start + size
                    end'
                        | end >= V.length v = end - V.length v
                        | otherwise = end
                V.unsafeWrite v end' x
                writeMutVar var $! DequeState v start (size + 1)
{-# INLINE pushBackDeque #-}

-- | Fold over a 'Deque', starting at the beginning. Does not modify the 'Deque'.
--
-- @since 0.1.9.0
foldlDeque
  :: (V.MVector v a, PrimMonad m)
  => (acc -> a -> m acc)
  -> acc
  -> Deque v (PrimState m) a
  -> m acc
foldlDeque f acc0 (Deque var) = do
  DequeState v start size <- readMutVar var
  let loop idx acc
        | idx >= size = pure acc
        | otherwise = do
            let idxPlusStart = idx + start
                idx'
                  | idxPlusStart >= V.length v = idxPlusStart - V.length v
                  | otherwise = idxPlusStart
            a <- V.unsafeRead v idx'
            acc' <- f acc a
            loop (idx + 1) $! acc'
  loop 0 acc0

-- | Fold over a 'Deque', starting at the end. Does not modify the 'Deque'.
--
-- @since 0.1.9.0
foldrDeque
  :: (V.MVector v a, PrimMonad m)
  => (a -> acc -> m acc)
  -> acc
  -> Deque v (PrimState m) a
  -> m acc
foldrDeque f acc0 (Deque var) = do
  DequeState v start size <- readMutVar var
  let loop idx acc
        | idx < 0 = pure acc
        | otherwise = do
            let idxPlusStart = idx + start
                idx'
                  | idxPlusStart >= V.length v = idxPlusStart - V.length v
                  | otherwise = idxPlusStart
            a <- V.unsafeRead v idx'
            acc' <- f a acc
            loop (idx - 1) $! acc'
  loop (size - 1) acc0

-- | Convert a 'Deque' into a list. Does not modify the 'Deque'.
--
-- @since 0.1.9.0
dequeToList
  :: (V.MVector v a, PrimMonad m)
  => Deque v (PrimState m) a
  -> m [a]
dequeToList = foldrDeque (\a rest -> pure $ a : rest) []
{-# INLINE dequeToList #-}

newVector :: (PrimMonad m, V.MVector v a)
          => v (PrimState m) a
          -> Int
          -> Int
          -> (v (PrimState m) a -> Int -> Int -> m b)
          -> m b
newVector v size2 sizeOrig f = assert (sizeOrig == V.length v) $ do
    v' <- V.unsafeNew (V.length v * 2)
    let size1 = V.length v - size2
    V.unsafeCopy
        (V.unsafeTake size1 v')
        (V.unsafeSlice size2 size1 v)
    V.unsafeCopy
        (V.unsafeSlice size1 size2 v')
        (V.unsafeTake size2 v)
    f v' 0 sizeOrig
{-# INLINE newVector #-}
