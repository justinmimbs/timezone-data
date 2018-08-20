module TimeZone.Data exposing (..)

import Time exposing (Month(..), Weekday(..))



-- Types


type alias Year =
    Int


type alias Hour =
    Float


type OnOrAfterDay
    = OnOrAfterDay


type DayOfMonth
    = Day Int
    | First Weekday OnOrAfterDay Int
    | Last Weekday


type Clock
    = Universal
    | Standard
    | WallClock


type alias Rule =
    { from : Year
    , to : Year

    -- transition time
    , month : Month
    , day : DayOfMonth
    , time : Hour
    , clock : Clock

    -- to state
    , save : Hour -- add to Standard time
    }


type ZoneRules
    = Save Hour
    | Rules (List Rule)


type alias ZoneState =
    { offset : Hour
    , rules : ZoneRules
    }


type DateTime
    = DateTime Year Month Int Hour


type alias Zone =
    { history : List ( ZoneState, DateTime )
    , current : ZoneState
    }



-- Bounds


min : Year
min =
    1970


max : Year
max =
    2038



-- Rules


us : List Rule
us =
    [ Rule 1967 2006 Oct (Last Sun) 2 WallClock 0
    , Rule 1967 1973 Apr (Last Sun) 2 WallClock 1
    , Rule 1974 1974 Jan (Day 6) 2 WallClock 1
    , Rule 1975 1975 Feb (Day 23) 2 WallClock 1
    , Rule 1976 1986 Apr (Last Sun) 2 WallClock 1
    , Rule 1987 2006 Apr (First Sun OnOrAfterDay 1) 2 WallClock 1
    , Rule 2007 max Mar (First Sun OnOrAfterDay 8) 2 WallClock 1
    , Rule 2007 max Nov (First Sun OnOrAfterDay 1) 2 WallClock 0
    ]



-- Zones


america__new_york : Zone
america__new_york =
    Zone
        []
        (ZoneState -5 (Rules us))


america__indiana__indianapolis : Zone
america__indiana__indianapolis =
    Zone
        [ ( ZoneState -5 (Rules us), DateTime 1971 Jan 1 0 )
        , ( ZoneState -5 (Save 0), DateTime 2006 Jan 1 0 )
        ]
        (ZoneState -5 (Rules us))



-- Zone Names


zones =
    [ ( "America/New_York", america__new_york )
    , ( "America/Indiana/Indianapolis", america__indiana__indianapolis )
    ]
