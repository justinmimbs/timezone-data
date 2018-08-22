#! /usr/bin/python

import argparse
import os
import re
import sys

MIN_YEAR = 1970

tab_or_spaces = re.compile(r"\t| +")


# source file

def parse_source(sourcefile):
    lines = open(sourcefile).readlines()

    rulesets = {}
    zones = {}
    parsing_zonename = None

    for line in lines:
        if line[0] == "#":
            continue

        line = line[0:line.find("#")].rstrip()
        fields = re.split(tab_or_spaces, line)

        if parsing_zonename is not None:
            if line[0:3] == "\t\t\t":
                state, until = make_zonestateuntil(fields[3:])
                if until is None or MIN_YEAR < until["year"]:
                    insert_zonestateuntil(parsing_zonename, state, until, zones)
                continue

            else:
                parsing_zonename = None

        if fields[0] == "Rule":
            rule = make_rule(fields[2:])
            if MIN_YEAR <= rule["to"]:
                insert_rule(fields[1], rule, rulesets)

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
    year2 = year1 if fields[1] == "only" else ("max" if fields[1] == "max" else int(fields[1]))
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
        return [ "First", weekday, "OnOrAfterDay", after ]

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
        "day": fields[2] if len(fields) > 2 else 1,
        "time": minutes_from_time(fields[3]) if len(fields) > 3 else 0
    }


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
    return h * 60 + m


# OUTPUT

def print_output(rulesets, zones):
    output = []

    # rulesets
    output.append("-- Rules")
    for name in sorted(rulesets.keys()):
        output.append(print_ruleset(name, rulesets[name]))

    # zones
    output.append("-- Zones")
    for name in sorted(zones.keys()):
        output.append(print_zone(name, zones[name]))

    return "\n\n".join(output)


def print_ruleset(name, rules):
    name_ = identifier_from_name(name)
    rules_ = line_separator1.join(map(print_rule, rules))
    return template_ruleset.format(name=name_, rules=rules_)


def print_rule(rule):
    dayofmonth = " ".join(map(str, rule["day"]))
    return template_rule.format(dayofmonth=dayofmonth, **rule)


def print_zone(name, zone):
    name_ = identifier_from_name(name)
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
        return "Rules {}".format(identifier_from_name(zonerules[1]))

    else:
        return " ".join(map(str, zonerules))


def identifier_from_name(name):
    return name.replace("/", "__").replace("-", "_").lower()


# templates

template_ruleset = """{name} : List Rule
{name} =
    [ {rules}
    ]
"""

template_rule = "Rule {from} {to} {month} ({dayofmonth}) {time} {clock} {save}"

template_zone = """{name} : Pack
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

line_separator1 = "\n    , "

line_separator3 = "\n            , "


# main

def main():
    argparser = argparse.ArgumentParser()
    argparser.add_argument("sourcefile", help="path to tzdb source file")
    args = argparser.parse_args()

    sourcefile = os.path.abspath(args.sourcefile)

    if not os.path.exists(sourcefile):
        print "error: sourcefile not found: " + sourcefile
        sys.exit(1)

    #
    rulesets, zones = parse_source(sourcefile)
    # TODO remove unused rulesets
    # TODO remove zones without a current state
    print print_output(rulesets, zones)


if __name__ == "__main__":
    main()
