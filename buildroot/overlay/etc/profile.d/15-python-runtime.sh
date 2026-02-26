#!/bin/sh

# Python startup/runtime defaults for this disposable VM environment.
export PYTHONNOUSERSITE="${PYTHONNOUSERSITE:-1}"
export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"
export PYTHONOPTIMIZE="${PYTHONOPTIMIZE:-1}"
