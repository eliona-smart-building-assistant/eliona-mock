#!/usr/bin/env python3
# Copyright (c) 2026 ABB Schweiz AG
# Authors: Adam Lange, et al.
"""Compute the database objects api-v2 needs and filter a pg_restore TOC to them.

Usage: subset.py <api-v2 source dir> <toc list from pg_restore -l>  (psql access via PSQL env, e.g. "psql -At")
Writes the filtered TOC to stdout and a summary to stderr.
"""
import os
import re
import shlex
import subprocess
import sys

PSQL = shlex.split(os.environ.get("PSQL", "psql -At"))
SKIP_SCHEMA = re.compile(r"^(pg_catalog|information_schema|sqitch|_timescaledb.*|timescaledb.*|toolkit_experimental)$")


def query(sql):
    out = subprocess.run(PSQL + ["-F", "\x1f", "-R", "\x1e", "-c", sql], check=True, capture_output=True, text=True).stdout
    return [r.split("\x1f") for r in out.strip("\x1e\n").split("\x1e") if r]


# Catalog: relations, functions, extension members, dependencies.
rels = {int(o): (s, n, k) for o, s, n, k in query(
    "select c.oid, n.nspname, c.relname, c.relkind::text from pg_class c join pg_namespace n on n.oid = c.relnamespace")}
procs = {int(o): (s, n, src) for o, s, n, src in query(
    "select p.oid, n.nspname, p.proname, coalesce(p.prosrc, '') from pg_proc p join pg_namespace n on n.oid = p.pronamespace")}
ext_member = {(int(c), int(o)) for c, o in query("select classid::int, objid::int from pg_depend where deptype = 'e'")}
ext_of = {(int(c), int(o)): int(e) for c, o, e in query("select classid::int, objid::int, refobjid::int from pg_depend where deptype = 'e'")}
deps = query("select classid::int, objid::int, refclassid::int, refobjid::int, deptype::text from pg_depend where deptype in ('n', 'a', 'i')")
PG_CLASS, PG_PROC, PG_TRIGGER, PG_POLICY = (int(query(f"select '{t}'::regclass::oid")[0][0]) for t in ("pg_class", "pg_proc", "pg_trigger", "pg_policy"))

# The mock reproduces api-v2 behaviour, not platform rules: triggers (license check, audit, notify, guards)
# and row level security policies are left out. Kept are only triggers whose function shapes the data api-v2
# reads back: column defaults (*_but) and the heap rows of assets and attributes.
KEEP_TRIGGER_FUNCS = re.compile(r"_but$|^(setup_asset_heap|attribute_schema_aut|asset_delete_trigger|heap_counter|property_adt)$")
trigger_funcs = {int(o): n for o, n in query("select t.oid, p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid where not t.tgisinternal")}
KEEP_TRIGGERS = {o for o, f in trigger_funcs.items() if KEEP_TRIGGER_FUNCS.search(f)}

forward, owned = {}, {}
for c, o, rc, ro, t in deps:
    c, o, rc, ro = int(c), int(o), int(rc), int(ro)
    forward.setdefault((c, o), []).append((rc, ro))
    if t in ("a", "i"):
        owned.setdefault((rc, ro), []).append((c, o))

by_name_rel, by_name_proc = {}, {}
for o, (s, n, k) in rels.items():
    by_name_rel.setdefault(n, []).append((s, o))
for o, (s, n, _) in procs.items():
    by_name_proc.setdefault(n, []).append((s, o))

TOKEN = re.compile(r'"?([a-z_][a-z0-9_]*)"?\s*\.\s*"?([a-z_][a-z0-9_]*)"?|"?([a-z_][a-z0-9_]*)"?', re.I)


