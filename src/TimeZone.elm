module TimeZone exposing (unpack)

import RataDie exposing (RataDie)
import Time exposing (Month(..), Weekday(..))
import TimeZone.Data
import TimeZone.Types exposing (..)


unpack : Pack -> List { start : Int, offset : Int }
unpack (Packed zone) =
    let
        ranges =
            zone
                |> zoneToRanges
                    (DateTime TimeZone.Data.min Jan 1 0)
                    (DateTime (TimeZone.Data.max + 1) Jan 1 0)
    in
    ranges
        |> List.concatMap
            (\( start, state, until ) -> stateToOffsetChanges start until state)
        |> stripDuplicatesBy .offset


zoneToRanges : DateTime -> DateTime -> Zone -> List ( DateTime, ZoneState, DateTime )
zoneToRanges zoneStart zoneUntil zone =
    let
        ( currentStart, historyRanges ) =
            List.foldl
                (\( state, nextStart ) ( start, ranges ) ->
                    ( nextStart
                    , ( start, state, nextStart ) :: ranges
                    )
                )
                ( zoneStart, [] )
                zone.history
    in
    ( currentStart, zone.current, zoneUntil ) :: historyRanges |> List.reverse


stateToOffsetChanges : DateTime -> DateTime -> ZoneState -> List { start : Int, offset : Int }
stateToOffsetChanges start until { standardOffset, zoneRules } =
    case zoneRules of
        Save save ->
            [ { start = minutesFromDateTime start - minutesFromHours standardOffset
              , offset = minutesFromHours (standardOffset + save)
              }
            ]

        Rules rules ->
            rulesToOffsetChanges start until standardOffset rules


rulesToOffsetChanges : DateTime -> DateTime -> Hour -> List Rule -> List { start : Int, offset : Int }
rulesToOffsetChanges start until standardOffset rules =
    let
        startMinutes =
            minutesFromDateTime start

        untilMinutes =
            minutesFromDateTime until

        years =
            List.range start.year until.year

        transitions : List { time : Int, clock : Clock, save : Hour }
        transitions =
            years
                |> List.concatMap
                    (\year ->
                        rules
                            |> List.filter
                                (\rule -> rule.from <= year && year <= rule.to)
                            |> List.map
                                (\rule ->
                                    { time =
                                        -- date
                                        minutesFromRataDie
                                            (case rule.day of
                                                Day day ->
                                                    RataDie.dayOfMonth year rule.month day

                                                First weekday OnOrAfterDay day ->
                                                    RataDie.dayOfMonth year rule.month day |> RataDie.ceilingWeekday weekday

                                                Last weekday ->
                                                    RataDie.lastOfMonth year rule.month |> RataDie.floorWeekday weekday
                                            )
                                            -- hour
                                            + minutesFromHours
                                                rule.hour
                                    , clock =
                                        rule.clock
                                    , save =
                                        rule.save
                                    }
                                )
                            |> List.sortBy .time
                    )
    in
    transitions
        |> List.foldl
            (\transition ( currentOffset, changes ) ->
                let
                    utcAdjustment =
                        minutesFromHours
                            (case transition.clock of
                                Universal ->
                                    0.0

                                Standard ->
                                    0.0 - standardOffset

                                WallClock ->
                                    0.0 - currentOffset
                            )

                    change =
                        { start = transition.time + utcAdjustment
                        , offset = minutesFromHours (standardOffset + transition.save)
                        }
                in
                ( standardOffset + transition.save
                , if startMinutes <= transition.time && transition.time < untilMinutes then
                    change :: changes

                  else
                    changes
                )
            )
            ( standardOffset, [] )
        |> Tuple.second
        |> List.reverse



-- time helpers


minutesFromDateTime : DateTime -> Int
minutesFromDateTime { year, month, day, hour } =
    minutesFromRataDie (RataDie.dayOfMonth year month day)
        + minutesFromHours hour


minutesFromRataDie : RataDie -> Int
minutesFromRataDie rd =
    (rd - 719163) * 1440


minutesFromHours : Hour -> Int
minutesFromHours hours =
    hours * 60 |> floor



-- List


stripDuplicatesBy : (a -> b) -> List a -> List a
stripDuplicatesBy f list =
    case list of
        [] ->
            list

        x :: xs ->
            stripDuplicatesByHelp f (f x) [ x ] xs


stripDuplicatesByHelp : (a -> b) -> b -> List a -> List a -> List a
stripDuplicatesByHelp f a rev list =
    case list of
        [] ->
            List.reverse rev

        x :: xs ->
            let
                b =
                    f x

                rev_ =
                    if a /= b then
                        x :: rev

                    else
                        rev
            in
            stripDuplicatesByHelp f b rev_ xs
