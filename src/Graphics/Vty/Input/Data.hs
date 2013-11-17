-- Copyright Corey O'Connor
module Graphics.Vty.Input.Data where

-- | Representations of non-modifier keys.
--
-- KFun is indexed from 0 to 63. Range of supported FKeys varies by terminal and keyboard.
data Key = KEsc | KFun Int | KBackTab | KPrtScr | KPause | KASCII Char | KBS | KIns
         | KHome | KPageUp | KDel | KEnd | KPageDown | KBegin |  KNP5 | KUp | KMenu
         | KLeft | KDown | KRight | KEnter
    deriving (Eq,Show,Ord)

-- | Modifier keys.  Key codes are interpreted such that users are more likely to
-- have Meta than Alt; for instance on the PC Linux console, 'MMeta' will
-- generally correspond to the physical Alt key.
data Modifier = MShift | MCtrl | MMeta | MAlt
    deriving (Eq,Show,Ord)

-- | Mouse buttons.  Not yet used.
data Button = BLeft | BMiddle | BRight
    deriving (Eq,Show,Ord)

-- | Generic events.
data Event = EvKey Key [Modifier] | EvMouse Int Int Button [Modifier]
           | EvResize Int Int
    deriving (Eq,Show,Ord)

type ClassifyTable = [(String, (Key, [Modifier]))]

map_to_legacy_table :: [(String, Event)] -> ClassifyTable
map_to_legacy_table = map f
    where f (s, EvKey k mods) = (s, (k, mods))
          f _                 = error "no mapping for mouse or resize events"

-- | classify table directly generated from terminfo cap strings
keys_from_caps_table :: [(String, Event)]
keys_from_caps_table =
    [ ("khome", EvKey KHome     [])
    , ("kend",  EvKey KEnd      [])
    , ("cbt",   EvKey KBackTab  [])
    , ("kcud1", EvKey KDown     [])
    , ("kcuu1", EvKey KUp       [])
    , ("kcuf1", EvKey KRight    [])
    , ("kcub1", EvKey KLeft     [])
    , ("kLFT",  EvKey KLeft     [MShift])
    , ("kRIT",  EvKey KRight    [MShift])
    ] ++ function_key_caps_table

function_key_caps_table :: [(String, Event)]
function_key_caps_table = flip map [0..63] $ \n -> ("kf" ++ show n, EvKey (KFun n) [])

nav_keys_0 :: ClassifyTable
nav_keys_0 =
    [ k "G" KNP5
    , k "P" KPause
    , k "A" KUp
    , k "B" KDown
    , k "C" KRight
    , k "D" KLeft
    , k "H" KHome
    , k "F" KEnd
    , k "E" KBegin
    ]
    where k c s = ("\ESC["++c,(s,[]))

-- Support for arrows and KHome/KEnd
nav_keys_1 :: ClassifyTable
nav_keys_1 =
   [("\ESC[" ++ charCnt ++ show mc++c,(s,m))
    | charCnt <- ["1;", ""], -- we can have a count or not
    (m,mc) <- [([MShift],2::Int), ([MCtrl],5), ([MMeta],3),
               ([MShift, MCtrl],6), ([MShift, MMeta],4)], -- modifiers and their codes
    (c,s) <- [("A", KUp), ("B", KDown), ("C", KRight), ("D", KLeft), ("H", KHome), ("F", KEnd)] -- directions and their codes
   ]

nav_keys_2 :: ClassifyTable
nav_keys_2 =
    let k n s = ("\ESC["++show n++"~",(s,[]))
    in zipWith k [2::Int,3,5,6,1,4]
                 [KIns,KDel,KPageUp,KPageDown,KHome,KEnd]

nav_keys_3 :: ClassifyTable
nav_keys_3 =
    let k n s = ("\ESC["++show n++";5~",(s,[MCtrl]))
    in zipWith k [2::Int,3,5,6,1,4]
                 [KIns,KDel,KPageUp,KPageDown,KHome,KEnd]

