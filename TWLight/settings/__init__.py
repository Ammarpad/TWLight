"""Package init for TWLight settings.

Which settings module to load is derived from a single environment token,
TWLIGHT_ENV, instead of being repeated across entry points and env files.
"""

import os

from django.core.exceptions import ImproperlyConfigured

# The environments we ship a settings module for. TWLIGHT_ENV selects one;
# anything else is an operator typo, not a new environment.
KNOWN_ENVIRONMENTS = frozenset({"local", "test", "staging", "production"})


def select_settings_module():
    """Point DJANGO_SETTINGS_MODULE at the module named by TWLIGHT_ENV.

    TWLIGHT_ENV is the sole environment token; the settings module falls out
    of it. A missing or unrecognized token is an operator error, so we fail
    loud rather than guess (defaulting to production was the old, more
    dangerous, behaviour: a stray invocation without the env file would
    quietly run against prod).
    """
    env = os.environ.get("TWLIGHT_ENV")
    if env not in KNOWN_ENVIRONMENTS:
        raise ImproperlyConfigured(
            f"TWLIGHT_ENV={env!r} is not one of {sorted(KNOWN_ENVIRONMENTS)}; "
            "refusing to guess a settings module."
        )
    os.environ["DJANGO_SETTINGS_MODULE"] = f"TWLight.settings.{env}"
