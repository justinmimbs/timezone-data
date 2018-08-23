#! /bin/bash

set -e

# ensure tz repository

if [ ! -d tz/.git ]; then
    git clone https://github.com/eggert/tz.git
else
    git -C tz checkout master && git -C tz pull
fi

# tz: checkout latest version

version=$(git -C tz describe --tags --abbrev=0)
git -C tz -c advice.detachedHead=false checkout $version

# build src/TimeZone/Data.elm

# TODO ./build.py tz $version

# tz: checkout master

git -C tz checkout master
