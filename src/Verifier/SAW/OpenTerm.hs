{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}

{- |
Module      : Verifier.SAW.OpenTerm
Copyright   : Galois, Inc. 2018
License     : BSD3
Stability   : experimental
Portability : non-portable (language extensions)

This module defines an interface to building SAW core terms in an incrementally
type-checked way, meaning that type-checking is performed as the terms are
built.
-}

module Verifier.SAW.OpenTerm (
  -- * Open terms and converting to closed terms
  OpenTerm, completeOpenTerm,
  -- * Basic operations for building open terms
  closedOpenTerm, flatOpenTerm, applyOpenTerm, lambdaOpenTerm, piOpenTerm,
  -- * Monadic operations for building terms with binders
  OpenTermM, dedupOpenTermM, lambdaOpenTermM, piOpenTermM,
  lambdaOpenTermAuxM, piOpenTermAuxM
  ) where

import Control.Monad
import Verifier.SAW.Term.Functor
import Verifier.SAW.SharedTerm
import Verifier.SAW.SCTypeCheck

-- | An open term is represented as a type-checking computation that computes a
-- SAW core term and its type
newtype OpenTerm = OpenTerm { unOpenTerm :: TCM TypedTerm }

-- | "Complete" an 'OpenTerm' to a closed term
completeOpenTerm :: SharedContext -> OpenTerm -> IO (Either TCError Term)
completeOpenTerm sc (OpenTerm termM) = runTCM (typedVal <$> termM) sc Nothing []

-- | Embed a closed 'Term' into an 'OpenTerm'
closedOpenTerm :: Term -> OpenTerm
closedOpenTerm t = OpenTerm $ typeInferComplete t

-- | Build an 'OpenTerm' from a 'FlatTermF'
flatOpenTerm :: FlatTermF OpenTerm -> OpenTerm
flatOpenTerm ftf = OpenTerm $
  (sequence (fmap unOpenTerm ftf) >>= typeInferComplete)

-- | Apply an 'OpenTerm' to another
applyOpenTerm :: OpenTerm -> OpenTerm -> OpenTerm
applyOpenTerm (OpenTerm f) (OpenTerm arg) =
  OpenTerm ((App <$> f <*> arg) >>= typeInferComplete)

-- | Build an 'OpenTerm' for the top variable in the current context, by
-- building the 'TCM' computation which checks how much longer the context has
-- gotten since the variable was created and uses this to compute its deBruijn
-- index
openTermTopVar :: TCM OpenTerm
openTermTopVar =
  do outer_ctx <- askCtx
     return $ OpenTerm $ do
       inner_ctx <- askCtx
       typeInferComplete (LocalVar (length inner_ctx
                                    - length outer_ctx) :: TermF Term)

-- | Build an open term inside a binder of a variable with the given name and
-- type, where the binder is represented as a Haskell function on 'OpenTerm's
bindOpenTerm :: String -> TypedTerm -> (OpenTerm -> OpenTerm) -> TCM TypedTerm
bindOpenTerm x tp body_f =
  do tp_whnf <- typeCheckWHNF $ typedVal tp
     withVar x tp_whnf (openTermTopVar >>= (unOpenTerm . body_f))

-- | Build a lambda abstraction as an 'OpenTerm'
lambdaOpenTerm :: String -> OpenTerm -> (OpenTerm -> OpenTerm) -> OpenTerm
lambdaOpenTerm x (OpenTerm tpM) body_f = OpenTerm $
  do tp <- tpM
     body <- bindOpenTerm x tp body_f
     typeInferComplete $ Lambda x tp body

-- | Build a Pi abstraction as an 'OpenTerm'
piOpenTerm :: String -> OpenTerm -> (OpenTerm -> OpenTerm) -> OpenTerm
piOpenTerm x (OpenTerm tpM) body_f = OpenTerm $
  do tp <- tpM
     body <- bindOpenTerm x tp body_f
     typeInferComplete $ Pi x tp body

-- | The monad for building 'OpenTerm's if you want to add in 'IO' actions is
-- the type-checking monad, which we rename here to be self-contained
type OpenTermM = TCM

-- | "De-duplicate" an open term, so that duplicating the returned 'OpenTerm'
-- does not lead to duplicated WHNF work
dedupOpenTermM :: OpenTerm -> OpenTermM OpenTerm
dedupOpenTermM (OpenTerm trmM) = do
  trm <- trmM
  return $ OpenTerm $ return trm

-- | Build an open term inside a binder of a variable with the given name and
-- type, where the binder is represented as a monadic Haskell function on
-- 'OpenTerm's that also returns an auxiliary value. Returns the normalized type
-- and the body, along with the auxiliary result returned by the body-generating
-- function.
bindOpenTermAuxM :: String -> OpenTerm ->
                    (OpenTerm -> OpenTermM (OpenTerm, a)) ->
                    OpenTermM (TypedTerm, TypedTerm, a)
bindOpenTermAuxM x (OpenTerm tpM) body_f =
  do TypedTerm tp tp_tp <- tpM
     tp_whnf <- typeCheckWHNF tp
     (OpenTerm bodyM, a) <- withVar x tp_whnf (openTermTopVar >>= body_f)
     body <- bodyM
     return (TypedTerm tp_whnf tp_tp, body, a)

-- | Build a lambda abstraction in the 'OpenTermM' monad
lambdaOpenTermM :: String -> OpenTerm -> (OpenTerm -> OpenTermM OpenTerm) ->
                   OpenTermM OpenTerm
lambdaOpenTermM x tp body_f =
  fst <$> lambdaOpenTermAuxM x tp (body_f >=> (\t -> return (t, ())))

-- | Build a pi abstraction in the 'OpenTermM' monad
piOpenTermM :: String -> OpenTerm -> (OpenTerm -> OpenTermM OpenTerm) ->
               OpenTermM OpenTerm
piOpenTermM x tp body_f =
  fst <$> piOpenTermAuxM x tp (body_f >=> (\t -> return (t, ())))

-- | Build a lambda abstraction with an auxiliary return value in the
-- 'OpenTermM' monad
lambdaOpenTermAuxM :: String -> OpenTerm ->
                      (OpenTerm -> OpenTermM (OpenTerm, a)) ->
                      OpenTermM (OpenTerm, a)
lambdaOpenTermAuxM x tp body_f =
  do (tp', body, a) <- bindOpenTermAuxM x tp body_f
     return (OpenTerm (typeInferComplete $ Lambda x tp' body), a)

-- | Build a pi abstraction with an auxiliary return value in the 'OpenTermM'
-- monad
piOpenTermAuxM :: String -> OpenTerm -> (OpenTerm -> OpenTermM (OpenTerm, a)) ->
                  OpenTermM (OpenTerm, a)
piOpenTermAuxM x tp body_f =
  do (tp', body, a) <- bindOpenTermAuxM x tp body_f
     return (OpenTerm (typeInferComplete $ Pi x tp' body), a)
