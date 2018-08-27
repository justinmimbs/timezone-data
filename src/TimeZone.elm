module TimeZone
    exposing
        ( Error(..)
        , getZone
        , unpack
          -- expose for testing
        , unpackOffsets
        )

import Dict
import RataDie exposing (RataDie)
import Task exposing (Task)
import Time exposing (Month(..), Weekday(..))
import TimeZone.Data
import TimeZone.Types exposing (..)


type Error
    = NoZoneName
    | NoDataForZoneName String


getZone : Task Error ( String, Time.Zone )
getZone =
    Time.getZoneName
        |> Task.andThen
            (\nameOrOffset ->
                case nameOrOffset of
                    Time.Name zoneName ->
                        case Dict.get zoneName TimeZone.Data.packs of
                            Just pack ->
                                Task.succeed ( zoneName, unpack pack )

                            Nothing ->
                                Task.fail (NoDataForZoneName zoneName)

                    Time.Offset _ ->
                        Task.fail NoZoneName
            )



-- unpack TimeZone.Data


unpack : TimeZone.Data.Pack -> Time.Zone
unpack pack =
    let
        { changes, initial } =
            unpackOffsets pack
    in
    Time.customZone initial changes


unpackOffsets : Pack -> { changes : List { start : Int, offset : Int }, initial : Int }
unpackOffsets (Packed zone) =
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
                    (DateTime TimeZone.Data.minYear Jan 1 0)
                    (DateTime TimeZone.Data.maxYear Dec 31 0)
                |> List.foldl
                    (\( start, state, until ) ( prevOffset, prevChanges ) ->
                        let
                            ( nextChanges, nextOffset ) =
                                stateToOffsetChanges prevOffset start until state
                        in
                        ( nextOffset, prevChanges ++ nextChanges )
                    )
                    ( initialOffset, [] )
                |> Tuple.second
                |> stripDuplicatesByHelp .offset initialOffset []
                |> List.reverse
    in
    { changes = offsetChanges
    , initial = initialOffset
    }


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


stateToOffsetChanges : Int -> DateTime -> DateTime -> ZoneState -> ( List { start : Int, offset : Int }, Int )
stateToOffsetChanges previousOffset start until { standardOffset, zoneRules } =
    case zoneRules of
        Save save ->
            ( [ { start = minutesFromDateTime start - previousOffset
                , offset = standardOffset + save
                }
              ]
            , standardOffset + save
            )

        Rules rules ->
            rulesToOffsetChanges previousOffset start until standardOffset rules


rulesToOffsetChanges : Int -> DateTime -> DateTime -> Minutes -> List Rule -> ( List { start : Int, offset : Int }, Int )
rulesToOffsetChanges previousOffset start until standardOffset rules =
    let
        rulesStart =
            minutesFromDateTime start

        rulesUntil =
            minutesFromDateTime until

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

                                                First weekday onOrAfterDay ->
                                                    RataDie.dayOfMonth year rule.month onOrAfterDay
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

        ( nextOffset, initialChange, descendingChanges ) =
            transitions
                |> List.foldl
                    (\transition ( currentOffset, change0, changes ) ->
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
                        if transition.start <= rulesStart then
                            ( change.offset, { change0 | offset = change.offset }, changes )

                        else if transition.start < rulesUntil then
                            ( change.offset, change0, change :: changes )

                        else
                            ( currentOffset, change0, changes )
                    )
                    ( previousOffset
                    , { start = rulesStart - previousOffset
                      , offset = standardOffset
                      }
                    , []
                    )
    in
    ( initialChange :: List.reverse descendingChanges, nextOffset )



-- time helpers


minutesFromDateTime : DateTime -> Int
minutesFromDateTime { year, month, day, time } =
    minutesFromRataDie (RataDie.dayOfMonth year month day) + time


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
