"""
Settings for test runs. Identical to local except DEBUG is off, so tests
exercise the non-debug code paths.
"""

from .local import *

DEBUG = False
