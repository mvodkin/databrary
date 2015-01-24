{-# LANGUAGE TemplateHaskell #-}
module Databrary.Model.Token
  ( module Databrary.Model.Types.Token
  , lookupSession
  , sessionAuthorization
  ) where

import Control.Applicative ((<$>))
import qualified Data.ByteString.Base64.URL as Base64

import Databrary.Model.SQL.Token
import Databrary.Model.SQL
import Databrary.Model.Party
import Databrary.Model.Authorize
import Databrary.Entropy
import Databrary.DB
import Databrary.Model.Types.Token

generateToken :: EntropyM m => m TokenId
generateToken = Base64.encode <$> entropyBytes 24

lookupSession :: DBM m => TokenId -> m (Maybe SessionToken)
lookupSession tok = dbQuery1 $(selectQuery' sessionTokenSelector "WHERE session.token = ${tok}")

sessionAuthorization :: SessionToken -> Authorization
sessionAuthorization tok = Authorization
  { authorizeChild = accountParty (sessionAccount tok)
  , authorizeParent = rootParty
  , authorizeAccess = sessionAccess tok
  }