#! /bin/bash

set -e

# ensure tz repository

if [ ! -d tz/.git ]; then
    git clone https://github.com/eggert/tz.git
else
    git -C tz checkout main && git -C tz pull
fi

# tz: checkout latest version

version=$(git -C tz describe --tags --abbrev=0)
git -C tz -c advice.detachedHead=false checkout $version

# build file

output="src/TimeZone.elm"

echo "Creating file $output for version $version"
python2 build.py tz $version $output
elm-format --yes $output

# tz: checkout main

git -C tz checkout main
