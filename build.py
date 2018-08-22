#! /usr/bin/python

import argparse
import os
import re
import sys

MIN_YEAR = 1970

whitespace = re.compile(r"\s")

def parse_source(sourcefile):
    lines = open(sourcefile).readlines()

    rules = {}
    zones = []
    current_zone = None

    for line in lines:
        if line[0] == "#":
            continue

        if current_zone is not None:
            if line[0:3] == "\t\t\t":
                zone_fields = re.split(whitespace, line[3:])
                current_zone["rows"].append(zone_fields)
                continue

            else:
                zones.append(current_zone)
                current_zone = None

        if line[0:4] == "Rule":
            rule_fields = re.split(whitespace, line[5:])
            rule = make_rule(rule_fields)
            if MIN_YEAR <= rule["to"]:
                insert_rule(rule_fields[0], rule, rules)

        elif line[0:4] == "Zone":
            zone_fields = re.split(whitespace, line[5:])
            current_zone = {
                "name": zone_fields[0],
                "rows": [ zone_fields[1:] ]
            }

    if current_zone is not None:
        zones.append(current_zone)

    return ( rules, zones )


def insert_rule(name, rule, rules):
    if name in rules:
        rules[name].append(rule)

    else:
        rules[name] = [ rule ]


def make_rule(fields):
    year1 = int(fields[1])
    year2 = year1 if fields[2] == "only" else ("max" if fields[2] == "max" else int(fields[2]))
    return {
        "from" : year1,
        "to" : year2,
        "month" : fields[4],
        "day" : to_dayofmonth(fields[5]),
        "time" : time_to_minutes(fields[6]),
        "clock" : char_to_clock(fields[6][-1:]),
        "save" : time_to_minutes(fields[7])
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


# rule: at     =    h:mmc
# rule: save   =    h[:mm]
# zone: offset = [-]h:mm[:ss]
# zone: until  =    h:mm[:ss]


def time_to_minutes(hhmm):
    hm = hhmm.split(":")
    h = int(hm[0])
    m = int(hm[1][0:2]) if len(hm) > 1 else 0
    return h * 60 + m


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