def names_in(text, default_schemas=("public",)):
    """Relations and functions referenced in SQL text, schema-qualified or resolved via default_schemas."""
    found = set()
    for m in TOKEN.finditer(text.lower()):
        if m.group(1):
            sch, name = m.group(1), m.group(2)
            found |= {(PG_CLASS, o) for s, o in by_name_rel.get(name, []) if s == sch}
            found |= {(PG_PROC, o) for s, o in by_name_proc.get(name, []) if s == sch}
        else:
            name = m.group(3)
            found |= {(PG_CLASS, o) for s, o in by_name_rel.get(name, []) if s in default_schemas}
            found |= {(PG_PROC, o) for s, o in by_name_proc.get(name, []) if s in default_schemas}
    return found


# Seed: every SQL string literal in api-v2 Go code (tests excluded).
LITERAL = re.compile(r"`([^`]*)`|\"((?:[^\"\\\n]|\\.)*)\"", re.S)
SQL_WORD = re.compile(r"\b(select|insert|update|delete|from|join|returning|call)\b", re.I)
seed = set()
src_dir = sys.argv[1]
for root, dirs, files in os.walk(src_dir):
    dirs[:] = [d for d in dirs if d not in ("it", "it-mock", ".git", "vendor")]
    for f in files:
        if f.endswith(".go") and not f.endswith("_test.go"):
            text = open(os.path.join(root, f), encoding="utf-8", errors="ignore").read()
            for m in LITERAL.finditer(text):
                s = m.group(1) or m.group(2) or ""
                if SQL_WORD.search(s):
                    seed |= names_in(s, ("public", "api"))

# Closure: owned sub-objects, forward dependencies and names referenced in function bodies.
keep, extensions, todo = set(), set(), list(seed)
while todo:
    obj = todo.pop()
    if obj in keep:
        continue
    if obj in ext_member:
        extensions.add(ext_of[obj])
        continue
    cls, oid = obj
    if cls == PG_CLASS and oid in rels and SKIP_SCHEMA.match(rels[oid][0]):
        continue
    if cls == PG_PROC and oid in procs and SKIP_SCHEMA.match(procs[oid][0]):
        continue
    keep.add(obj)
    todo += [(c, o) for c, o in owned.get(obj, [])
             if c != PG_POLICY and (c != PG_TRIGGER or o in KEEP_TRIGGERS)]
    todo += forward.get(obj, [])
    if cls == PG_PROC and oid in procs:
        todo += names_in(procs[oid][2])

keep_oids = {o for _, o in keep}
keep_rel_names = {rels[o][:2] for c, o in keep if c == PG_CLASS and o in rels}
schemas = {rels[o][0] for c, o in keep if c == PG_CLASS and o in rels} | {procs[o][0] for c, o in keep if c == PG_PROC and o in procs}
ext_names = {n for (n,) in query("select extname from pg_extension where oid in (%s)" % ",".join(map(str, extensions or {0})))}

# Filter the TOC: "<id>; <catalog oid> <object oid> <TYPE ...> <schema> <name> <owner>".
TOC = re.compile(r"^(\d+); (\d+) (\d+) (.+)$")
kept = 0
for line in open(sys.argv[2], encoding="utf-8"):
    m = TOC.match(line)
    if not m:
        if line.startswith(";"):
            sys.stdout.write(line)
        continue
    obj_oid, rest = int(m.group(3)), m.group(4)
    words = rest.split()
    ok = obj_oid in keep_oids
    if rest.startswith(("TABLE ATTACH ", "INDEX ATTACH ")):  # these entries carry no OID
        ok = (words[2], words[3]) in keep_rel_names
    elif rest.startswith("SCHEMA "):
        ok = words[2] in schemas
    elif rest.startswith("ROW SECURITY "):
        ok = False
    elif rest.startswith("EXTENSION "):
        ok = words[2] in ext_names and words[2] != "plpgsql"
    if ok:
        kept += 1
        sys.stdout.write(line)

rel_count = sum(1 for c, o in keep if c == PG_CLASS and o in rels and rels[o][2] in ("r", "p", "v", "m"))
print(f"seed {len(seed)}, relations {rel_count}, functions {sum(1 for c, _ in keep if c == PG_PROC)}, "
      f"schemas {sorted(schemas)}, extensions {sorted(ext_names)}, toc entries {kept}", file=sys.stderr)
