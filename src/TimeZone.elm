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


type alias Change =
    { start : Int
    , offset : Minutes
    }


type alias Offset =
    { standard : Minutes
    , save : Minutes
    }


unpackOffsets : Pack -> { changes : List Change, initial : Int }
unpackOffsets (Packed zone) =
    let
        initialState =
            case zone.history of
                ( earliest, _ ) :: _ ->
                    earliest

                [] ->
                    zone.current

        initialOffset =
            { standard =
                initialState.standardOffset
            , save =
                case initialState.zoneRules of
                    Save save ->
                        save

                    _ ->
                        0
            }

        ascendingChanges =
            zone
                |> zoneToRanges
                    (DateTime TimeZone.Data.minYear Jan 1 0 Universal)
                    (DateTime (TimeZone.Data.maxYear + 1) Jan 1 0 Universal)
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
                |> stripDuplicatesByHelp .offset (initialOffset.standard + initialOffset.save) []

        ( initial, changes ) =
            dropChangesBeforeEpoch ( initialOffset.standard + initialOffset.save, ascendingChanges )
    in
    { changes = List.reverse changes
    , initial = initial
    }


dropChangesBeforeEpoch : ( Minutes, List Change ) -> ( Minutes, List Change )
dropChangesBeforeEpoch ( initial, changes ) =
    case changes of
        change :: rest ->
            if change.start <= 0 then
                dropChangesBeforeEpoch ( change.offset, rest )

            else
                ( initial, changes )

        [] ->
            ( initial, [] )


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


stateToOffsetChanges : Offset -> DateTime -> DateTime -> ZoneState -> ( List Change, Offset )
stateToOffsetChanges previousOffset start until { standardOffset, zoneRules } =
    case zoneRules of
        Save save ->
            ( [ { start = utcMinutesFromDateTime previousOffset start
                , offset = standardOffset + save
                }
              ]
            , { standard = standardOffset, save = save }
            )

        Rules rules ->
            rulesToOffsetChanges previousOffset start until standardOffset rules


rulesToOffsetChanges : Offset -> DateTime -> DateTime -> Minutes -> List Rule -> ( List Change, Offset )
rulesToOffsetChanges previousOffset start until standardOffset rules =
    let
        transitions : List { start : Int, clock : Clock, save : Minutes }
        transitions =
            List.range (start.year - 1) until.year
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

        initialOffset =
            { standard = standardOffset, save = 0 }

        initialChange =
            { start = utcMinutesFromDateTime previousOffset start
            , offset = standardOffset
            }

        ( nextOffset, descendingChanges ) =
            transitions
                |> List.foldl
                    (\transition ( currentOffset, changes ) ->
                        let
                            newOffset =
                                { standard = standardOffset, save = transition.save }
                        in
                        if transition.start + utcAdjustment transition.clock previousOffset <= initialChange.start then
                            let
                                updatedInitialChange =
                                    { start = initialChange.start
                                    , offset = standardOffset + transition.save
                                    }
                            in
                            ( newOffset, [ updatedInitialChange ] )

                        else if transition.start + utcAdjustment transition.clock currentOffset < utcMinutesFromDateTime currentOffset until then
                            let
                                change =
                                    { start = transition.start + utcAdjustment transition.clock currentOffset
                                    , offset = standardOffset + transition.save
                                    }
                            in
                            ( newOffset, change :: changes )

                        else
                            ( currentOffset, changes )
                    )
                    ( initialOffset, [ initialChange ] )
    in
    ( List.reverse descendingChanges, nextOffset )



-- time helpers


utcAdjustment : Clock -> Offset -> Int
utcAdjustment clock { standard, save } =
    case clock of
        Universal ->
            0

        Standard ->
            0 - standard

        WallClock ->
            0 - (standard + save)


utcMinutesFromDateTime : Offset -> DateTime -> Int
utcMinutesFromDateTime offset datetime =
    minutesFromDateTime datetime + utcAdjustment datetime.clock offset


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
