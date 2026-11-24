#!/usr/bin/env python3
"""Configure UI runner languages. Publication refs always require full coverage."""
import os
from pathlib import Path
import xml.etree.ElementTree as ET

def language_mode(ref, full_languages):
    if full_languages not in ("true", "false", ""):
        raise ValueError("full_languages must be a boolean")
    if ref == "refs/heads/main" or ref.startswith("refs/tags/") or full_languages == "true":
        return "full"
    return "ar"

def configure(scheme, mode):
    if mode not in ("ar", "full"):
        raise ValueError("Invalid UI language mode")
    tree = ET.parse(scheme)
    action = tree.getroot().find("TestAction")
    if action is None:
        raise ValueError("Missing TestAction")
    variables = action.find("EnvironmentVariables")
    if variables is None:
        variables = ET.SubElement(action, "EnvironmentVariables")
    for item in list(variables):
        if item.get("key") == "MIRSA_UI_LANGUAGE_MODE":
            variables.remove(item)
    ET.SubElement(variables, "EnvironmentVariable", {
        "key": "MIRSA_UI_LANGUAGE_MODE", "value": mode, "isEnabled": "YES"
    })
    tree.write(scheme, encoding="UTF-8", xml_declaration=True)

if __name__ == "__main__":
    mode = language_mode(os.environ["GITHUB_REF"], os.environ.get("FULL_LANGUAGES_REQUESTED", ""))
    configure(Path("Mirsa.xcodeproj/xcshareddata/xcschemes/MirsaUI.xcscheme"), mode)
    print("UI language coverage = " + mode + " (all non-language tests retained)")
