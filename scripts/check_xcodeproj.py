#!/usr/bin/env python3
"""Sanity checks for TimeTracker.xcodeproj that Xcode enforces when opening a project.

Fails if any file or group is a child of more than one PBXGroup (Xcode 27: "The reference ...
is a member of more than one group"), if a group lists a missing object, or if any file
reference points inside the local Swift package, which Xcode already shows as its own folder.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

PROJECT = Path(sys.argv[1] if len(sys.argv) > 1 else "TimeTracker.xcodeproj") / "project.pbxproj"
PACKAGE_DIR = "Packages/TimeTrackerCore"

text = PROJECT.read_text()
object_ids = set(re.findall(r"^\t\t([0-9A-F]{24})(?: /\*.*?\*/)? = \{", text, re.M))

groups = re.findall(
    r"^\t\t([0-9A-F]{24}) /\* (.*?) \*/ = \{\n\t\t\tisa = (?:PBXGroup|PBXVariantGroup);\n\t\t\tchildren = \(\n(.*?)\t\t\t\);",
    text, re.M | re.S,
)
parents = defaultdict(list)
problems = []
for group_id, group_name, children in groups:
    for child_id, child_name in re.findall(r"([0-9A-F]{24}) /\* (.*?) \*/", children):
        parents[(child_id, child_name)].append(group_name or group_id)
        if child_id not in object_ids:
            problems.append(f"Group '{group_name}' lists missing object {child_id} ({child_name})")

for (child_id, child_name), owners in parents.items():
    if len(owners) > 1:
        problems.append(f"'{child_name}' ({child_id}) is a member of more than one group: {owners}")

for match in re.finditer(r"isa = PBXFileReference;[^}]*?path = \"?([^;\"]+)\"?;", text):
    if match.group(1).startswith(PACKAGE_DIR + "/") or match.group(1).startswith("Tests/TimeTrackerCoreTests"):
        problems.append(f"File reference inside the local package: {match.group(1)}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"OK: {len(groups)} groups, every child has exactly one parent group.")
