#!/bin/bash

# Author: Jay Bowers
# 
# Description
#  TODO
#

set -o errexit
set -o nounset
set -o pipefail

usage() {
	echo "Usage: $0 ..."
	echo " ... - ..."
}

_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

debug() {
    if [ $debug == 1 ]; then
        "$@"
    fi
}

debug=0
while getopts ":d" option; do
    case "${option}" in
        d)
            set -o xtrace
            ;;
        v)
            debug=1
            ;;
        *)
            echo "Unknown option $option"
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))


