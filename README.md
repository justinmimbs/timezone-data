# timezone-data

This Elm package contains time zone data from the [IANA Time Zone Database][tzdb] for using with `elm/time`.

The `elm/time` library provides a `Posix` type for representing an instant in time. To extract human-readable parts from a `Posix` time requires a `Time.Zone`. This library provides such `Time.Zone` data.


## Examples

### Get a specific time zone

Data is contained in the `TimeZone.Data` module, where data for each zone is packaged as a `TimeZone.Data.Pack` type. A `Pack` must be unpacked to a `Time.Zone` with the `TimeZone.unpack` function.

```elm
import Time
import TimeZone
import TimeZone.Data

zone : Time.Zone
zone =
    TimeZone.unpack TimeZone.Data.america__new_york
```

Each `Pack` in the `TimeZone.Data` module is named after its zone name (e.g. _America/New_York_), where slashes are replaced by `__`, dashes are replaced by `_`, and the name is lowercased. For example, _America/Port-au-Prince_ becomes `america__port_au_prince`.

You can look up a `Pack` by its zone name in the `TimeZone.Data.packs` dictionary.

```elm
Dict.get "America/New_York" TimeZone.Data.packs
    == Just TimeZone.Data.america__new_york
```


### Get the local time zone

The `elm/time` library provides a task for getting the local zone name, `Time.getZoneName`. This library provides a convenience task for getting the local zone, `TimeZone.getZone`.

```elm
type Model
    = Loading
    | Failure TimeZone.Error
    | Success Time.Zone


type Msg
    = ReceiveTimeZone (Result TimeZone.Error ( String, Time.Zone ))


init : ( Model, Cmd Msg )
init =
    ( Loading
    , TimeZone.getZone |> Task.attempt ReceiveTimeZone
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update (ReceiveTimeZone result) _ =
    ( case result of
        Ok ( zoneName, zone ) ->
            Success zone

        Err error ->
            Failure error
    , Cmd.none
    )
```

[tzdb]: https://www.iana.org/time-zones
