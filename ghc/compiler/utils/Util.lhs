%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[Util]{Highly random utility functions}

\begin{code}
-- IF_NOT_GHC is meant to make this module useful outside the context of GHC
#define IF_NOT_GHC(a)

module Util (
	-- The Eager monad
	Eager, thenEager, returnEager, mapEager, appEager, runEager,

	-- general list processing
	zipEqual, zipWithEqual, zipWith3Equal, zipWith4Equal,
        zipLazy, stretchZipEqual,
	mapAndUnzip, mapAndUnzip3,
	nOfThem, lengthExceeds, isSingleton, only,
	snocView,
	isIn, isn'tIn,

	-- association lists
	assoc, assocUsing, assocDefault, assocDefaultUsing,

	-- duplicate handling
	hasNoDups, equivClasses, runs, removeDups, equivClassesByUniq,

	-- sorting
	IF_NOT_GHC(quicksort COMMA stableSortLt COMMA mergesort COMMA)
	sortLt,
	IF_NOT_GHC(mergeSort COMMA) naturalMergeSortLe,	-- from Carsten
	IF_NOT_GHC(naturalMergeSort COMMA mergeSortLe COMMA)

	-- transitive closures
	transitiveClosure,

	-- accumulating
	mapAccumL, mapAccumR, mapAccumB, foldl2, count,

	-- comparisons
	thenCmp, cmpList,

	-- strictness
	seqList, ($!),

	-- pairs
	IF_NOT_GHC(cfst COMMA applyToPair COMMA applyToFst COMMA)
	IF_NOT_GHC(applyToSnd COMMA foldPair COMMA)
	unzipWith
    ) where

#include "HsVersions.h"

import List		( zipWith4 )
import Panic		( panic )
import Unique		( Unique )
import UniqFM		( eltsUFM, emptyUFM, addToUFM_C )

infixr 9 `thenCmp`
\end{code}

%************************************************************************
%*									*
\subsection{The Eager monad}
%*									*
%************************************************************************

The @Eager@ monad is just an encoding of continuation-passing style,
used to allow you to express "do this and then that", mainly to avoid
space leaks. It's done with a type synonym to save bureaucracy.

\begin{code}
type Eager ans a = (a -> ans) -> ans

runEager :: Eager a a -> a
runEager m = m (\x -> x)

appEager :: Eager ans a -> (a -> ans) -> ans
appEager m cont = m cont

thenEager :: Eager ans a -> (a -> Eager ans b) -> Eager ans b
thenEager m k cont = m (\r -> k r cont)

returnEager :: a -> Eager ans a
returnEager v cont = cont v

mapEager :: (a -> Eager ans b) -> [a] -> Eager ans [b]
mapEager f [] = returnEager []
mapEager f (x:xs) = f x			`thenEager` \ y ->
		    mapEager f xs	`thenEager` \ ys ->
		    returnEager (y:ys)
\end{code}

%************************************************************************
%*									*
\subsection[Utils-lists]{General list processing}
%*									*
%************************************************************************

A paranoid @zip@ (and some @zipWith@ friends) that checks the lists
are of equal length.  Alastair Reid thinks this should only happen if
DEBUGging on; hey, why not?

\begin{code}
zipEqual	:: String -> [a] -> [b] -> [(a,b)]
zipWithEqual	:: String -> (a->b->c) -> [a]->[b]->[c]
zipWith3Equal	:: String -> (a->b->c->d) -> [a]->[b]->[c]->[d]
zipWith4Equal	:: String -> (a->b->c->d->e) -> [a]->[b]->[c]->[d]->[e]

#ifndef DEBUG
zipEqual      _ = zip
zipWithEqual  _ = zipWith
zipWith3Equal _ = zipWith3
zipWith4Equal _ = zipWith4
#else
zipEqual msg []     []     = []
zipEqual msg (a:as) (b:bs) = (a,b) : zipEqual msg as bs
zipEqual msg as     bs     = panic ("zipEqual: unequal lists:"++msg)

zipWithEqual msg z (a:as) (b:bs)=  z a b : zipWithEqual msg z as bs
zipWithEqual msg _ [] []	=  []
zipWithEqual msg _ _ _		=  panic ("zipWithEqual: unequal lists:"++msg)

zipWith3Equal msg z (a:as) (b:bs) (c:cs)
				=  z a b c : zipWith3Equal msg z as bs cs
