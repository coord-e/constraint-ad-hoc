{-# LANGUAGE FlexibleContexts #-}
module Overload where

import qualified AST.Intermediate          as S
import qualified AST.Kind                  as S
import qualified AST.Target                as T
import qualified AST.Type                  as S
import           Config
import           Overload.Env
import           Overload.GlobalInfer
import           Overload.Kind             (evalKind)
import           Overload.LocalInfer       (withBinding)
import           Overload.Type
import           Overload.TypeEval
import           Overload.Unify
import           Reporting.Error
import           Reporting.Error.Type
import           Reporting.Result

import           Control.Eff
import           Control.Eff.Exception
import           Control.Eff.Fresh
import           Control.Eff.Reader.Strict
import           Control.Eff.State.Strict
import           Control.Monad             (unless)
import qualified Data.Map                  as Map


compile :: Config -> S.Expr -> Result T.Expr
compile (Config bases lits binds) e = do
  ((PredType cstrs _, e'), cs) <- run . runError . runState initConstraints . runReader (mkInitEnv bases lits) . runFresh' 0 . loadBindings binds $ globalInfer e
  _ <- runSolve cs
  unless (null cstrs) (Left . TypeError $ UnresolvedVariable cstrs)
  return e'


mkInitEnv :: Map.Map String S.Kind -> LiteralTypes -> Env
mkInitEnv m = Env initContext kindenv typeenv
  where
    kindenv = Map.map evalKind m
    typeenv = Map.mapWithKey go m
    go = const . PredSem [] . SType . TBase

loadBindings :: (Member Fresh r, Member (Reader Env) r) => Map.Map String S.TypeScheme -> Eff r a -> Eff r a
loadBindings = flip $ Map.foldrWithKey go
  where
    go x s e = do
      s' <- runSchemeEvalToType s
      withBinding x s' e
