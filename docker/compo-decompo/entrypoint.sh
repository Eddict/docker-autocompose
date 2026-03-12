#!/bin/sh
if [ "$1" = "autocompose" ]; then
  shift
  exec poetry run autocompose "$@"
elif [ "$1" = "decomposerize" ]; then
  shift
  exec decomposerize "$@"
else
  exec "$@"
fi