zipWith3Equal msg _ [] []  []	=  []
zipWith3Equal msg _ _  _   _	=  panic ("zipWith3Equal: unequal lists:"++msg)

zipWith4Equal msg z (a:as) (b:bs) (c:cs) (d:ds)
				=  z a b c d : zipWith4Equal msg z as bs cs ds
zipWith4Equal msg _ [] [] [] []	=  []
zipWith4Equal msg _ _  _  _  _	=  panic ("zipWith4Equal: unequal lists:"++msg)
#endif
\end{code}

\begin{code}
-- zipLazy is lazy in the second list (observe the ~)

zipLazy :: [a] -> [b] -> [(a,b)]
zipLazy [] ys = []
zipLazy (x:xs) ~(y:ys) = (x,y) : zipLazy xs ys
\end{code}


\begin{code}
stretchZipEqual :: (a -> b -> Maybe a) -> [a] -> [b] -> [a]
-- (stretchZipEqual f xs ys) stretches ys to "fit" the places where f returns a Just

stretchZipEqual f [] [] = []
stretchZipEqual f (x:xs) (y:ys) = case f x y of
				    Just x' -> x' : stretchZipEqual f xs ys
				    Nothing -> x  : stretchZipEqual f xs (y:ys)
\end{code}


\begin{code}
mapAndUnzip :: (a -> (b, c)) -> [a] -> ([b], [c])

mapAndUnzip f [] = ([],[])
mapAndUnzip f (x:xs)
  = let
	(r1,  r2)  = f x
	(rs1, rs2) = mapAndUnzip f xs
    in
    (r1:rs1, r2:rs2)

mapAndUnzip3 :: (a -> (b, c, d)) -> [a] -> ([b], [c], [d])

mapAndUnzip3 f [] = ([],[],[])
mapAndUnzip3 f (x:xs)
  = let
	(r1,  r2,  r3)  = f x
	(rs1, rs2, rs3) = mapAndUnzip3 f xs
    in
    (r1:rs1, r2:rs2, r3:rs3)
\end{code}

\begin{code}
nOfThem :: Int -> a -> [a]
nOfThem n thing = replicate n thing

lengthExceeds :: [a] -> Int -> Bool
-- (lengthExceeds xs n) is True if   length xs > n
(x:xs)	`lengthExceeds` n = n < 1 || xs `lengthExceeds` (n - 1)
[]	`lengthExceeds` n = n < 0

isSingleton :: [a] -> Bool
isSingleton [x] = True
isSingleton  _  = False

only :: [a] -> a
#ifdef DEBUG
only [a] = a
#else
only (a:_) = a
#endif
\end{code}

\begin{code}
snocView :: [a] -> ([a], a)	-- Split off the last element
snocView xs = go xs []
	    where
	      go [x]    acc = (reverse acc, x)
	      go (x:xs) acc = go xs (x:acc)
\end{code}

Debugging/specialising versions of \tr{elem} and \tr{notElem}

\begin{code}
isIn, isn'tIn :: (Eq a) => String -> a -> [a] -> Bool

# ifndef DEBUG
isIn    msg x ys = elem__    x ys
isn'tIn msg x ys = notElem__ x ys

--these are here to be SPECIALIZEd (automagically)
elem__ _ []	= False
elem__ x (y:ys)	= x==y || elem__ x ys

notElem__ x []	   =  True
notElem__ x (y:ys) =  x /= y && notElem__ x ys

# else {- DEBUG -}
isIn msg x ys
  = elem ILIT(0) x ys
  where
    elem i _ []	    = False
    elem i x (y:ys)
      | i _GE_ ILIT(100) = panic ("Over-long elem in: " ++ msg)
      | otherwise	 = x == y || elem (i _ADD_ ILIT(1)) x ys

isn'tIn msg x ys
  = notElem ILIT(0) x ys
  where
    notElem i x [] =  True
    notElem i x (y:ys)
      | i _GE_ ILIT(100) = panic ("Over-long notElem in: " ++ msg)
      | otherwise	 =  x /= y && notElem (i _ADD_ ILIT(1)) x ys

# endif {- DEBUG -}

\end{code}

%************************************************************************
%*									*
\subsection[Utils-assoc]{Association lists}
%*									*
%************************************************************************

See also @assocMaybe@ and @mkLookupFun@ in module @Maybes@.

