module Examples exposing (main)

import Browser
import Dict
import Html exposing (Html)
import Html.Attributes
import Task exposing (Task)
import Time exposing (Posix)
import TimeZone
import TimeZone.Data


main : Program () Model Msg
main =
    Browser.document
        { init = always init
        , view = view
        , update = update
        , subscriptions = always Sub.none
        }


type Model
    = Loading
    | Failure TimeZone.Error
    | Success ( String, Time.Zone )


type Msg
    = ReceiveTimeZone (Result TimeZone.Error ( String, Time.Zone ))


init : ( Model, Cmd Msg )
init =
    ( Loading
    , TimeZone.getZone |> Task.attempt ReceiveTimeZone
    )



-- update


update : Msg -> Model -> ( Model, Cmd Msg )
update (ReceiveTimeZone result) _ =
    ( case result of
        Ok data ->
            Success data

        Err error ->
            Failure error
    , Cmd.none
    )



-- view


view : Model -> Browser.Document Msg
view model =
    Browser.Document
        "Examples"
        (case model of
            Loading ->
                [ Html.pre [] [ Html.text "Loading..." ] ]

            Failure error ->
                [ Html.pre [ Html.Attributes.style "color" "red" ] [ Html.text (Debug.toString error) ] ]

            Success ( zoneName, zone ) ->
                [ Html.pre
                    []
                    [ [ "Examples of Posix times displayed in UTC and your local time:"
                      , ""
                      , "UTC                      | " ++ zoneName
                      , "------------------------ | ------------------------"
                      ]
                        ++ ([ 867564229068
                            , 1131357044194
                            , 1467083800795
                            , 1501214531979
                            , 1512980764516
                            , 1561825998564
                            , 1689782246881
                            ]
                                |> List.map Time.millisToPosix
                                |> List.map
                                    (\posix ->
                                        (posix |> formatPosix Time.utc) ++ " | " ++ (posix |> formatPosix zone)
                                    )
                           )
                        |> String.join "\n"
                        |> Html.text
                    ]
                ]
        )


formatPosix : Time.Zone -> Posix -> String
formatPosix zone posix =
    String.join " "
        [ Time.toWeekday zone posix |> Debug.toString
        , Time.toMonth zone posix |> Debug.toString
        , Time.toDay zone posix |> String.fromInt |> String.padLeft 2 '0'
        , Time.toYear zone posix |> String.fromInt
        , String.join ":"
            [ Time.toHour zone posix |> String.fromInt |> String.padLeft 2 '0'
            , Time.toMinute zone posix |> String.fromInt |> String.padLeft 2 '0'
            , Time.toSecond zone posix |> String.fromInt |> String.padLeft 2 '0'
            ]
        ]
