module TimeZone exposing (unpack)

import RataDie exposing (RataDie)
import Time exposing (Month(..), Weekday(..))
import TimeZone.Data
import TimeZone.Types exposing (..)


unpack : Pack -> ( List { start : Int, offset : Int }, Int )
unpack (Packed zone) =
    let
        initialState =
            case zone.history of
                ( earliest, _ ) :: _ ->
                    earliest

                [] ->
                    zone.current

        initialOffset =
            initialState.standardOffset
                + (case initialState.zoneRules of
                    Save save ->
                        save

                    _ ->
                        0
                  )

        offsetChanges =
            zone
                |> zoneToRanges
                    (DateTime TimeZone.Data.min Jan 1 0)
                    (DateTime TimeZone.Data.max Dec 31 0)
                |> List.concatMap
                    (\( start, state, until ) -> stateToOffsetChanges start until state)
                |> stripDuplicatesBy .offset
                |> List.reverse
    in
    ( offsetChanges, initialOffset )


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
            [ { start = minutesFromDateTime start - standardOffset
              , offset = standardOffset + save
              }
            ]

        Rules rules ->
            rulesToOffsetChanges start until standardOffset rules


rulesToOffsetChanges : DateTime -> DateTime -> Minutes -> List Rule -> List { start : Int, offset : Int }
rulesToOffsetChanges start until standardOffset rules =
    let
        years =
            List.range start.year until.year

        transitions : List { start : Int, clock : Clock, save : Minutes }
        transitions =
            years
                |> List.concatMap
                    (\year ->
                        rules
                            |> List.filter
                                (\rule -> rule.from <= year && year <= rule.to)
                            |> List.map
                                (\rule ->
                                    { start =
                                        -- date
                                        minutesFromRataDie
                                            (case rule.day of
                                                Day day ->
                                                    RataDie.dayOfMonth year rule.month day

                                                First weekday OnOrAfterDay day ->
                                                    RataDie.dayOfMonth year rule.month day
                                                        |> RataDie.ceilingWeekday weekday

                                                Last weekday ->
                                                    RataDie.lastOfMonth year rule.month
                                                        |> RataDie.floorWeekday weekday
                                            )
                                            -- time
                                            + rule.time
                                    , clock =
                                        rule.clock
                                    , save =
                                        rule.save
                                    }
                                )
                            |> List.sortBy .start
                    )
    in
    transitions
        |> List.foldl
            (\transition ( currentOffset, changes ) ->
                let
                    utcAdjustment =
                        case transition.clock of
                            Universal ->
                                0

                            Standard ->
                                0 - standardOffset

                            WallClock ->
                                0 - currentOffset

                    change =
                        { start = transition.start + utcAdjustment
                        , offset = standardOffset + transition.save
                        }
                in
                ( standardOffset + transition.save
                , if minutesFromDateTime start <= transition.start && transition.start < minutesFromDateTime until then
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
minutesFromDateTime { year, month, day, time } =
    minutesFromRataDie (RataDie.dayOfMonth year month day)
        + time


minutesFromRataDie : RataDie -> Int
minutesFromRataDie rd =
    (rd - 719163) * 1440



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