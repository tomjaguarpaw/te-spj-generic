{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}

module Main where

import Control.Arrow ((>>>))
import Data.Functor.Const (Const (Const, getConst))
import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy (Proxy))
import Prelude hiding (pi)

{- Section: Summary of the idea

The idea of this library is to take a sum type like

    data Sum arg1 ... argn = C1 t1 | ... | Cm tm

and systematically generate (e.g. via TH) a Sigma type that is isomorphic to it

    data SumTag = C1 | ... | Cm

    f = \case { C1 -> t1, ..., Cm -> tm }

    Sigma (c :: SumTag). f c

and to take a product type like

    data Sum arg1 ... argn = C t1 tm

and generate a Pi type that is isomorphic to it

    data ProductTag = F1 | ... | Fm

    f = \case { F1 -> t1, ..., Fm -> tm }

    Pi (t :: ProductTag). f t

(The isomorphisms are expressed in this library though sumToSigma,
sigmaToSum, productToPi and piToProduct.)

The hope is that it's easier to work generically with Sigma and Pi
types than arbitrary Haskell data definitions.  Of course, to code up
Sigma and Pi types in Haskell requires a fair bit of machinery, and
that's the bulk of this library!

Overall goal.  Write this generically
   showSum :: (Show a, Show b) => Sum a b -> String

Converting to generic rep
  class IsSum @t (sum :: Type) (sumf :: FunctionSymbol t)
        | sum -> sumf, sumf -> sum
    where
      sumConNames :: Pi t (Const String)
      sumToSigma :: sum -> Sigma t (Newtyped sumf)
      sigmaToSum :: Sigma t (Newtyped sumf) -> sum

  data Sigma t f where
    Sigma :: forall t i k. (Known @t i)   -- Tag
                        => k i            -- Payload, often essentially (Apply t i)
                                          --   wrapped in a newtype
                        -> Sigma t k

In the case of (Sum a b), t will be SumTag.
(Known @t i) is an implicitly-passed value i::t; a singleton type
In our case,
   t=SumTag.
   i::t, say ATag or BTag

eg.   sumToSigma (A 3 :: Sum t1 t2)
         = Sigma @SumTag @ATag @_ (dict :: Known @SumTag ATag)
                                  (MkNewtyped @(MySumF t1 t2) @ATag
                                              (3 :: Apply (MySumF t1 t2) ATag))
-}

----------------------------------------------------------------------------
-- Section: User code
----------------------------------------------------------------------------

-- Currently this library works for types with multiple constructors
-- each with a single field ...
data MySum a b
  = A Int
  | B Bool
  | C a
  | D a
  | E b

-- ... or with a single constructor with multiple fields.
data Product a = Product Int Bool a

-- General ADTs are work-in-progress.  The work-in-progress is under
-- "Attempt at a nested version" below.
data SumOfProducts a b
  = SP1 a b
  | SP2
  | SP3 a
  | SP4 b
  | SP5 Char

-- We can obtain show generically!
showSum :: (Show a, Show b) => MySum a b -> String
showSum = genericShowSum

-- We can obtain show generically!
showProduct :: (Show a) => Product a -> String
showProduct = genericShowProduct

showSumOfProducts :: (Show a, Show b) => SumOfProducts a b -> String
showSumOfProducts = genericShowNested

main :: IO ()
main = do
  mapM_ (putStrLn . showSum) [A 1, B True, C 'x', D 'y', E ()]
  putStrLn (showProduct (Product 1 True 'x'))
  putStrLn (showSumOfProducts (SP1 True 'x'))
  putStrLn (showSumOfProducts @() @() SP2)
  putStrLn (showSumOfProducts @() @() (SP5 'y'))

----------------------------------------------------------------------------
-- Section: Generics library
----------------------------------------------------------------------------

type Sigma :: forall t. (t -> Type) -> Type
data Sigma (f :: t -> Type) where
  MkSigma :: forall t i f. (Known @t i) => f i -> Sigma @t f

