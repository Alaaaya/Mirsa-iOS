#!/usr/bin/env python3
"""Omit generated test-host IPAs only from the device packaging specification.
The canonical test specification remains strict and unchanged.
"""
from pathlib import Path

GENERATED_TEST_IPAS = (
    "tests/fixtures/exact-hooks25/ExactLaunch25Fixture.ipa",
    "tests/fixtures/generic-injection25/GenericLaunch25Fixture.ipa",
)


def device_spec(source):
    prefix, tests = source.split("  MirsaTests:\n", 1)
    for path in GENERATED_TEST_IPAS:
        entry = f"      - path: {path}\n        buildPhase: resources\n"
        if tests.count(entry) != 1:
            raise ValueError(f"Expected exactly one generated test resource: {path}")
        tests = tests.replace(entry, "", 1)
    return prefix + "  MirsaTests:\n" + tests


if __name__ == "__main__":
    Path("project.device.generated.yml").write_text(device_spec(Path("project.yml").read_text()))
