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

    rules = {}
    zones = {}
    parsing_zonename = None

    for line in lines:
        if line[0] == "#":
            continue

        line = line[0:line.find("#")].rstrip()
        fields = re.split(tab_or_spaces, line)

        if parsing_zonename is not None:
            if line[0:3] == "\t\t\t":
                state, until = make_zonestate(fields[3:])
                if until is None or MIN_YEAR < until["year"]:
                    insert_zonestate(parsing_zonename, state, until, zones)
                continue

            else:
                parsing_zonename = None

        if fields[0] == "Rule":
            rule = make_rule(fields[2:])
            if MIN_YEAR <= rule["to"]:
                insert_rule(fields[1], rule, rules)

        elif fields[0] == "Zone":
            parsing_zonename = fields[1]
            state, until = make_zonestate(fields[2:])
            if until is None or MIN_YEAR < until["year"]:
                insert_zonestate(parsing_zonename, state, until, zones)

    return ( rules, zones )


# rules

def insert_rule(name, rule, rules):
    if name in rules:
        rules[name].append(rule)

    else:
        rules[name] = [ rule ]


def make_rule(fields):
    year1 = int(fields[0])
    year2 = year1 if fields[1] == "only" else ("max" if fields[1] == "max" else int(fields[1]))
    return {
        "from" : year1,
        "to" : year2,
        "month" : fields[3],
        "day" : to_dayofmonth(fields[4]),
        "time" : time_to_minutes(fields[5]),
        "clock" : char_to_clock(fields[5][-1:]),
        "save" : time_to_minutes(fields[6])
    }


def to_dayofmonth(string):
    if string[0:4] == "last":
        weekday = string[4:7]
        return [ "Last", weekday ]

    elif string[3:5] == ">=":
        weekday = string[0:3]
        after = int(string[5:])
        return [ "First", weekday, after ]

    else:
        return [ "Day", int(string) ]


def char_to_clock(char):
    if char in [ "u", "z", "g" ]:
        return "Universal"

    elif char == "s":
        return "Standard"

    else:
        return "WallClock"


# zones

def insert_zonestate(name, state, until, zones):
    if name not in zones:
        zones[name] = { "history": [], "current": None }

    if until is not None:
        zones[name]["history"].append(( state, until ))

    else:
        zones[name]["current"] = state


def make_zonestate(fields):
    state = {
        "offset": time_to_minutes(fields[0]),
        "rules": to_zonerules(fields[1])
    }
    until = make_datetime(fields[3:7]) if len(fields) > 3 else None
    return ( state, until )


def to_zonerules(string):
    if string[0:1].isalpha():
        return [ "Rules", string ]

    elif string == "-":
        return [ "Save", 0 ]

    else:
        return [ "Save", time_to_minutes(string) ]


def make_datetime(fields):
    return {
        "year": int(fields[0]),
        "month": fields[1] if len(fields) > 1 else "Jan",
        "day": fields[2] if len(fields) > 2 else 1,
        "time": time_to_minutes(fields[3]) if len(fields) > 3 else 0
    }


# time

# Rule AT     =    h:mm[c]
# Rule SAVE   =    h[:mm]
# Zone GMTOFF = [-]h:mm[:ss]
# Zone RULES  =    h:mm
# Zone UNTIL  =    h:mm[:ss]

def time_to_minutes(hhmm):
    hm = hhmm.split(":")
    h = int(hm[0])
    m = int(hm[1][0:2]) if len(hm) > 1 else 0
    return h * 60 + m


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
    x = parse_source(sourcefile)
    print x


if __name__ == "__main__":
    main()
