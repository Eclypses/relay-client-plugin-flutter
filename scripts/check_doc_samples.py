#!/usr/bin/env python3
"""Compile-check every Dart sample in the customer-facing docs.

Reading a sample proves nothing. `RelayRequest(bodyUtf8: ...)` was the primary POST
example in four places here and had never compiled -- `bodyUtf8` is a field on the
*response*, not a parameter on the request. It survived a same-day edit of two of
those very blocks, because the editor came looking for something else and validated
only that.

Each ```dart block is a fragment, and there is no reliable way to tell from the
text alone whether it belongs at top level, inside a function, or inside a class
body. So this does not guess: it compiles every block in all three shapes and
accepts the block if ANY of them is clean. That means a reported failure is a
real one -- the sample compiles nowhere -- rather than an artefact of the
harness picking the wrong wrapper.

The probe is generated inside `example/`, so `package:mte_relay` resolves
through the example app's own package config rather than a copied one.

Skip a block that genuinely cannot stand alone with a `<!-- check-doc-samples:
skip -->` comment on the line before its fence, which forces the reason to be
written down instead of silently tolerated.

Usage:  python3 scripts/check_doc_samples.py [--keep]
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOCS = [REPO / "README.md", REPO / "quick-start" / "flutter.md"]
EXAMPLE = REPO / "example"
PROBE = EXAMPLE / "lib" / "__doc_samples__"
SKIP = "<!-- check-doc-samples: skip -->"

IGNORES = (
    "// ignore_for_file: unused_import, unused_local_variable, unused_element\n"
    "// ignore_for_file: avoid_print, prefer_const_constructors, unused_field\n"
    "// ignore_for_file: duplicate_import, unused_element_parameter\n"
    "// ignore_for_file: override_on_non_overriding_member\n"
)

# Identifiers the docs introduce once (or present as reader-supplied) and then reuse
# across blocks. Each sample is compiled alone, so the probe has to stand these up or
# every block that mentions one fails for a reason that is not about the sample.
#
# These are deliberately typed with `dynamic`, never with a type that needs an import.
# A stub that needed `dart:io` would drag that import into every sample and hide the
# very defect this script exists to find.
CLIENTS = (
    "final _relay = MteRelayClient();\n"
    "final _plugin = MteRelayClientPlugin();\n"
    "final _client = RelayHttpClient();\n"
    "const relayServerUrl = 'https://relay.example.com';\n"
    "dynamic getFileToUpload(String size) async => null;\n"
    "dynamic getDownloadLocation(String name) async => '';\n"
    "class MultipartHelper {\n"
    "  MultipartHelper(String name);\n"
    "  String get boundary => '';\n"
    "  Future<int> calculateContentLength(dynamic f) async => 0;\n"
    "}\n\n"
)


def blocks(path: Path):
    """Yield (line_number, code, skipped) for each ```dart fence."""
    lines = path.read_text().splitlines()
    i = 0
    while i < len(lines):
        if lines[i].strip().startswith("```dart"):
            start = i + 1
            body = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                body.append(lines[i])
                i += 1
            skipped = any(SKIP in l for l in lines[max(0, start - 3):start])
            yield start + 1, "\n".join(body), skipped
        i += 1


def split_imports(code: str):
    """Lift the sample's own imports out of the body.

    A sample may carry its own `import`, which is only legal at top level -- so
    leaving it inline makes the function and class-member shapes fail for a
    reason that has nothing to do with the sample being wrong.
    """
    kept, lifted = [], []
    for line in code.splitlines():
        (lifted if line.strip().startswith("import ") else kept).append(line)
    return "\n".join(kept), lifted


def doc_imports(doc: Path) -> list:
    """Every import THIS document shows, in any of its code blocks.

    Deliberately derived rather than hardcoded: a hardcoded list silently supplies
    imports the docs never mention, so a sample using `File` would compile here and
    fail for the customer -- precisely the defect this script exists to catch.

    Scoped per document, not pooled across them, because a reader may hold only one.
    Pooling let one document's `import 'dart:math'` cover another's sample that
    lacked it, which is a green tick for a customer who cannot compile.
    """
    found = []
    for line in doc.read_text().splitlines():
        t = line.strip()
        if not t.startswith("import "):
            continue
        # Doc imports usually carry a trailing comment explaining what they are for --
        # "import 'dart:typed_data';  // For Uint8List". Keep it, drop the commentary.
        if "//" in t:
            t = t[:t.index("//")].strip()
        if t.endswith(";") and t not in found:
            found.append(t)
    return found