-- Support for simple characters.
-- we limit to < 0xC1. The UTF8 sequence detector will catch all values 0xC2 and above before this
-- classify table is reached.
--
-- TODO: resolve
-- 1. start at ' '. The earlier characters are all ctrl_char_keys
simple_chars :: ClassifyTable
simple_chars = [(x:[],(KASCII x,[])) | x <- [' ' .. toEnum 0xC1]]

-- TODO: Support for function keys (should use terminfo)
-- 
-- (corey): yes. This definitely should. On my terminal these keys do not operate as expected.
-- function_keys_0 :: ClassifyTable
-- function_keys_0 = [ ("\ESC[["++[toEnum(64+i)],(KFun i,[])) | i <- [1..5] ]

-- TODO: I suspect this should be generated by interpretting the terminals use of meta mode:
-- "If the terminal has a ``meta key'' which acts as a shift key, setting the 8th bit of any
-- character transmitted, this fact can be indicated with  km.   Other- wise,  software  will
-- assume that the 8th bit is parity and it will usually be cleared.  If strings exist to turn this
-- ``meta mode'' on and off, they can be given as smm and rmm."
--
-- That is more complex that below. I cannot fault the original author for just hard coding a table
-- ;-)
function_keys_1 :: ClassifyTable
function_keys_1 =
    let f ff nrs m = [ ("\ESC["++show n++"~",(KFun (n-(nrs!!0)+ff), m)) | n <- nrs ] in
    concat [f 1 [25,26] [MShift], f 3 [28,29] [MShift], f 5 [31..34] [MShift] ]

-- TODO: resolve -
--
-- 1. removed 'ESC' from second list due to duplication with "special_support_keys".
-- 2. removed '[' from second list due to conflict with 7-bit encoding for ESC. Whether meta+[ is
-- the same as ESC should examine km and current encoding.
-- 3. stopped enumeration at '~' instead of '\DEL'. The latter is mapped to KBS by
-- special_support_keys.
function_keys_2 :: ClassifyTable
function_keys_2 = [ ('\ESC':[x],(KASCII x,[MMeta])) | x <- '\t':[' ' .. '~'],
                                                      x /= '[']

-- Ctrl+Char
ctrl_char_keys :: ClassifyTable
ctrl_char_keys =
    [ ([toEnum x],(KASCII y,[MCtrl]))
    | (x,y) <- zip ([0..31]) ('@':['a'..'z']++['['..'_']),
               y /= 'i' -- Resolve issue #3 where CTRL-i hides TAB.
    ]

-- Ctrl+Meta+Char
-- 
-- TODO: CTRL-i is the same as tab thing
ctrl_meta_keys :: ClassifyTable
ctrl_meta_keys =
    [ ('\ESC':[toEnum x],(KASCII y,[MMeta,MCtrl])) | (x,y) <- zip [0..31] ('@':['a'..'z']++['['..'_']),
                                                     y /= 'i'
    ]

-- Special support
special_support_keys :: ClassifyTable
special_support_keys =
    [ -- special support for ESC
      ("\ESC",(KEsc,[])) , ("\ESC\ESC",(KEsc,[MMeta]))
    -- Special support for backspace
    , ("\DEL",(KBS,[])), ("\ESC\DEL",(KBS,[MMeta]))
    -- Special support for Enter
    , ("\ESC\^J",(KEnter,[MMeta])), ("\^J",(KEnter,[]))
    ]

-- | classify table for ANSI terminals
ansi_classify_table :: [ClassifyTable]
ansi_classify_table =
    [ nav_keys_0
    , nav_keys_1
    , nav_keys_2
    , nav_keys_3
    , simple_chars
    , function_keys_1
    , function_keys_2
    , ctrl_char_keys
    , ctrl_meta_keys
    , special_support_keys
    ]