-- (Known @t (i::t)) is a witness for (Singleton i)
--   with `know` I can get a value of type Singleton t (i::t)

-- MkSigma :: forall t f. foreach (i::t) -> f i -> Sigma t f
-- Pair of a value (i::t) and a value (v::f i)

{- For (MySum a b),   t = SumTag,
                    sumf = MySumF a b :: FunctionSymbol SumTag = Proxy SumTag -> Type
     Sigma SumTag (NewTyped sumf)  has values like:
        MkSigma ATag (payload::Apply (MySumF a b) ATag = Int)
        MkSigma BTag (payload::Apply (MySumF a b) BTag = Bool)
        MkSigma CTag (payload::Apply (MySumF a b) CTag = a)
        ...

-- Pedagogically this is our Sigma for sums:
data Sigma @t (f::FunctionSymbol t) where
  MkSigma :: forall t (f::FunctionSymbol t).      -- Universal
             forall (i::t).                       -- Existential
             Known @t i                           -- Witness for existential
             => Apply f i                     -- Field value
             -> Sigma @t f                        -- Result

-}

data Dict c where Dict :: (c) => Dict c

type Known :: forall t. t -> Constraint
class Known (i :: t) where
  know :: Singleton i

knowProxy :: forall t i f. (Known @t i) => f i -> Singleton i
knowProxy _ = know @_ @i

-- | @Singleton t@ is the "singleton type" version of @t@
class Tag t where
  data Singleton (i::t) :: Type

  -- | All the types of kind @t@
  type Tags t :: [t]

  data Pi :: (t -> Type) -> Type

  getPi' :: forall (i :: t) (f :: t -> Type). Pi f -> Singleton i -> f i
  makePi :: (forall (i :: t). (Known @t i) => f i) -> Pi f

  knowns :: Singleton i -> Dict (Known @t i)

  traversePi ::
    forall (f :: t -> Type) (g :: t -> Type) m.
    (Applicative m) =>
    (forall (i :: t). Singleton i -> f i -> m (g i)) ->
    Pi f ->
    m (Pi g)

  provideConstraint' ::
    (Foreach t c) =>
    Proxy c ->
    Singleton i ->
    ((c i) => r) ->
    r

makePi' :: (Tag t) => (forall (i :: t). Singleton i -> f i) -> Pi f
makePi' f = makePi (f know)

makePiProxy ::
  (Tag t) => (forall (i :: t). (Known @t i) => Proxy i -> f i) -> Pi f
makePiProxy f = makePi (f Proxy)

getPi ::
  forall t (i :: t) (f :: t -> Type). (Known @t i, Tag t) => Pi f -> f i
getPi pi = getPi' pi know

-- Useful for obtaining @t@ without making it visible in signatures.
-- ToDo: Why not make FunctionSymbol into an empty data type
--  data FunctionSymbol :: Type -> Type
-- Reason: data MySumF :: Type -> Type -> FunctionSymbol SumTag
--     is rejected for not having a Type result.
--     But it too is just a kind-level thing. This should be fine
--     data kind MySumF :: Type -> Type -> FunctionSymbol SumTag
--
-- Ideas:
--    1.  Kind level data type don't need Type result
-- or 2.  Empty data types don't need Type result.

type FunctionSymbol :: Type -> Type -> Type
-- A type (f :: FunctionSymbol s t) represents
-- a type-level function from s to t.
type FunctionSymbol s t = Proxy s -> Proxy t -> Type

-- (Apply f i) is the type of the argument to
--    the data constructor (corresponding to) `i`
--    in the data type (corresponding to) `f`.
--
-- This is the "apply" of a defunctionalized mapping from @t@ to
-- @Type@, represented by the function symbol @f@.  We need this
-- defunctionalized version because we can't partially apply type
-- synonyms.
type family Apply (f :: FunctionSymbol s t) (i :: s) :: t

