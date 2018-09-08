module CompareToJson exposing (main)

import Browser
import Dict
import Html exposing (Html)
import Html.Attributes
import Http
import Json.Decode as Decode exposing (Decoder)
import Task exposing (Task)
import Time
import TimeZone


main : Program () Model Msg
main =
    Browser.document
        { init = always init
        , view = view
        , update = update
        , subscriptions = always Sub.none
        }


type Model
    = CheckingJson
    | NoJson Http.Error
    | Processing
        { results : List ( String, Maybe String )
        , zoneName : String
        , zone : () -> Time.Zone
        , queue : List ( String, () -> Time.Zone )
        }
    | Finished (List ( String, Maybe String ))


type Msg
    = ReceiveZone String (Result Http.Error Time.Zone)


init : ( Model, Cmd Msg )
init =
    ( CheckingJson
    , fetchZone "America/New_York"
    )



-- update


update : Msg -> Model -> ( Model, Cmd Msg )
update (ReceiveZone zoneName receivedZone) model =
    case model of
        CheckingJson ->
            case receivedZone of
                Ok _ ->
                    case TimeZone.zones |> Dict.toList of
                        ( firstZoneName, firstZone ) :: rest ->
                            ( Processing
                                { results = []
                                , zoneName = firstZoneName
                                , zone = firstZone
                                , queue = rest
                                }
                            , fetchZone firstZoneName
                            )

                        [] ->
                            ( Finished [], Cmd.none )

                Err error ->
                    ( NoJson error, Cmd.none )

        Processing current ->
            if zoneName /= current.zoneName then
                ( model, Cmd.none )

            else
                let
                    results =
                        compareToJson zoneName current.zone receivedZone :: current.results
                in
                case current.queue of
                    ( nextZoneName, nextZone ) :: rest ->
                        ( Processing
                            { results = results
                            , zoneName = nextZoneName
                            , zone = nextZone
                            , queue = rest
                            }
                        , fetchZone nextZoneName
                        )

                    [] ->
                        ( Finished results, Cmd.none )

        _ ->
            ( model, Cmd.none )


compareToJson : String -> (() -> Time.Zone) -> Result Http.Error Time.Zone -> ( String, Maybe String )
compareToJson zoneName zone result =
    let
        error =
            case result of
                Err _ ->
                    Just "Loading failed"

                Ok fetchedZone ->
                    if fetchedZone /= zone () then
                        Just "Does not match!"

                    else
                        Nothing
    in
    ( zoneName, error )



-- fetch zone


fetchZone : String -> Cmd Msg
fetchZone zoneName =
    Http.get
        ("/json/" ++ TimeZone.version ++ "/" ++ zoneName ++ ".json")
        decodeZone
        |> Http.send (ReceiveZone zoneName)


decodeZone : Decoder Time.Zone
decodeZone =
    Decode.map2 Time.customZone
        (Decode.index 1 Decode.int)
        (Decode.index 0 (Decode.list decodeOffsetChange))


decodeOffsetChange : Decoder { start : Int, offset : Int }
decodeOffsetChange =
    Decode.map2 (\a b -> { start = a, offset = b })
        (Decode.index 0 Decode.int)
        (Decode.index 1 Decode.int)



-- view


view : Model -> Browser.Document Msg
view model =
    Browser.Document
        "CompareToJson"
        (case model of
            CheckingJson ->
                [ colorText "black" "Checking for JSON files..." ]

            NoJson error ->
                [ colorText "red" "These tests require a set of time zone JSON files" ]

            Processing current ->
                let
                    summary =
                        "Remaining: "
                            ++ String.fromInt (List.length current.queue + 1)
                            ++ "\nFailed: "
                            ++ String.fromInt (List.length (current.results |> List.filterMap Tuple.second))
                            ++ "\n\n"
                in
                style
                    :: colorText "black" summary
                    :: (current.results |> List.reverse |> List.map viewResult)
                    ++ (current.queue |> List.map (\( name, _ ) -> colorText "gray" ("- " ++ name)))

            Finished results ->
                let
                    summary =
                        "Tested: "
                            ++ String.fromInt (List.length results)
                            ++ "\nFailed: "
                            ++ String.fromInt (List.length (results |> List.filterMap Tuple.second))
                            ++ "\n\n"
                in
                style
                    :: colorText "black" summary
                    :: (results |> List.reverse |> List.map viewResult)
        )


style =
    Html.node "style" [] [ Html.text "pre { margin: 0; }" ]


viewResult : ( String, Maybe String ) -> Html a
viewResult ( name, error ) =
    case error of
        Just message ->
            colorText "red" ("X " ++ name ++ " (" ++ message ++ ")")

        Nothing ->
            colorText "black" ("* " ++ name)


colorText : String -> String -> Html a
colorText color text =
    Html.pre [ Html.Attributes.style "color" color ] [ Html.text text ]
