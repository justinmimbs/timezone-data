module TimeZone.Types exposing (..)

import Time exposing (Month(..), Weekday(..))


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
    , hour : Hour
    , clock : Clock

    -- to state
    , save : Hour -- add to Standard time
    }


type ZoneRules
    = Save Hour
    | Rules (List Rule)


type alias ZoneState =
    { standardOffset : Hour
    , zoneRules : ZoneRules
    }


type alias DateTime =
    { year : Year
    , month : Month
    , day : Int
    , hour : Hour
    }


type alias Zone =
    { history : List ( ZoneState, DateTime )
    , current : ZoneState
    }


type Pack
    = Packed Zone