-- We would prefer this:
-- type family Apply (s :: Type) (i :: TagOf s) :: Type
-- but we got stuck on defining TagOf.

-- | @ForEachField f c@ means that for each @i@ of kind @t@,
-- @Apply f i@ has an instance for @c@.
type Foreach :: forall (t :: Type) -> (t -> Constraint) -> Constraint
type Foreach t c = Foreach' t c (Tags t)

-- | The implementation of @Foreach@
type Foreach' :: forall (t :: Type) -> (t -> Constraint) -> [t] -> Constraint
type family Foreach' t c ts where
  Foreach' _ _ '[] = ()
  Foreach' t c (i : is) = (c i, Foreach' t c is)

-- | Witness to the property of @ForEachField@
provideConstraint ::
  forall (t :: Type) (c :: t -> Constraint) (r :: Type) (i :: t).
  (Tag t) =>
  (Foreach t c) =>
  Singleton i ->
  ((c i) => r) ->
  r
provideConstraint = provideConstraint' (Proxy @c)

type Compose :: FunctionSymbol t u -> (u -> Constraint) -> t -> Constraint
class (c (Apply f i)) => Compose f c i

instance (c (Apply f i)) => Compose f c i

-- | We can't partially apply type families so instead we
-- defunctionalize them to a symbol @f@ and then wrap them up in a
-- newtype for use when we do need to partially apply them.
type Newtyped :: forall t. FunctionSymbol t Type -> t -> Type
newtype Newtyped f i = MkNewtyped {getNewtyped :: Apply f i}

mashPiSigma ::
  (Tag t) =>
  Pi @t f1 ->
  Sigma @t f2 ->
  (forall i. (Known @t i) => f1 i -> f2 i -> r) ->
  r
