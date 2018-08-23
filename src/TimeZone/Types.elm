module TimeZone.Types exposing (..)

import Time exposing (Month(..), Weekday(..))


type alias Year =
    Int


type alias Minutes =
    Int


type DayOfMonth
    = Day Int
    | First Weekday Int
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
    , time : Minutes
    , clock : Clock

    -- to state
    , save : Minutes -- add to Standard time
    }


type ZoneRules
    = Save Minutes
    | Rules (List Rule)


type alias ZoneState =
    { standardOffset : Minutes
    , zoneRules : ZoneRules
    }


type alias DateTime =
    { year : Year
    , month : Month
    , day : Int
    , time : Minutes
    }


type alias Zone =
    { history : List ( ZoneState, DateTime )
    , current : ZoneState
    }


type Pack
    = Packed Zone
