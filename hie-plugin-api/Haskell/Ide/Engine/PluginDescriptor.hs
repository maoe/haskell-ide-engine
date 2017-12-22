{-# LANGUAGE OverloadedStrings    #-}
-- | A data structure to define a plugin.
-- Allows description of a plugin and the commands it provides

module Haskell.Ide.Engine.PluginDescriptor
  ( runPluginCommand
  , pluginDescToIdePlugins
  , dynToJSON
  , fromDynJSON
  ) where

import           Control.Monad.State.Strict
import           Data.Aeson
import           Data.List
import qualified Data.Map                        as Map
import           Data.Monoid
import qualified Data.Text                       as T
import qualified Data.ConstrainedDynamic         as CD
import           Data.Typeable
import           Haskell.Ide.Engine.IdeFunctions
import           Haskell.Ide.Engine.MonadTypes

pluginDescToIdePlugins :: [(PluginId,PluginDescriptor)] -> IdePlugins
pluginDescToIdePlugins = IdePlugins . foldr (uncurry Map.insert . f) Map.empty
  where f = fmap pluginCommands

type DynamicJSON = CD.ConstrainedDynamic ToJSON

dynToJSON :: DynamicJSON -> Value
dynToJSON x = CD.applyClassFn x toJSON

fromDynJSON :: (Typeable a, ToJSON a) => DynamicJSON -> Maybe a
fromDynJSON = CD.fromDynamic

-- | Runs a plugin command given a PluginId, CommandName and
-- arguments in the form of a JSON object.
runPluginCommand :: PluginId -> CommandName -> Value -> IdeGhcM (IdeResponse DynamicJSON)
runPluginCommand p com arg = do
  (IdePlugins m) <- lift . lift $ getPlugins
  case Map.lookup p m of
    Nothing -> return $
      IdeResponseFail $ IdeError UnknownPlugin ("Plugin " <> p <> " doesn't exist") Null
    Just xs -> case find ((com ==) . commandName) xs of
      Nothing -> return $ IdeResponseFail $
        IdeError UnknownCommand ("Command " <> com <> " isn't defined for plugin " <> p <> ". Legal commands are: " <> T.pack(show $ map commandName xs)) Null
      Just (PluginCommand _ _ (CmdSync f)) -> case fromJSON arg of
        Error err -> return $ IdeResponseFail $
          IdeError ParameterError ("error while parsing args for " <> com <> " in plugin " <> p <> ": " <> T.pack err) Null
        Success a -> do
            res <- f a
            return $ fmap (CD.toDyn) res
