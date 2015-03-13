{-# LANGUAGE OverloadedStrings #-}
module Databrary.View.Angular
  ( htmlAngular
  ) where

import Control.Monad (forM_)
import qualified Data.Aeson.Encode as JSON
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BSB
import qualified Data.ByteString.Char8 as BSC
import Data.Monoid (mempty, (<>))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as HA

import Control.Applicative.Ops
import Control.Has (view)
import Databrary.Model.Identity
import Databrary.Action.Auth
import Databrary.Action
import Databrary.View.Html
import Databrary.View.Template

import Databrary.Controller.Static
import {-# SOURCE #-} Databrary.Controller.Angular

ngAttribute :: String -> H.AttributeValue -> H.Attribute
ngAttribute = H.customAttribute . H.stringTag . ("ng-" <>)

public :: [BS.ByteString] -> H.AttributeValue
public p = byteStringValue $ actionURL (staticPublicFile $ staticPath p) Nothing

htmlAngular :: AuthRequest -> H.Html
htmlAngular auth = H.docTypeHtml H.! ngAttribute "ng-app" "databraryModule" $ do
  H.head $ do
    htmlHeader req
    H.noscript $
      H.meta
        H.! HA.httpEquiv "Refresh"
        H.! HA.content (builderValue $ BSB.string7 "0;url=" <> nojs)
    H.meta
      H.! HA.httpEquiv "X-UA-Compatible"
      H.! HA.content "IE=edge"
    H.meta 
      H.! HA.name "viewport"
      H.! HA.content "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"
    H.title
      H.! ngAttribute "bind" "page.display.title + ' || Databrary'"
      $ "Databrary"
    forM_ [Just "114x114", Just "72x72", Nothing] $ \size ->
      H.link
        H.! HA.rel "apple-touch-icon-precomposed"
        H.! HA.href (public ["icons", "apple-touch-icon" <> maybe "" (BSC.cons '-') size <> ".png"])
        !? (HA.sizes . byteStringValue <$> size)
    H.link
      H.! HA.rel "stylesheet"
      H.! HA.href (public ["app.min.css"])
    H.script $ do
      H.preEscapedString "window.$play={user:"
      H.unsafeLazyByteString $ JSON.encode $ identityJSON (view auth)
      H.preEscapedString "};"
    forM_ [] $ \js ->
      H.script
        H.! HA.src (public js)
        $ return ()
    H.script
      H.! HA.src (byteStringValue $ actionURL angularConstants Nothing)
      $ return ()
  H.body
    H.! H.customAttribute "flow-prevent-drop" mempty
    $ do
    H.noscript $ do
      H.preEscapedString "Our site works best with modern browsers (Firefox, Chrome, Safari &ge;6, IE &ge;10, and others) with Javascript enabled.  You can also switch to the "
      H.a
        H.! HA.href (builderValue nojs)
        $ "simple version"
      H.preEscapedString " of this page."
    H.preEscapedString "<toolbar></toolbar>"
    H.preEscapedString "<main ng-view id=\"main\" class=\"main\" autoscroll ng-if=\"!page.display.error\"></main>"
    H.preEscapedString "<errors></errors>"
    htmlFooter
    H.preEscapedString "<messages></messages>"
    H.preEscapedString "<tooltip ng-repeat=\"tooltip in page.tooltips.list track by tooltip.id\" ng-if=\"tooltip.target\"></tooltip>"
    H.div
      H.! HA.id "loading"
      H.! HA.class_ "loading"
      H.! HA.style "display:none"
      H.! ngAttribute "show" "page.display.loading" $ 
      H.div H.! HA.class_ "loading-animation" $ do
        H.div H.! HA.class_ "loading-spinner" $
          H.div H.! HA.class_ "loading-mask" $
            H.div H.! HA.class_ "loading-cicle" $
              return ()
        H.div H.! HA.class_ "loading-text" $ do
          "["
          H.span "loading"
          "]"
    H.script
      $ H.preEscapedString "document.getElementById('loading').style.display='block';"
  where
  req = view auth
  nojs = snd $ jsURL (Just False) req