def header(own: list, doc: Path) -> str:
    have = {l.strip() for l in own}
    return (IGNORES + "\n".join(own)
            + ("\n" if own else "")
            + "\n".join(i for i in doc_imports(doc) if i not in have) + "\n\n")


# Identifiers the docs introduce once (or present as reader-supplied) and then reuse
# across blocks. Each sample is compiled alone, so the probe has to stand these up or
# every block that mentions one fails for a reason that is not about the sample.
def as_top_level(code: str, doc: Path) -> str:
    body, own = split_imports(code)
    return header(own, doc) + CLIENTS + body + "\n"


def as_function(code: str, doc: Path) -> str:
    body, own = split_imports(code)
    return (header(own, doc) + CLIENTS
            + "Future<void> _docSample() async {\n" + body + "\n}\n")


def as_signature(code: str, doc: Path) -> str:
    """An API-reference block: a bare signature with no body.

    Valid nowhere on its own, but valid as an abstract member once terminated,
    which is enough to prove the documented signature is real Dart.
    """
    body, own = split_imports(code)
    return (header(own, doc) + "abstract class _DocSignature {\n"
            + body.rstrip().rstrip(";") + ";\n}\n")


def as_member(code: str, doc: Path) -> str:
    """A fragment of a class body -- an `initState` override, a field, a method.

    A plain class, not a StatefulWidget: subclassing one would need
    `package:flutter/material.dart` whether or not the docs show it, and supplying
    an import the docs never mention is exactly what this script must not do. An
    `@override` with nothing to override is only a warning, which is why it can be
    a plain class at all.
    """
    code, own = split_imports(code)
    return (header(own, doc)
            + "class _DocBase {\n"
            + "  void initState() {}\n"
            + "  void dispose() {}\n"
            + "  void setState(void Function() fn) {}\n}\n\n"
            + "class _DocSample extends _DocBase {\n"
            + "  final _relay = MteRelayClient();\n"
            + "  final _plugin = MteRelayClientPlugin();\n"
            + "  final _client = RelayHttpClient();\n"
            + "  static const relayServerUrl = 'https://relay.example.com';\n"
            + "  dynamic getFileToUpload(String size) async => null;\n"
            + "  dynamic getDownloadLocation(String name) async => '';\n"
            + code + "\n}\n")


SHAPES = {"top": as_top_level, "fn": as_function,
          "member": as_member, "sig": as_signature}


def analyze(directory: Path) -> set:
    """Return the set of file stems that produced at least one error."""
    proc = subprocess.run(
        ["dart", "analyze", "--no-fatal-warnings", str(directory)],
        capture_output=True, text=True, cwd=EXAMPLE)
    bad = set()
    for line in (proc.stdout + proc.stderr).splitlines():
        if not line.strip().startswith("error"):
            continue
        m = re.search(r"(s_[A-Za-z0-9_]+)\.dart", line)
        if m:
            bad.add(m.group(1))
    return bad


def main() -> int:
    keep = "--keep" in sys.argv
    if not (EXAMPLE / ".dart_tool" / "package_config.json").exists():
        print("!! example/.dart_tool missing -- run `flutter pub get` in example/ first")
        return 2

    samples = []
    skipped = 0
    for doc in DOCS:
        rel = doc.relative_to(REPO)
        for lineno, code, skip in blocks(doc):
            if skip:
                skipped += 1
                continue
            if not code.strip():
                continue
            stem = "s_%s_%d" % (re.sub(r"\W", "_", str(rel)), lineno)
            samples.append((stem, "%s:%d" % (rel, lineno), code, doc))

    if PROBE.exists():
        shutil.rmtree(PROBE)
    failing = {stem for stem, _, _, _ in samples}
    try:
        for shape, fn in SHAPES.items():
            d = PROBE / shape
            d.mkdir(parents=True)
            for stem, _, code, doc in samples:
                (d / (stem + ".dart")).write_text(fn(code, doc))
            failing &= analyze(d)          # survives only if it fails in EVERY shape
    finally:
        if keep:
            print("probe kept at %s" % PROBE)
        elif PROBE.exists():
            shutil.rmtree(PROBE)

    where = {stem: loc for stem, loc, _, _ in samples}
    print("checked %d samples (%d skipped)" % (len(samples), skipped))
    if failing:
        print("\nFAIL: %d sample(s) compile in no context:" % len(failing))
        for stem in sorted(failing, key=lambda s: where[s]):
            print("  %s" % where[stem])
        print("\nRe-run with --keep and analyze example/lib/__doc_samples__ for detail.")
        return 1
    print("OK: every doc sample compiles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