mashPiSigma pi (MkSigma f) k = k (getPi' pi know) f

traversePi_ ::
  (Applicative m, Tag t) =>
  (forall (i :: t). Singleton i -> f i -> m ()) ->
  Pi @t f ->
  m ()
-- This implementation could be better
traversePi_ f = fmap (const ()) . traversePi (\st -> fmap Const . f st)

toListPi :: (Tag t) => (forall (i :: t). Singleton i -> f i -> a) -> Pi @t f -> [a]
toListPi f = getConst . traversePi_ (\st x -> Const [f st x])

type SumTag :: Type -> Type
-- Takes the user type to a type (usually an enumeration)
--    representing each contructor
--    e.g. instance SumTag (Maybe a) = Bool
type family SumTag sum

type SumField :: forall (sum :: Type) -> FunctionSymbol (SumTag sum) Type
-- Takes the user type to an empty data type
type family SumField sum

-- Sum types will (or could -- that isn't implemented yet) have an
-- instance of this class generated for them
--    e.g.  instance IsSum (Maybe a)
type IsSum :: Type -> Constraint
class Tag (SumTag sum) => IsSum sum where
  sumConName :: forall (i :: SumTag sum). Singleton i -> String
    -- ToDo: we'd prefer to say
    -- sumConName :: forall (i :: SumTag sum). Known i => String
  sumToSigma :: sum -> Sigma (Newtyped (SumField sum))
  sigmaToSum :: Sigma (Newtyped (SumField sum)) -> sum

sumConName' :: forall sum (i :: SumTag sum). (IsSum sum, Known i) => String
sumConName' = sumConName @sum (know @_ @i)

type ProductIndex :: Type -> Type
type family ProductIndex product

type ProductField ::
  forall (product :: Type) -> FunctionSymbol (ProductIndex product) Type
type family ProductField product

-- Product types will (or could -- that isn't implemented yet) have an
-- instance of this class generated for them
type IsProduct :: Type -> Constraint
class (Tag (ProductIndex product)) => IsProduct product where
  productConName :: String
  productToPi :: product -> Pi (Newtyped (ProductField product))
  piToProduct :: Pi (Newtyped (ProductField product)) -> product

-- Section: Client of the generics library, between the generics
-- library and the user.  It provides a generic implementation of
-- Show.

showField ::
  forall t (f :: FunctionSymbol t Type) i.
  (Tag t, Foreach t (Compose f Show)) =>
  Singleton i ->
  Newtyped f i ->
  String
showField t = provideConstraint @_ @(Compose f Show) t show . getNewtyped

genericShowSum ::
  forall sum.
  (IsSum sum,
   Foreach (SumTag sum) (Compose (SumField sum) Show))  -- All fields of sum satisfy Show
  => sum -> String
genericShowSum x
  = case sumToSigma x of
       MkSigma (field :: f tag) -> sumConName' @sum @tag ++ " " ++ showField know field
       -- MkSigma @_ @tag field -> sumConName' @sum @tag ++ " " ++ showField know field

genericShowProduct ::
  forall product.
  ( IsProduct product,
    Foreach (ProductIndex product) (Compose (ProductField product) Show)
  ) =>
  product ->
  String
genericShowProduct x =
  productConName @product ++ " " ++ unwords (toListPi showField (productToPi x))

{- --------------------------------------------------------------------------
-- Section: Generated code
-- The generics library could in principle
-- generate this, but that isn't implemented yet.
--
From data Sum a b = A Int | B Bool | ...
we generate
\* The data type SumTag = ATag | BTag | ...
\* An instance of the class Tag: instance Tag SumTag
\* An instance of the class Known for each data constructor.
\* An empty data type MySumF
\* A type family SumFamily
\* An instance Applys (MySumF a b)
\* An instance for IsSum (Sum a b) (MySumF a b)

-------------------------------------------------------------------------- -}

-- For data Sum

-- | One value for each constructor of the sum type
data MySumTag = ATag | BTag | CTag | DTag | ETag

-- Singleton stuff for MySumTag
instance Known @MySumTag ATag where know = SATag
instance Known @MySumTag BTag where know = SBTag
instance Known @MySumTag CTag where know = SCTag
instance Known @MySumTag DTag where know = SDTag
instance Known @MySumTag ETag where know = SETag

instance Tag MySumTag where
  data Singleton t where
    SATag :: Singleton ATag
    SBTag :: Singleton BTag
    SCTag :: Singleton CTag
    SDTag :: Singleton DTag
    SETag :: Singleton ETag

  knowns = \case
    SATag -> Dict
    SBTag -> Dict
    SCTag -> Dict
    SDTag -> Dict
    SETag -> Dict

  data Pi f = PiSMySumTag (f ATag) (f BTag) (f CTag) (f DTag) (f ETag)
  type Tags MySumTag = [ATag, BTag, CTag, DTag, ETag]
  getPi' (PiSMySumTag f1 f2 f3 f4 f5) = \case
    SATag -> f1
    SBTag -> f2
    SCTag -> f3
    SDTag -> f4
    SETag -> f5
  makePi f = PiSMySumTag f f f f f

  traversePi f (PiSMySumTag a b c d e) =
    PiSMySumTag <$> f know a <*> f know b <*> f know c <*> f know d <*> f know e

  provideConstraint' = \_ -> \case
    SATag -> \r -> r
    SBTag -> \r -> r
    SCTag -> \r -> r
    SDTag -> \r -> r
    SETag -> \r -> r

-- | A empty data type, used so that we can defunctionalize the mapping
-- @SumFamily@
-- ToDo: use data kind?
data MySumF :: Type -> Type -> FunctionSymbol MySumTag Type
            -- Type -> Type -> Proxy MySumTag -> Type

-- This is what we really want:
--   type family Apply (s :: Type) (i :: TagOf s) :: Type
--   type instance Apply (MySum a b) ATag = Int
--
-- Need instance TagOf (MySum a b) = MySumTag  See #12088
-- Manually fix with empty TH splice $()
--
-- Instead we encode using MySumF

-- type Apply :: FunctionSymbol s t -> s -> t
type instance Apply (MySumF a b) ATag = Int
type instance Apply (MySumF a b) BTag = Bool
type instance Apply (MySumF a b) CTag = a
type instance Apply (MySumF a b) DTag = a
type instance Apply (MySumF a b) ETag = b

type instance SumField (MySum a b) = MySumF a b

type instance SumTag (MySum a b) = MySumTag

instance IsSum (MySum a b) where
  sumConName = \case
        SATag -> "A"
        SBTag -> "B"
        SCTag -> "C"
        SDTag -> "D"
        SETag -> "E"

  sumToSigma = \case
    A p -> MkSigma @_ @ATag (MkNewtyped p)
    B p -> MkSigma @_ @BTag (MkNewtyped p)
    C p -> MkSigma @_ @CTag (MkNewtyped p)
    D p -> MkSigma @_ @DTag (MkNewtyped p)
    E p -> MkSigma @_ @ETag (MkNewtyped p)

  sigmaToSum = \case
    MkSigma (f@(getNewtyped -> p)) -> case knowProxy f of
      SATag -> A p
      SBTag -> B p
      SCTag -> C p
      SDTag -> D p
      SETag -> E p

-- For data Product

-- One value for each constructor of the product type
data ProductTag = Field1 | Field2 | Field3

instance Known @ProductTag Field1 where know = SField1

instance Known @ProductTag Field2 where know = SField2

instance Known @ProductTag Field3 where know = SField3

instance Tag ProductTag where
  data Singleton t where
    SField1 :: Singleton Field1
    SField2 :: Singleton Field2
    SField3 :: Singleton Field3

  knowns = \case
    SField1 -> Dict
    SField2 -> Dict
    SField3 -> Dict

  data Pi f = PiSProductTag (f Field1) (f Field2) (f Field3)
  type Tags ProductTag = [Field1, Field2, Field3]

  getPi' (PiSProductTag f1 f2 f3) = \case
    SField1 -> f1
    SField2 -> f2
    SField3 -> f3
  makePi f = PiSProductTag f f f

  traversePi f (PiSProductTag f1 f2 f3) =
    PiSProductTag <$> f know f1 <*> f know f2 <*> f know f3

  provideConstraint' = \_ -> \case
    SField1 -> \r -> r
    SField2 -> \r -> r
    SField3 -> \r -> r

-- | A symbol used so that we can defunctionalize the mapping
-- @ProductFamily@
data ProductF (a :: Type) (s :: Proxy ProductTag) (t :: Proxy Type)

type instance Apply (ProductF a) t = ProductFamily a t 

type family ProductFamily (a :: Type) (t :: ProductTag) :: Type where
  ProductFamily _ Field1 = Int
  ProductFamily _ Field2 = Bool
  ProductFamily a Field3 = a

type instance ProductIndex (Product a) = ProductTag

type instance ProductField (Product a) = ProductF a

instance IsProduct (Product a) where
  productConName = "Product"
  productToPi (Product f1 f2 f3) =
    makePi'
      ( MkNewtyped . \case
          SField1 -> f1
          SField2 -> f2
          SField3 -> f3
      )

  piToProduct pi =
    Product (getField @Field1) (getField @Field2) (getField @Field3)
    where
      getField :: forall i. (Known @ProductTag i) => ProductFamily a i
      getField = getNewtyped (getPi @_ @i pi)

-- Attempt at a nested version

-- Trying to promote constructors of non-uniform (or
-- "non-parametric"?) data types is a mess.  This is the only way I've
-- come up with.  For more details see
--
-- https://mail.haskell.org/pipermail/haskell-cafe/2023-September/136341.html

data NestedProductATag = NA1 | NA2

data NestedProductBTag

data NestedProductCTag = NC1

data NestedProductDTag = ND1

data NestedProductETag = NE1

type family NestedProductTagF a where
  NestedProductTagF ATag = NestedProductATag
  NestedProductTagF BTag = NestedProductBTag
  NestedProductTagF CTag = NestedProductCTag
  NestedProductTagF DTag = NestedProductDTag
  NestedProductTagF ETag = NestedProductETag

type NestedProductTag :: MySumTag -> Type
newtype NestedProductTag (a :: MySumTag)
  = NestedProductTag (NestedProductTagF a)

type SNestedProductATag :: NestedProductTag ATag -> Type
data SNestedProductATag a where
  SNA1 :: SNestedProductATag ('NestedProductTag NA1)
  SNA2 :: SNestedProductATag ('NestedProductTag NA2)

type SNestedProductBTag :: NestedProductTag BTag -> Type
data SNestedProductBTag a

type SNestedProductCTag :: NestedProductTag CTag -> Type
data SNestedProductCTag a where
  SNC1 :: SNestedProductCTag ('NestedProductTag NC1)

type SNestedProductDTag :: NestedProductTag DTag -> Type
data SNestedProductDTag a where
  SND1 :: SNestedProductDTag ('NestedProductTag ND1)

type SNestedProductETag :: NestedProductTag ETag -> Type
data SNestedProductETag a where
  SNE1 :: SNestedProductETag ('NestedProductTag NE1)

type SNestedProductTagF :: forall (a :: MySumTag) -> NestedProductTag a -> Type
type family SNestedProductTagF a where
  SNestedProductTagF ATag = SNestedProductATag
  SNestedProductTagF BTag = SNestedProductBTag
  SNestedProductTagF CTag = SNestedProductCTag
  SNestedProductTagF DTag = SNestedProductDTag
  SNestedProductTagF ETag = SNestedProductETag

instance Known @(NestedProductTag ATag) ('NestedProductTag NA1) where
  know = SNestedProductTag SNA1

instance Known @(NestedProductTag ATag) ('NestedProductTag NA2) where
  know = SNestedProductTag SNA2

instance Known @(NestedProductTag CTag) ('NestedProductTag NC1) where
  know = SNestedProductTag SNC1

instance Known @(NestedProductTag DTag) ('NestedProductTag ND1) where
  know = SNestedProductTag SND1

instance Known @(NestedProductTag ETag) ('NestedProductTag NE1) where
  know = SNestedProductTag SNE1

type TheTags :: forall (a :: MySumTag) -> [NestedProductTag a]
type family TheTags a where
  TheTags ATag = '[ 'NestedProductTag NA1, 'NestedProductTag NA2]
  TheTags BTag = '[]
  TheTags CTag = '[ 'NestedProductTag NC1]
  TheTags DTag = '[ 'NestedProductTag ND1]
  TheTags ETag = '[ 'NestedProductTag NE1]

type ThePi :: forall (a :: MySumTag) -> (NestedProductTag a -> Type) -> Type
type family ThePi a b where
  ThePi ATag f = (f ('NestedProductTag NA1), f ('NestedProductTag NA2))
  ThePi BTag f = ()
  ThePi CTag f = f ('NestedProductTag NC1)
  ThePi DTag f = f ('NestedProductTag ND1)
  ThePi ETag f = f ('NestedProductTag NE1)

instance (Known @MySumTag a) => Tag (NestedProductTag a) where
  newtype Singleton (i :: NestedProductTag a)
      = SNestedProductTag {unSNestedProductTag :: SNestedProductTagF a i}

  type Tags (NestedProductTag a) = TheTags a

  data Pi @(NestedProductTag a) f = NestedPi {unNestedPi :: ThePi a f}

  getPi' =
    unNestedPi
      >>> fmap
        (. unSNestedProductTag)
        ( case know @_ @a of
            SATag -> \(thePi1, thePi2) -> \case
              SNA1 -> thePi1
              SNA2 -> thePi2
            SBTag -> \() -> \case {}
            SCTag -> \thePi -> \case SNC1 -> thePi
            SDTag -> \thePi -> \case SND1 -> thePi
            SETag -> \thePi -> \case SNE1 -> thePi
        )

  knowns =
    unSNestedProductTag >>> case know @_ @a of
      SATag -> \case
        SNA1 -> Dict
        SNA2 -> Dict
      SBTag -> \case {}
      SCTag -> \case SNC1 -> Dict
      SDTag -> \case SND1 -> Dict
      SETag -> \case SNE1 -> Dict

  makePi x = NestedPi $ case know @_ @a of
    SATag -> (x, x)
    SBTag -> ()
    SCTag -> x
    SDTag -> x
    SETag -> x

  traversePi f = traverseNestedPi $ case know @_ @a of
    SATag -> \(thePi1, thePi2) ->
      (,) <$> f know thePi1 <*> f know thePi2
    SBTag -> pure
    SCTag -> f know
    SDTag -> f know
    SETag -> f know
    where
      traverseNestedPi g (NestedPi thePi) =
        NestedPi <$> g thePi

  provideConstraint' = \_ -> case know @_ @a of
    SATag -> \case
      SNestedProductTag SNA1 -> \r -> r
      SNestedProductTag SNA2 -> \r -> r
    SBTag -> \case SNestedProductTag a -> case a of {}
    SCTag -> \case SNestedProductTag SNC1 -> \r -> r
    SDTag -> \case SNestedProductTag SND1 -> \r -> r
    SETag -> \case SNestedProductTag SNE1 -> \r -> r

-- Wow, this WrapPi/BetterConst stuff is some deep magic
type WrapPi ::
  forall (t :: Type).
  forall (f :: t -> Type) ->
  (forall (z :: t). f z -> Type) ->
  t ->
  Type
newtype WrapPi f k s = WrapPi (Pi @(f s) k)

type BetterConst :: forall f. Type -> forall z. f z -> Type
newtype BetterConst t x = BetterConst t

foo :: Sigma @MySumTag (WrapPi NestedProductTag (BetterConst String))
foo =
  MkSigma @_ @ATag
    ( WrapPi
        ( makePi'
            ( \(st :: Singleton i) ->
                case knowns st of
                  Dict ->
                    case know @_ @i of
                      SNestedProductTag SNA1 -> BetterConst "SNA1"
                      SNestedProductTag SNA2 -> BetterConst "SNA2"
            )
        )
    )

-- | A symbol used so that we can defunctionalize the mapping
-- @SumFamily@
data SumOfProductsF (a :: Type) (b :: Type) (s :: MySumTag) (t :: Proxy (NestedProductTag s)) (r :: Proxy Type)

-- Do I need to generalise this?
type instance Apply (SumOfProductsF a b s) t = SumOfProductsFamily a b s t

type SumOfProductsFamily :: Type -> Type -> forall (s :: MySumTag) -> NestedProductTag s -> Type
type family SumOfProductsFamily (a :: Type) (b :: Type) (s :: MySumTag) (t :: NestedProductTag s) :: Type where
  SumOfProductsFamily a _ ATag ('NestedProductTag NA1) = a
  SumOfProductsFamily _ b ATag ('NestedProductTag NA2) = b
  SumOfProductsFamily a _ CTag ('NestedProductTag NC1) = a
  SumOfProductsFamily _ b DTag ('NestedProductTag ND1) = b
  SumOfProductsFamily _ _ ETag ('NestedProductTag NE1) = Char

type Newtyped2 :: Type -> Type -> forall (s :: MySumTag). NestedProductTag s -> Type
newtype Newtyped2 a b (i :: NestedProductTag s) = Newtyped2 {getNewtyped2 :: SumOfProductsFamily a b s i}

type ForeachTopField a b c = ForeachTopField' a b c (Tags MySumTag)

type ForeachTopField' ::
  Type -> Type -> (Type -> Constraint) -> [MySumTag] -> Constraint
type family ForeachTopField' a b c ts where
  ForeachTopField' _ _ _ '[] = ()
  ForeachTopField' a b c (t : ts) =
    (ForeachNestedField a b c t, ForeachTopField' a b c ts)

type ForeachNestedField a b c s =
  ForeachNestedField' a b c s (Tags (NestedProductTag s))

type ForeachNestedField' ::
  Type ->
  Type ->
  (Type -> Constraint) ->
  forall (s :: MySumTag) ->
  [NestedProductTag s] ->
  Constraint
type family ForeachNestedField' a b c s ns where
  ForeachNestedField' _ _ _ _ '[] = ()
  ForeachNestedField' a b c s (n : ns) =
    (c (SumOfProductsFamily a b s n), ForeachNestedField' a b c s ns)

provideConstraintNested ::
  forall a b c (s :: MySumTag) (n :: NestedProductTag s) r.
  (Known @MySumTag s) =>
  (ForeachTopField a b c) =>
  Singleton n ->
  ((c (SumOfProductsFamily a b s n)) => r) ->
  r
provideConstraintNested = case know @_ @s of
  SATag -> \s -> case unSNestedProductTag s of
    SNA1 -> \r -> r
    SNA2 -> \r -> r
  SBTag -> \case {}
  SCTag -> \s -> case unSNestedProductTag s of
    SNC1 -> \r -> r
  SDTag -> \s -> case unSNestedProductTag s of
    SND1 -> \r -> r
  SETag -> \s -> case unSNestedProductTag s of
    SNE1 -> \r -> r

genericShow' ::
  forall a b x.
  (ForeachTopField a b Show) =>
  Pi @MySumTag (Const String) ->
  (x -> Sigma @MySumTag (WrapPi NestedProductTag (Newtyped2 a b))) ->
  x ->
  String
genericShow' pi f x = mashPiSigma pi (f x) $ \(Const conName) (WrapPi fields) ->
  conName
    ++ " "
    ++ unwords
      ( toListPi
          ( \su -> provideConstraintNested @a @b @Show su show . getNewtyped2
          )
          fields
      )

genericShowNested :: (Show a, Show b) => SumOfProducts a b -> String
genericShowNested =
  genericShow' sumOfProductsConNames sumOfProductsToSigmaOfPi

sumOfProductsConNames :: Pi @MySumTag (Const String)
sumOfProductsConNames =
  makePi' $
    Const . \case
      SATag -> "SP1"
      SBTag -> "SP2"
      SCTag -> "SP3"
      SDTag -> "SP4"
      SETag -> "SP5"

sumOfProductsToSigmaOfPi ::
  forall a b.
  SumOfProducts a b ->
  Sigma @MySumTag (WrapPi NestedProductTag (Newtyped2 a b))
sumOfProductsToSigmaOfPi = \case
  SP1 a b -> k $ \case
    SNA1 -> a
    SNA2 -> b
  SP2 -> k @BTag $ \case {}
  SP3 a -> k $ \case
    SNC1 -> a
  SP4 a -> k $ \case
    SND1 -> a
  SP5 a -> k $ \case
    SNE1 -> a
  where
    f ::
      forall s i.
      (Known @(NestedProductTag s) i) =>
      ( SNestedProductTagF s i ->
        SumOfProductsFamily a b s i
      ) ->
      Newtyped2 a b i
    f g = Newtyped2 $ g (unSNestedProductTag (know @_ @i))

    k ::
      forall s.
      (Known @MySumTag s) =>
      ( forall i'.
        (Known @(NestedProductTag s) i') =>
        SNestedProductTagF s i' ->
        SumOfProductsFamily a b s i'
      ) ->
      Sigma @MySumTag (WrapPi NestedProductTag (Newtyped2 a b))
    k g = MkSigma @_ @s (WrapPi (makePi (f g)))
