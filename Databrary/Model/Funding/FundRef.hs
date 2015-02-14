{-# LANGUAGE OverloadedStrings #-}
module Databrary.Model.Funding.FundRef
  ( lookupFunderRef
  ) where

import Control.Applicative ((<$>))
import Control.Monad.Catch (MonadThrow)
import Control.Monad.Trans.Maybe (MaybeT(..), runMaybeT)
import qualified Data.Attoparsec.ByteString as P
import qualified Data.ByteString as BS
import Data.List (stripPrefix)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HC
import Text.Read (readMaybe)

import qualified Databrary.JSON as JSON
import Databrary.Web.Client
import Databrary.DB
import Databrary.Model.Id.Types
import Databrary.Model.Funding

fundRefDOI :: String
fundRefDOI = "10.13039/"

fundRefId :: Id Funder -> String
fundRefId fi = ("http://data.fundref.org/fundref/funder/" ++ fundRefDOI) ++ show fi

requestJSON :: (HTTPClientM c m) => HC.Request -> m (Maybe JSON.Value)
requestJSON req = httpRequest req "application/json" $ \rb ->
  P.maybeResult <$> P.parseWith rb JSON.json BS.empty

makeFunder :: Id Funder -> T.Text -> [T.Text] -> [T.Text] -> Funder
makeFunder fi name aliases country =
  Funder fi name -- TODO

parseFundRef :: JSON.Value -> JSON.Parser Funder
parseFundRef = JSON.withObject "fundref" $ \j -> do
  doi <- j JSON..: "id"
  fid <- maybe (fail $ "doi: " ++ doi) (return . Id) $ readMaybe =<< stripPrefix ("http://dx.doi.org/" ++ fundRefDOI) doi
  name <- label =<< j JSON..: "prefLabel"
  -- TODO
  return $ makeFunder fid name undefined undefined
  where
  label j = j JSON..: "Label" >>= (JSON..: "literalForm") >>= (JSON..: "content")

lookupFundRef :: (DBM m, HTTPClientM c m, MonadThrow m) => Id Funder -> m (Maybe Funder)
lookupFundRef fi = runMaybeT $ do
  req <- HC.parseUrl $ fundRefId fi
  j <- MaybeT $ requestJSON req
  MaybeT $ return $ JSON.parseMaybe parseFundRef j

lookupFunderRef :: (DBM m, HTTPClientM c m, MonadThrow m) => Id Funder -> m (Maybe Funder)
lookupFunderRef fi =
  maybe (lookupFundRef fi) (return . Just) =<< lookupFunder fi
