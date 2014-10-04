module Verifier.SAW.Constant (scConstant) where
import Verifier.SAW.SharedTerm
import Verifier.SAW.Rewriter
import Verifier.SAW.Conversion

scConstant :: SharedContext s -> Ident -> SharedTerm s -> IO (SharedTerm s)
scConstant sc ident t = do
  ty <- scTypeOf sc t
  ty' <- rewriteSharedTerm sc (addConvs natConversions emptySimpset) ty
  scTermF sc (Constant ident t ty')