\begin{code}
assoc		  :: (Eq a) => String -> [(a, b)] -> a -> b
assocDefault	  :: (Eq a) => b -> [(a, b)] -> a -> b
assocUsing	  :: (a -> a -> Bool) -> String -> [(a, b)] -> a -> b
assocDefaultUsing :: (a -> a -> Bool) -> b -> [(a, b)] -> a -> b

assocDefaultUsing eq deflt ((k,v) : rest) key
  | k `eq` key = v
  | otherwise  = assocDefaultUsing eq deflt rest key

assocDefaultUsing eq deflt [] key = deflt

assoc crash_msg         list key = assocDefaultUsing (==) (panic ("Failed in assoc: " ++ crash_msg)) list key
assocDefault deflt      list key = assocDefaultUsing (==) deflt list key
assocUsing eq crash_msg list key = assocDefaultUsing eq (panic ("Failed in assoc: " ++ crash_msg)) list key
\end{code}

%************************************************************************
%*									*
\subsection[Utils-dups]{Duplicate-handling}
%*									*
%************************************************************************

\begin{code}
hasNoDups :: (Eq a) => [a] -> Bool

hasNoDups xs = f [] xs
  where
    f seen_so_far []     = True
    f seen_so_far (x:xs) = if x `is_elem` seen_so_far then
				False
			   else
				f (x:seen_so_far) xs

    is_elem = isIn "hasNoDups"
\end{code}

\begin{code}
equivClasses :: (a -> a -> Ordering) 	-- Comparison
	     -> [a]
	     -> [[a]]

equivClasses cmp stuff@[]     = []
equivClasses cmp stuff@[item] = [stuff]
equivClasses cmp items
  = runs eq (sortLt lt items)
  where
    eq a b = case cmp a b of { EQ -> True; _ -> False }
    lt a b = case cmp a b of { LT -> True; _ -> False }
\end{code}

The first cases in @equivClasses@ above are just to cut to the point
more quickly...

@runs@ groups a list into a list of lists, each sublist being a run of
identical elements of the input list. It is passed a predicate @p@ which
tells when two elements are equal.

\begin{code}
runs :: (a -> a -> Bool) 	-- Equality
     -> [a]
     -> [[a]]

runs p []     = []
runs p (x:xs) = case (span (p x) xs) of
		  (first, rest) -> (x:first) : (runs p rest)
\end{code}

\begin{code}
removeDups :: (a -> a -> Ordering) 	-- Comparison function
	   -> [a]
	   -> ([a], 	-- List with no duplicates
	       [[a]])	-- List of duplicate groups.  One representative from
			-- each group appears in the first result

