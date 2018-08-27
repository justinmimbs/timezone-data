#! /usr/bin/python

import argparse
import io
import os
import re
import sys
from datetime import date


MIN_YEAR = 1970

MAX_YEAR = 2037

PRIMARY_DATA = [
    "africa",
    "antarctica",
    "asia",
    "australasia",
    "europe",
    "northamerica",
    "southamerica"
]


# PARSE

tabs_or_spaces = re.compile(r"\t+ *| +")

indented_comment = re.compile(r"[\t ]+#")


# zone table

def parse_zonetable(filepath):
    zonenames = set()

    for line in open(filepath).readlines():
        if line[0] == "#":
            continue

        fields = re.split(tabs_or_spaces, line.rstrip())
        zonenames.add(fields[2])

    return zonenames


# source file

def parse_sourcefile(filepath):
    rulesets = {}
    zones = {}
    parsing_zonename = None

    for line in open(filepath).readlines():
        if line[0] == "#" or indented_comment.match(line) is not None:
            continue

        line = line[0:line.find("#")].rstrip()
        fields = re.split(tabs_or_spaces, line)

        if parsing_zonename is not None:
            if line[0:3] == "\t\t\t":
                state, until = make_zonestateuntil(fields[1:])
                if until is None or MIN_YEAR < until["year"]:
                    insert_zonestateuntil(parsing_zonename, state, until, zones)
                continue

            else:
                parsing_zonename = None

        if fields[0] == "Rule":
            rulesetname = fields[1]
            rule = make_rule(fields[2:])
            if rule["from"] <= MAX_YEAR and (rule["to"] == "maxYear" or MIN_YEAR <= int(rule["to"])):
                insert_rule(rulesetname, rule, rulesets)

        elif fields[0] == "Zone":
            parsing_zonename = fields[1]
            state, until = make_zonestateuntil(fields[2:])
            if until is None or MIN_YEAR < until["year"]:
                insert_zonestateuntil(parsing_zonename, state, until, zones)

    return ( rulesets, zones )


# rulesets

def insert_rule(name, rule, rulesets):
    if name in rulesets:
        rulesets[name].append(rule)

    else:
        rulesets[name] = [ rule ]


def make_rule(fields):
    year1 = int(fields[0])
    year2 = year1 if fields[1] == "only" else ("maxYear" if fields[1] == "max" else int(fields[1]))
    return {
        "from" : year1,
        "to" : year2,
        "month" : fields[3],
        "day" : parse_dayofmonth(fields[4]),
        "time" : minutes_from_time(fields[5]),
        "clock" : clock_from_char(fields[5][-1:]),
        "save" : minutes_from_time(fields[6])
    }


def parse_dayofmonth(string):
    if string[0:4] == "last":
        weekday = string[4:7]
        return [ "Last", weekday ]

    elif string[3:5] == ">=":
        weekday = string[0:3]
        after = int(string[5:])
        return [ "First", weekday, after ]

    else:
        return [ "Day", int(string) ]


def clock_from_char(char):
    if char in [ "u", "z", "g" ]:
        return "Universal"

    elif char == "s":
        return "Standard"

    else:
        return "WallClock"


# zones

def insert_zonestateuntil(name, state, until, zones):
    if name not in zones:
        zones[name] = { "history": [], "current": None }

    if until is not None:
        zones[name]["history"].append(( state, until ))

    else:
        zones[name]["current"] = state


def make_zonestateuntil(fields):
    state = {
        "offset": minutes_from_time(fields[0]),
        "zonerules": parse_zonerules(fields[1])
    }
    until = make_datetime(fields[3:7]) if len(fields) > 3 else None
    return ( state, until )


def parse_zonerules(string):
    if string[0:1].isalpha():
        return [ "Rules", string ]

    elif string == "-":
        return [ "Save", 0 ]

    else:
        return [ "Save", minutes_from_time(string) ]


def make_datetime(fields):
    return {
        "year": int(fields[0]),
        "month": fields[1] if len(fields) > 1 else "Jan",
        "day": to_concreteday(*fields[0:3]) if len(fields) > 2 else 1,
        "time": minutes_from_time(fields[3]) if len(fields) > 3 else 0
    }


