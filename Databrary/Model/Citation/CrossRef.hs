{-# LANGUAGE OverloadedStrings #-}
module Databrary.Model.Citation.CrossRef
  ( lookupCitation
  ) where

import Control.Applicative ((<$>), (<*>), (<$), optional)
import Control.Monad (guard)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (MaybeT(..), runMaybeT)
import qualified Data.Attoparsec.ByteString as P
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Foldable as Fold
import Data.Maybe (fromJust)
import qualified Data.Text.Encoding as TE
import qualified Network.HTTP.Client as HC
import qualified Network.URI as URI

import qualified Databrary.JSON as JSON
import Databrary.Web.Client
import Databrary.URL
import Databrary.Model.Citation.Types

crossRefUrl :: HC.Request
crossRefUrl = fromJust $ HC.parseUrl "http://data.crossref.org/"

crossRefReq :: String -> HC.Request
crossRefReq h = crossRefUrl { HC.path = BSC.pack $ '/' : URI.escapeURIString URI.isUnescapedInURIComponent h }

uriHDL :: URI.URI -> Maybe String
uriHDL u
  | URI.uriScheme u == "hdl:" = Just $ URI.uriPath u ++ URI.uriQuery u
  | otherwise = Nothing

parseCitation :: JSON.Value -> JSON.Parser Citation
parseCitation = JSON.withObject "citation" $ \o ->
  Citation
    <$> o JSON..:? "head" JSON..!= ""
    <*> o JSON..:? "title"
    <*> (Just <$> (o JSON..: "DOI" >>= parseDOI))
    <*> optional (o JSON..: "issued" >>= (JSON..: "date-parts") >>= (JSON..! 0) >>= (JSON..! 0))
  where
  parseDOI d = hdlURL d <$ guard (validHDL d)

lookupCitation :: (HTTPClientM c m) => URI.URI -> m (Maybe Citation)
lookupCitation uri = runMaybeT $ do
  hdl <- may $ uriHDL uri
  let req = httpRequest (crossRefReq hdl)
  j <- MaybeT $ req "application/vnd.citationstyles.csl+json" $ \rb ->
    P.maybeResult <$> P.parseWith rb JSON.json BS.empty
  cite <- may $ JSON.parseMaybe parseCitation j
  -- empirically this is UTF-8, but does not say so:
  bib <- lift $ req "text/x-bibliography;style=apa" $ fmap Just . HC.brConsume
  return $ maybe cite (\h -> cite{ citationHead = Fold.foldMap TE.decodeUtf8 h }) bib
  where
  may = MaybeT . return
