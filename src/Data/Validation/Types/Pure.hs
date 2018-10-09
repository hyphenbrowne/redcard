{-# LANGUAGE Rank2Types #-}
module Data.Validation.Types.Pure where

import            Control.Applicative
import qualified  Data.Map.Strict as Map
import qualified  Data.Set as Set
import            Data.Scientific
import qualified  Data.Text as Text
import qualified  Data.Vector as Vec

newtype Validator a = Validator {
    run :: forall input. Validatable input => input -> ValidationResult a
  }

class Validatable input where
  inputText :: input -> Maybe Text.Text
  inputBool :: input -> Maybe Bool
  inputNull :: input -> Maybe ()
  arrayItems :: input -> Maybe (Vec.Vector input)
  scientificNumber :: input -> Maybe Scientific
  lookupChild :: Text.Text -> input -> Lookup input


data Lookup input = LookupResult (Maybe input)
                  | InvalidLookup

data ValidationResult a =
    Valid a
  | Invalid Errors
  deriving (Eq, Show)

data Errors =
    Messages (Set.Set Text.Text)
  | Group (Map.Map Text.Text Errors)
  deriving (Eq, Show)

-- Helpers for building primitive validators

errMessage :: Text.Text -> Errors
errMessage text = Messages (Set.singleton text)

nestErrors :: Text.Text -> Errors -> Errors
nestErrors attr err = Group (Map.singleton attr err)

mapResult :: (ValidationResult a -> ValidationResult b)
          -> Validator a -> Validator b
mapResult f v = Validator $ \value -> f (run v value)

mapErrors :: (Errors -> Errors) -> ValidationResult a -> ValidationResult a
mapErrors f (Invalid errs) = Invalid (f errs)
mapErrors _ valid = valid

-- Instances

instance Monoid Errors where
  mempty = Messages Set.empty
  (Messages m) `mappend` (Messages m') = Messages (m `mappend` m')
  (Group g) `mappend` (Group g') = Group (Map.unionWith mappend g g')
  g `mappend` m@(Messages _) = g `mappend` nestErrors "" m
  m `mappend` g = nestErrors "" m `mappend` g

instance Monoid a => Monoid (ValidationResult a) where
  mempty = Valid mempty
  (Valid a) `mappend` (Valid a') = Valid (a `mappend` a')
  (Invalid e) `mappend` (Invalid e') = Invalid (e `mappend` e')
  (Valid _) `mappend` invalid = invalid
  invalid `mappend` (Valid _) = invalid

instance Functor ValidationResult where
  f `fmap` (Valid a) = Valid (f a)
  _ `fmap` (Invalid errors) = Invalid errors

instance Applicative ValidationResult where
  pure = Valid

  (Valid f) <*> (Valid a) = Valid (f a)
  (Invalid errs) <*> (Invalid errs') = Invalid (errs `mappend` errs')
  Invalid errs <*> _ = Invalid errs
  _ <*> Invalid errs = Invalid errs

instance Functor Validator where
  f `fmap` v = mapResult (fmap f) v

instance Applicative Validator where
  pure a = Validator (const (pure a))
  v <*> v' = Validator $ \value -> run v value <*> run v' value

instance Monad Validator where
  v >>= f = Validator $ \input ->
              case run v input of
              Invalid errors -> Invalid errors
              Valid a -> run (f a) input

  fail str = Validator $ \_ -> Invalid (errMessage (Text.pack str))

instance Functor Lookup where
  fmap _ InvalidLookup = InvalidLookup
  fmap f (LookupResult r) = LookupResult (fmap f r)

instance Applicative Lookup where
  pure = LookupResult . pure

  InvalidLookup <*> _ = InvalidLookup
  _ <*> InvalidLookup = InvalidLookup
  (LookupResult f) <*> (LookupResult a) = LookupResult (f <*> a)

instance Alternative Lookup where
  empty = LookupResult Nothing

  InvalidLookup <|> other = other
  other <|> InvalidLookup = other
  (LookupResult a) <|> (LookupResult b) = LookupResult (a <|> b)