def to_concreteday(yyyy, mmm, day):
    if day[0:4] == "last":
        year = int(yyyy)
        month = months.index(mmm) + 1
        weekday = weekdays.index(day[4:7]) + 1
        return floorweekday(lastofmonth(year, month), weekday).day

    elif day[3:5] == ">=":
        year = int(yyyy)
        month = months.index(mmm) + 1
        weekday = weekdays.index(day[0:3]) + 1
        after = int(day[5:])
        return ceilingweekday(date(year, month, after), weekday).day

    else:
        return int(day)


# date helpers

months = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]

weekdays = [ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" ]


def lastofmonth(year, month):
    firstofnextmonth = date(year, month + 1, 1) if month < 12 else date(year + 1, 1, 1)
    return date.fromordinal(firstofnextmonth.toordinal() - 1)


def floorweekday(date_, weekday):
    dayssincepreviousweekday = (date_.isoweekday() + 7 - weekday) % 7
    return date.fromordinal(date_.toordinal() - dayssincepreviousweekday)


def ceilingweekday(date_, weekday):
    floored = floorweekday(date_, weekday)
    return floored if date_ == floored else date.fromordinal(floored.toordinal() + 7)


# time

# Rule AT     =    h:mm[c]
# Rule SAVE   =    h[:mm]
# Zone GMTOFF = [-]h:mm[:ss]
# Zone RULES  =    h:mm
# Zone UNTIL  =    h:mm[:ss]

def minutes_from_time(hhmm):
    hm = hhmm.split(":")
    h = int(hm[0])
    m = int(hm[1][0:2]) if len(hm) > 1 else 0
    return h * 60 + (m if h >= 0 else -m)


# TRANSFORM

def transform(zonenames, ( rulesets, zones )):
    # update zones: remove zones without a current state, remove zones not in zonenames
    zones = { name: zone for name, zone in zones.iteritems() if zone["current"] is not None and name in zonenames }

    # update rulesets: add missing rulesets, remove unused rulesets
    rulesetnames = set()
    for zone in zones.itervalues():
        rulesetnames.update([ rulesetname_from_zonerules(state["zonerules"]) for state, _ in zone["history"] ])
        rulesetnames.add(rulesetname_from_zonerules(zone["current"]["zonerules"]))

    rulesets = { name: rulesets.get(name, []) for name in rulesetnames if name is not None }

    # optimization: remove empty rulesets, remove their references in zones
    emptyrulesets = set([ name for name, rules in rulesets.iteritems() if not rules ])
    for zone in zones.itervalues():
        for state, _ in zone["history"]:
            remove_referenced_rulsetnames(emptyrulesets, state)
        remove_referenced_rulsetnames(emptyrulesets, zone["current"])

    rulesets = { name: rules for name, rules in rulesets.iteritems() if rules }

    return ( rulesets, zones )


def remove_referenced_rulsetnames(rulsetnames, state):
    if rulesetname_from_zonerules(state["zonerules"]) in rulsetnames:
        state["zonerules"] = [ "Save", 0 ]


def rulesetname_from_zonerules(zonerules):
    return zonerules[1] if zonerules[0] == "Rules" else None


# PRINT

def print_filecontent(version, rulesets, zones):
    zonenameid_pairs = [ ( name, zoneid_from_name(name) ) for name in sorted(zones.iterkeys()) ]
    zoneids = ", ".join([ zoneid for _, zoneid in zonenameid_pairs ])

    output = [
        template_header.format(zoneids=zoneids),
        "-- Version",
        template_version.format(version=version),
        "-- Bounds",
        template_bounds.format(min=MIN_YEAR, max=MAX_YEAR),
    ]

    # rulesets
    output.append("-- Rules")
    for name in sorted(rulesets.keys()):
        output.append(print_ruleset(name, rulesets[name]))

    # zones
    output.append("-- Zones")
    for name in sorted(zones.keys()):
        output.append(print_zone(name, zones[name]))

    # zonenameid_pairs
    output.append("-- Zones by name")
    output.append(print_zonenameid_pairs(zonenameid_pairs))

    return "\n".join(output)


def print_ruleset(name, rules):
    name_ = rulesetid_from_name(name)
    rules_ = line_separator1.join(map(print_rule, rules))
    return template_ruleset.format(name=name_, rules=rules_)


def print_rule(rule):
    dayofmonth = " ".join(map(str, rule["day"]))
    return template_rule.format(dayofmonth=dayofmonth, **rule)


def print_zone(name, zone):
    name_ = zoneid_from_name(name)
    history = line_separator3.join(map(print_zonestateuntil, zone["history"]))
    current = print_zonestate(**zone["current"])
    return template_zone.format(name=name_, history=history, current=current)


def print_zonestateuntil(( state, until )):
    state_ = print_zonestate(**state)
    until_ = template_datetime.format(**until)
    return template_zonestateuntil.format(state=state_, until=until_)


def print_zonestate(offset, zonerules):
    zonerules_ = print_zonerules(zonerules)
    return template_zonestate.format(offset=offset, zonerules=zonerules_)


def print_zonerules(zonerules):
    if zonerules[0] == "Rules":
        return "Rules {}".format(rulesetid_from_name(zonerules[1]))

    else:
        return " ".join(map(str, zonerules))

def print_zonenameid_pairs(zonenameid_pairs):
    pairs = [ template_zonenameid_pair.format(k, v) for k, v in zonenameid_pairs ]
    return template_zonenameid_pairs.format(pairs=line_separator1.join(pairs))


def rulesetid_from_name(name):
    return "rules_" + name.replace("-", "_")


def zoneid_from_name(name):
    return name.replace("/", "__").replace("-", "_").lower()


# templates

template_header = """module TimeZone.Data exposing (Pack, version, minYear, maxYear, packs, {zoneids})

import Dict exposing (Dict)
import Time exposing (Month(..), Weekday(..))
import TimeZone.Types exposing (..)

type alias Pack =
    TimeZone.Types.Pack
"""

template_version = """
version : String
version =
    "{version}"
"""

template_bounds = """
minYear : Year
minYear =
    {min}

maxYear : Year
maxYear =
    {max}
"""

template_ruleset = """
{name} : List Rule
{name} =
    [ {rules}
    ]
"""

template_rule = "Rule {from} {to} {month} ({dayofmonth}) {time} {clock} {save}"

template_zone = """
{name} : Pack
{name} =
    Packed <|
        Zone
            [ {history}
            ]
            ({current})
"""

template_zonestateuntil = "( {state}, {until} )"

template_zonestate = "ZoneState {offset} ({zonerules})"

template_datetime = "DateTime {year} {month} {day} {time}"

template_zonenameid_pairs = """
packs : Dict String Pack
packs =
    [ {pairs}
    ]
        |> Dict.fromList
"""

template_zonenameid_pair = "( \"{0}\", {1} )"

line_separator1 = "\n    , "

line_separator3 = "\n            , "


# main

def main():
    argparser = argparse.ArgumentParser()
    argparser.add_argument("sourcedir", help="path to tzdb source directory")
    argparser.add_argument("version", help="what version of tzdb is this?")
    argparser.add_argument("output", help="path to destination file")
    args = argparser.parse_args()

    sourcedir = os.path.abspath(args.sourcedir)

    if not os.path.exists(sourcedir):
        print "error: sourcedir not found: " + sourcedir
        sys.exit(1)

    # we only want zones listed in the zone table
    zonenames = parse_zonetable(os.path.join(sourcedir, "zone1970.tab"))

    # parse, transform, print
    rulesets = {}
    zones = {}

    for filename in PRIMARY_DATA:
        rulesets_, zones_ = transform(zonenames, parse_sourcefile(os.path.join(sourcedir, filename)))
        rulesets.update(rulesets_)
        zones.update(zones_)

    missingzones = zonenames - set(zones.keys())
    if missingzones:
        print "error: zones not found: " + ", ".join(missingzones)
        sys.exit(1)

    filecontent = print_filecontent(args.version, rulesets, zones)

    # write file
    filepath = os.path.abspath(args.output)

    if not os.path.exists(os.path.dirname(filepath)):
       os.makedirs(os.path.dirname(filepath))

    output = io.open(filepath, "w", encoding="utf-8")
    output.write(unicode(filecontent, encoding="utf-8-sig"))
    output.close()


if __name__ == "__main__":
    main()