removeDups cmp []  = ([], [])
removeDups cmp [x] = ([x],[])
removeDups cmp xs
  = case (mapAccumR collect_dups [] (equivClasses cmp xs)) of { (dups, xs') ->
    (xs', dups) }
  where
    collect_dups dups_so_far [x]         = (dups_so_far,      x)
    collect_dups dups_so_far dups@(x:xs) = (dups:dups_so_far, x)
\end{code}


\begin{code}
equivClassesByUniq :: (a -> Unique) -> [a] -> [[a]]
	-- NB: it's *very* important that if we have the input list [a,b,c],
	-- where a,b,c all have the same unique, then we get back the list
	-- 	[a,b,c]
	-- not
	--	[c,b,a]
	-- Hence the use of foldr, plus the reversed-args tack_on below
equivClassesByUniq get_uniq xs
  = eltsUFM (foldr add emptyUFM xs)
  where
    add a ufm = addToUFM_C tack_on ufm (get_uniq a) [a]
    tack_on old new = new++old
\end{code}

%************************************************************************
%*									*
\subsection[Utils-sorting]{Sorting}
%*									*
%************************************************************************

%************************************************************************
%*									*
\subsubsection[Utils-quicksorting]{Quicksorts}
%*									*
%************************************************************************

\begin{code}
-- tail-recursive, etc., "quicker sort" [as per Meira thesis]
quicksort :: (a -> a -> Bool)		-- Less-than predicate
	  -> [a]			-- Input list
	  -> [a]			-- Result list in increasing order

quicksort lt []      = []
quicksort lt [x]     = [x]
quicksort lt (x:xs)  = split x [] [] xs
  where
    split x lo hi []		     = quicksort lt lo ++ (x : quicksort lt hi)
    split x lo hi (y:ys) | y `lt` x  = split x (y:lo) hi ys
			 | True      = split x lo (y:hi) ys
\end{code}

Quicksort variant from Lennart's Haskell-library contribution.  This
is a {\em stable} sort.

\begin{code}
stableSortLt = sortLt	-- synonym; when we want to highlight stable-ness

sortLt :: (a -> a -> Bool) 		-- Less-than predicate
       -> [a] 				-- Input list
       -> [a]				-- Result list

sortLt lt l = qsort lt   l []

-- qsort is stable and does not concatenate.
qsort :: (a -> a -> Bool)	-- Less-than predicate
      -> [a]			-- xs, Input list
      -> [a]			-- r,  Concatenate this list to the sorted input list
      -> [a]			-- Result = sort xs ++ r

qsort lt []     r = r
qsort lt [x]    r = x:r
qsort lt (x:xs) r = qpart lt x xs [] [] r

-- qpart partitions and sorts the sublists
-- rlt contains things less than x,
-- rge contains the ones greater than or equal to x.
-- Both have equal elements reversed with respect to the original list.

qpart lt x [] rlt rge r =
    -- rlt and rge are in reverse order and must be sorted with an
    -- anti-stable sorting
    rqsort lt rlt (x : rqsort lt rge r)

qpart lt x (y:ys) rlt rge r =
    if lt y x then
	-- y < x
	qpart lt x ys (y:rlt) rge r
    else
	-- y >= x
	qpart lt x ys rlt (y:rge) r

-- rqsort is as qsort but anti-stable, i.e. reverses equal elements
rqsort lt []     r = r
rqsort lt [x]    r = x:r
rqsort lt (x:xs) r = rqpart lt x xs [] [] r

rqpart lt x [] rle rgt r =
    qsort lt rle (x : qsort lt rgt r)

rqpart lt x (y:ys) rle rgt r =
    if lt x y then
	-- y > x
	rqpart lt x ys rle (y:rgt) r
    else
	-- y <= x
	rqpart lt x ys (y:rle) rgt r
\end{code}

%************************************************************************
%*									*
\subsubsection[Utils-dull-mergesort]{A rather dull mergesort}
%*									*
%************************************************************************

\begin{code}
mergesort :: (a -> a -> Ordering) -> [a] -> [a]

mergesort cmp xs = merge_lists (split_into_runs [] xs)
  where
    a `le` b = case cmp a b of { LT -> True;  EQ -> True; GT -> False }
    a `ge` b = case cmp a b of { LT -> False; EQ -> True; GT -> True  }

    split_into_runs []        []	    	= []
    split_into_runs run       []	    	= [run]
    split_into_runs []        (x:xs)		= split_into_runs [x] xs
    split_into_runs [r]       (x:xs) | x `ge` r = split_into_runs [r,x] xs
    split_into_runs rl@(r:rs) (x:xs) | x `le` r = split_into_runs (x:rl) xs
				     | True     = rl : (split_into_runs [x] xs)

    merge_lists []	 = []
    merge_lists (x:xs)   = merge x (merge_lists xs)

    merge [] ys = ys
    merge xs [] = xs
    merge xl@(x:xs) yl@(y:ys)
      = case cmp x y of
	  EQ  -> x : y : (merge xs ys)
	  LT  -> x : (merge xs yl)
	  GT -> y : (merge xl ys)
\end{code}

%************************************************************************
%*									*
\subsubsection[Utils-Carsten-mergesort]{A mergesort from Carsten}
%*									*
%************************************************************************

\begin{display}
Date: Mon, 3 May 93 20:45:23 +0200
From: Carsten Kehler Holst <kehler@cs.chalmers.se>
To: partain@dcs.gla.ac.uk
Subject: natural merge sort beats quick sort [ and it is prettier ]

Here is a piece of Haskell code that I'm rather fond of. See it as an
attempt to get rid of the ridiculous quick-sort routine. group is
quite useful by itself I think it was John's idea originally though I
believe the lazy version is due to me [surprisingly complicated].
gamma [used to be called] is called gamma because I got inspired by
the Gamma calculus. It is not very close to the calculus but does
behave less sequentially than both foldr and foldl. One could imagine
a version of gamma that took a unit element as well thereby avoiding
the problem with empty lists.

I've tried this code against

   1) insertion sort - as provided by haskell
   2) the normal implementation of quick sort
   3) a deforested version of quick sort due to Jan Sparud
   4) a super-optimized-quick-sort of Lennart's

