#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
    exec prove -Ilocal/lib/perl5 t
fi

case "$1" in
    prove)
        shift
        exec prove -Ilocal/lib/perl5 "$@"
        ;;
    perl)
        shift
        exec perl -I/app -I/app/local/lib/perl5 "$@"
        ;;
    *)
        exec prove -Ilocal/lib/perl5 "$@"
        ;;
esac
