-- Provides access to the preludeLanguage.Haskell.TH
{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
module Verifier.SAW.Prelude
  ( Module
  , module Verifier.SAW.Prelude
  ) where

import Verifier.SAW.ParserUtils

$(runDecWriter $ do
    prelude <- mkDecModule [] "preludeModule" "prelude/Prelude.saw"
    decSharedModuleFns "Prelude" (dmModule prelude)
 )