If the list is partially sorted both merge sort and in particular
natural merge sort wins. If the list is random [ average length of
rising subsequences = approx 2 ] mergesort still wins and natural
merge sort is marginally beaten by Lennart's soqs. The space
consumption of merge sort is a bit worse than Lennart's quick sort
approx a factor of 2. And a lot worse if Sparud's bug-fix [see his
fpca article ] isn't used because of group.

have fun
Carsten
\end{display}

\begin{code}
group :: (a -> a -> Bool) -> [a] -> [[a]]

{-
Date: Mon, 12 Feb 1996 15:09:41 +0000
From: Andy Gill <andy@dcs.gla.ac.uk>

Here is a `better' definition of group.
-}
group p []     = []
group p (x:xs) = group' xs x x (x :)
  where
    group' []     _     _     s  = [s []]
    group' (x:xs) x_min x_max s 
	| not (x `p` x_max) = group' xs x_min x (s . (x :)) 
	| x `p` x_min       = group' xs x x_max ((x :) . s) 
	| otherwise         = s [] : group' xs x x (x :) 

-- This one works forwards *and* backwards, as well as also being
-- faster that the one in Util.lhs.

{- ORIG:
group p [] = [[]]
group p (x:xs) =
   let ((h1:t1):tt1) = group p xs
       (t,tt) = if null xs then ([],[]) else
		if x `p` h1 then (h1:t1,tt1) else
		   ([], (h1:t1):tt1)
   in ((x:t):tt)
-}

generalMerge :: (a -> a -> Bool) -> [a] -> [a] -> [a]
generalMerge p xs [] = xs
generalMerge p [] ys = ys
generalMerge p (x:xs) (y:ys) | x `p` y   = x : generalMerge p xs (y:ys)
			     | otherwise = y : generalMerge p (x:xs) ys

-- gamma is now called balancedFold

balancedFold :: (a -> a -> a) -> [a] -> a
balancedFold f [] = error "can't reduce an empty list using balancedFold"
balancedFold f [x] = x
balancedFold f l  = balancedFold f (balancedFold' f l)

balancedFold' :: (a -> a -> a) -> [a] -> [a]
balancedFold' f (x:y:xs) = f x y : balancedFold' f xs
balancedFold' f xs = xs

generalMergeSort p [] = []
generalMergeSort p xs = (balancedFold (generalMerge p) . map (: [])) xs

generalNaturalMergeSort p [] = []
generalNaturalMergeSort p xs = (balancedFold (generalMerge p) . group p) xs

mergeSort, naturalMergeSort :: Ord a => [a] -> [a]

mergeSort = generalMergeSort (<=)
naturalMergeSort = generalNaturalMergeSort (<=)

mergeSortLe le = generalMergeSort le
naturalMergeSortLe le = generalNaturalMergeSort le
\end{code}

%************************************************************************
%*									*
\subsection[Utils-transitive-closure]{Transitive closure}
%*									*
%************************************************************************

This algorithm for transitive closure is straightforward, albeit quadratic.

\begin{code}
transitiveClosure :: (a -> [a])		-- Successor function
		  -> (a -> a -> Bool)	-- Equality predicate
		  -> [a]
		  -> [a]		-- The transitive closure

transitiveClosure succ eq xs
 = go [] xs
 where
   go done [] 			   = done
   go done (x:xs) | x `is_in` done = go done xs
   		  | otherwise      = go (x:done) (succ x ++ xs)

   x `is_in` []                 = False
   x `is_in` (y:ys) | eq x y    = True
  		    | otherwise = x `is_in` ys
\end{code}

%************************************************************************
%*									*
\subsection[Utils-accum]{Accumulating}
%*									*
%************************************************************************

@mapAccumL@ behaves like a combination
of  @map@ and @foldl@;
it applies a function to each element of a list, passing an accumulating
parameter from left to right, and returning a final value of this
accumulator together with the new list.

\begin{code}
mapAccumL :: (acc -> x -> (acc, y)) 	-- Function of elt of input list
					-- and accumulator, returning new
					-- accumulator and elt of result list
	    -> acc 		-- Initial accumulator
	    -> [x] 		-- Input list
	    -> (acc, [y])		-- Final accumulator and result list

mapAccumL f b []     = (b, [])
mapAccumL f b (x:xs) = (b'', x':xs') where
					  (b', x') = f b x
					  (b'', xs') = mapAccumL f b' xs
\end{code}

@mapAccumR@ does the same, but working from right to left instead.  Its type is
the same as @mapAccumL@, though.

\begin{code}
mapAccumR :: (acc -> x -> (acc, y)) 	-- Function of elt of input list
					-- and accumulator, returning new
					-- accumulator and elt of result list
	    -> acc 		-- Initial accumulator
	    -> [x] 		-- Input list
	    -> (acc, [y])		-- Final accumulator and result list

mapAccumR f b []     = (b, [])
mapAccumR f b (x:xs) = (b'', x':xs') where
					  (b'', x') = f b' x
					  (b', xs') = mapAccumR f b xs
\end{code}

Here is the bi-directional version, that works from both left and right.

\begin{code}
mapAccumB :: (accl -> accr -> x -> (accl, accr,y))
      				-- Function of elt of input list
      				-- and accumulator, returning new
      				-- accumulator and elt of result list
	  -> accl 			-- Initial accumulator from left
	  -> accr 			-- Initial accumulator from right
	  -> [x] 			-- Input list
	  -> (accl, accr, [y])	-- Final accumulators and result list

mapAccumB f a b []     = (a,b,[])
mapAccumB f a b (x:xs) = (a'',b'',y:ys)
   where
	(a',b'',y)  = f a b' x
	(a'',b',ys) = mapAccumB f a' b xs
\end{code}

A combination of foldl with zip.  It works with equal length lists.

\begin{code}
foldl2 :: (acc -> a -> b -> acc) -> acc -> [a] -> [b] -> acc
foldl2 k z [] [] = z
foldl2 k z (a:as) (b:bs) = foldl2 k (k z a b) as bs
\end{code}

Count the number of times a predicate is true

\begin{code}
count :: (a -> Bool) -> [a] -> Int
count p [] = 0
count p (x:xs) | p x       = 1 + count p xs
	       | otherwise = count p xs
\end{code}


%************************************************************************
%*									*
\subsection[Utils-comparison]{Comparisons}
%*									*
%************************************************************************

\begin{code}
thenCmp :: Ordering -> Ordering -> Ordering
{-# INLINE thenCmp #-}
thenCmp EQ   any = any
thenCmp other any = other

cmpList :: (a -> a -> Ordering) -> [a] -> [a] -> Ordering
    -- `cmpList' uses a user-specified comparer

cmpList cmp []     [] = EQ
cmpList cmp []     _  = LT
cmpList cmp _      [] = GT
cmpList cmp (a:as) (b:bs)
  = case cmp a b of { EQ -> cmpList cmp as bs; xxx -> xxx }
\end{code}

\begin{code}
cmpString :: String -> String -> Ordering

cmpString []     []	= EQ
cmpString (x:xs) (y:ys) = if	  x == y then cmpString xs ys
			  else if x  < y then LT
			  else		      GT
cmpString []     ys	= LT
cmpString xs     []	= GT
\end{code}


%************************************************************************
%*									*
\subsection[Utils-pairs]{Pairs}
%*									*
%************************************************************************

The following are curried versions of @fst@ and @snd@.

\begin{code}
cfst :: a -> b -> a	-- stranal-sem only (Note)
cfst x y = x
\end{code}

The following provide us higher order functions that, when applied
to a function, operate on pairs.

\begin{code}
applyToPair :: ((a -> c),(b -> d)) -> (a,b) -> (c,d)
applyToPair (f,g) (x,y) = (f x, g y)

applyToFst :: (a -> c) -> (a,b)-> (c,b)
applyToFst f (x,y) = (f x,y)

applyToSnd :: (b -> d) -> (a,b) -> (a,d)
applyToSnd f (x,y) = (x,f y)

foldPair :: (a->a->a,b->b->b) -> (a,b) -> [(a,b)] -> (a,b)
foldPair fg ab [] = ab
foldPair fg@(f,g) ab ((a,b):abs) = (f a u,g b v)
		       where (u,v) = foldPair fg ab abs
\end{code}

\begin{code}
unzipWith :: (a -> b -> c) -> [(a, b)] -> [c]
unzipWith f pairs = map ( \ (a, b) -> f a b ) pairs
\end{code}

\begin{code}
#if __HASKELL1__ > 4
seqList :: [a] -> b -> b
#else
seqList :: (Eval a) => [a] -> b -> b
#endif
seqList [] b = b
seqList (x:xs) b = x `seq` seqList xs b

#if __HASKELL1__ <= 4
($!)    :: (Eval a) => (a -> b) -> a -> b
f $! x  = x `seq` f x
#endif
\end{code}
