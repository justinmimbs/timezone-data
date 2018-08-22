module TimeZone.Data exposing (..)

import Time exposing (Month(..), Weekday(..))
import TimeZone.Types exposing (..)


type alias Pack =
    TimeZone.Types.Pack



-- Bounds


min : Year
min =
    1970


max : Year
max =
    2037



-- Rules


us : List Rule
us =
    [ Rule 1967 2006 Oct (Last Sun) (2 * 60) WallClock 0
    , Rule 1967 1973 Apr (Last Sun) (2 * 60) WallClock (1 * 60)
    , Rule 1974 1974 Jan (Day 6) (2 * 60) WallClock (1 * 60)
    , Rule 1975 1975 Feb (Day 23) (2 * 60) WallClock (1 * 60)
    , Rule 1976 1986 Apr (Last Sun) (2 * 60) WallClock (1 * 60)
    , Rule 1987 2006 Apr (First Sun OnOrAfterDay 1) (2 * 60) WallClock (1 * 60)
    , Rule 2007 max Mar (First Sun OnOrAfterDay 8) (2 * 60) WallClock (1 * 60)
    , Rule 2007 max Nov (First Sun OnOrAfterDay 1) (2 * 60) WallClock 0
    ]



-- Zones


america__new_york : Pack
america__new_york =
    Packed <|
        Zone
            []
            (ZoneState (-5 * 60) (Rules us))


america__indiana__indianapolis : Pack
america__indiana__indianapolis =
    Packed <|
        Zone
            [ ( ZoneState (-5 * 60) (Rules us), DateTime 1971 Jan 1 0 )
            , ( ZoneState (-5 * 60) (Save 0), DateTime 2006 Jan 1 0 )
            ]
            (ZoneState (-5 * 60) (Rules us))



-- Zones by name


packs =
    [ ( "America/New_York", america__new_york )
    , ( "America/Indiana/Indianapolis", america__indiana__indianapolis )
    ]