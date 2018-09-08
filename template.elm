module TimeZone exposing
    ( getZone, Error(..)
    , zones
    , ZONE_IDS
    , version
    )

{-| This library provides time zone data from the `VERSION` release of the IANA
Time Zone Database.


## Local zone

@docs getZone, Error


## Zones

@docs zones

---

Each unevaluated zone is named after its zone name (e.g.
`America/New_York`), where slashes are replaced by `__`, dashes are replaced
by `_`, and the name is lowercased. For example, `America/Port-au-Prince`
becomes `america__port_au_prince`.

@docs ZONE_IDS


## Metadata

@docs version

-}

import Dict exposing (Dict)
import Task exposing (Task)
import Time exposing (Month(..), Weekday(..))
import TimeZone.Specification exposing (Clock(..), DateTime, DayOfMonth(..), Rule, Zone, ZoneRules(..), ZoneState)


{-| What version of the IANA Time Zone Database is this data from?
-}
version : String
version =
    "VERSION"


minYear : Int
minYear =
    MIN_YEAR


maxYear : Int
maxYear =
    MAX_YEAR


fromSpecification : Zone -> Time.Zone
fromSpecification zone =
    let
        ( descending, bottom ) =
            zone |> TimeZone.Specification.toOffsets minYear maxYear
    in
    Time.customZone bottom descending


{-| Represents an error that may occur when trying to get the local zone.
-}
type Error
    = NoZoneName
    | NoDataForZoneName String


{-| Try to get the local time zone. If the task succeeds, then you get the zone
name along with the `Time.Zone`.
-}
getZone : Task Error ( String, Time.Zone )
getZone =
    Time.getZoneName
        |> Task.andThen
            (\nameOrOffset ->
                case nameOrOffset of
                    Time.Name zoneName ->
                        case Dict.get zoneName zones of
                            Just zone ->
                                Task.succeed ( zoneName, zone () )

                            Nothing ->
                                Task.fail (NoDataForZoneName zoneName)

                    Time.Offset _ ->
                        Task.fail NoZoneName
            )


{-| You can look up an unevaluated zone by its zone name in the `zones` dictionary.

    import Dict
    import TimeZone exposing (zones, america__new_york)


    Dict.get "America/New_York" zones

    -- Just america__new_york

-}
zones : Dict String (() -> Time.Zone)
zones =
    [ ZONE_NAME_ID_PAIRS
    ]
        |> Dict.fromList
