#!/usr/bin/env python3
"""Build an offline shell dependency map from shfmt's Bash syntax tree."""

# bin/python/bin/python3 maintenance/shell_map.py --json /tmp/shell-map.json
# bin/python/bin/python3 maintenance/shell_map.py \
#     --root /inne/repo --output /tmp/shell-map.html \
#     --json /tmp/shell-map.json

import argparse
from collections import defaultdict
from dataclasses import dataclass, field, replace
import fnmatch
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import textwrap


MAX_VALUES = 128
UNKNOWN = "\0"
SHELLS = {"bash", "sh", "dash", "ksh", "mksh"}
WRAPPERS = {"builtin", "command", "env", "exec", "nice", "setsid", "sudo", "timeout"}
STARTUP_FILES = {".bashrc", ".bash_profile", ".bash_aliases", ".bash_login", ".bash_logout", ".profile"}


def children(node):
    if isinstance(node, list):
        yield from node
    elif isinstance(node, dict):
        for key, value in node.items():
            if key not in {"Pos", "End", "Comments", "Last"} and isinstance(value, (dict, list)):
                yield value


def walk(node, skip_functions=False):
    if isinstance(node, dict):
        if skip_functions and node.get("Type") == "FuncDecl":
            return
        yield node
    for child in children(node):
        yield from walk(child, skip_functions)


def parse(parser, source, filename):
    result = subprocess.run(
        [parser, "--to-json", "-ln=bash", "--filename", filename], input=source,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
    )
    if result.returncode:
        raise ValueError(result.stderr.decode(errors="replace").strip())
    return json.loads(result.stdout)


def fragment(node, source):
    return source[node["Pos"]["Offset"]:node["End"]["Offset"]].decode(errors="replace")


def environment_tree(source):
    # shfmt rejects valid associative keys such as ubuntu-24.04. These data
    # files contribute declarations only; their values are not part of the map.
    declarations = []
    pattern = rb"^(?:declare[ \t]+-[A-Za-z]+[ \t]+)?([A-Za-z_][A-Za-z_0-9]*)="
    for match in re.finditer(pattern, source, re.MULTILINE):
        line = source.count(b"\n", 0, match.start()) + 1
        declarations.append({"Name": {"Value": match[1].decode()}, "Value": {},
                             "Pos": {"Offset": match.start(), "Line": line},
                             "End": {"Offset": match.end(), "Line": line}})
    return {"Stmts": declarations}


def product(parts):
    result = {""}
    for values in parts:
        if len(result) * len(values) > MAX_VALUES:
            return {UNKNOWN}
        result = {left + right for left, right in itertools.product(result, values)}
    return result


def values(node, bindings, source, filename, root):
    """Evaluate only literal words and common path expressions, never shell code."""
    kind = node.get("Type")
    if "Parts" in node or kind == "DblQuoted":
        return product(values(part, bindings, source, filename, root) for part in node.get("Parts", []))
    if kind in {"Lit", "SglQuoted"}:
        text = node.get("Value", "")
        return {re.sub(r"\\(.)", r"\1", text) if kind == "Lit" else text}
    if kind == "ParamExp":
        name = node["Param"]["Value"]
        result = bindings.get(name, {str(root / filename)} if name in {"BASH_SOURCE", "0"} else {UNKNOWN})
        raw = fragment(node, source)
        if "%/*}" in raw:
            return {os.path.dirname(value) for value in result}
        if "##*/}" in raw:
            return {os.path.basename(value) for value in result}
        if "^^}" in raw:
            return {value.upper() for value in result}
        if "Exp" in node and "Word" in node["Exp"]:
            fallback = values(node["Exp"]["Word"], bindings, source, filename, root)
            return result | fallback
        return result
    if kind == "CmdSubst":
        calls = [item for item in walk(node) if item.get("Type") == "CallExpr" and item.get("Args")]
        names = [(values(call["Args"][0], bindings, source, filename, root), call) for call in calls]
        for expected in ("cd", "dirname", "readlink"):
            for nameset, call in names:
                if nameset != {expected}:
                    continue
                args = [arg for arg in call["Args"][1:]
                        if not fragment(arg, source).startswith("-")]
                if not args:
                    continue
                result = values(args[-1], bindings, source, filename, root)
                if expected == "cd" and any(name == {"pwd"} for name, _ in names):
                    return {os.path.normpath(value if value.startswith("/") else str(root / value))
                            for value in result}
                if expected == "dirname":
                    return {os.path.dirname(value) for value in result}
                if expected == "readlink":
                    return result
        if len(names) == 1 and names[0][0] == {"pwd"}:
            return {str(root)}
    return {UNKNOWN}


@dataclass
class Site:
    node: dict
    owner: str
    source: bytes
    line_base: int = 0
    callback: str = ""
    extra: dict = field(default_factory=dict)
    context: str = ""

    @property
    def line(self):
        return self.line_base + self.node["Pos"]["Line"]

    @property
    def text(self):
        return " ".join(fragment(self.node, self.source).split())[:200]


class Script:
    def __init__(self, root, path, parser):
        self.root, self.path = root, path
        self.id = "file:" + path
        self.source = (root / path).read_bytes()
        self.functions, self.calls, self.references, self.assignments, self.loops = [], [], [], [], []
        self.bindings = {}
        self.collect(environment_tree(self.source) if path.endswith(".env") else parse(parser, self.source, path), self.id)
        self.bindings[self.id] = self.bind(self.id, {})
        for function in self.functions:
            self.bindings[function["id"]] = self.bind(function["id"], self.bindings[self.id])

    def collect(self, node, owner, source=None, line_base=0, callback="", extra=None, context=""):
        source = self.source if source is None else source
        if isinstance(node, dict):
            kind = node.get("Type")
            if kind == "FuncDecl":
                if callback:
                    return
                name = node["Name"]["Value"]
                owner = f"function:{self.path}:{name}:{node['Pos']['Offset']}"
                self.functions.append({"id": owner, "kind": "function", "name": name, "file": self.path,
                                       "line": node["Pos"]["Line"]})
            site = Site(node, owner, source, line_base, callback, extra or {}, context)
            if kind == "CallExpr" and node.get("Args"):
                self.calls.append(site)
            if kind == "ParamExp" or "Parts" in node:
                self.references.append(site)
            if not callback and "Name" in node and ("Value" in node or "Array" in node):
                if isinstance(node["Name"], dict) and "Value" in node["Name"]:
                    self.assignments.append(site)
            if kind == "WordIter":
                self.loops.append(site)
        for child in children(node):
            self.collect(child, owner, source, line_base, callback, extra, context)

    def bind(self, owner, inherited):
        bindings = {name: set(items) for name, items in inherited.items()}
        assigned = self.assignments + self.loops
        for site in assigned:
            if site.owner == owner:
                bindings.pop(site.node["Name"]["Value"], None)
        for _ in range(3):
            for site in assigned:
                if site.owner != owner:
                    continue
                node = site.node
                words = node.get("Items", []) if node.get("Type") == "WordIter" else (
                    [element["Value"] for element in node.get("Array", {}).get("Elems", []) if "Value" in element]
                    if "Array" in node else [node["Value"]] if node.get("Value") else [])
                choices = set().union(*(self.evaluate(word, bindings, site.source) for word in words))
                if choices and choices != {UNKNOWN} and len(choices) <= MAX_VALUES:
                    name = node["Name"]["Value"]
                    combined = bindings.get(name, set()) | choices
                    bindings[name] = combined if len(combined) <= MAX_VALUES else {UNKNOWN}
        return bindings

    def evaluate(self, word, bindings, source=None):
        return values(word, bindings, self.source if source is None else source, self.path, self.root)

    def scope(self, site):
        return self.bindings.get(site.owner, self.bindings[self.id]) | site.extra


def repository_files(root):
    listing = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"], timeout=20,
    )
    for name in sorted(set(os.fsdecode(item) for item in listing.split(b"\0") if item)):
        path = root / name
        if path.is_symlink() or not path.is_file():
            continue
        yield name


def shell_files(root, files):
    for name in files:
        path = root / name
        with path.open("rb") as stream:
            first_line = stream.readline(256)
        if (name.endswith((".sh", ".env")) or path.name in STARTUP_FILES
                or re.search(rb"^#!.*\b(?:bash|sh|dash|ksh|mksh)\b", first_line)
                or re.search(rb"^#\s*shellcheck\s+shell=(?:bash|sh|dash|ksh|mksh)\b", first_line)):
            yield name


def paths(script, site, word, files, hint="", executable=False):
    matches = {}
    if hint and hint != "/dev/null":
        for candidate in (os.path.normpath(str(Path(script.path).parent / hint)), hint):
            if candidate in files:
                matches[candidate] = "exact"
        if matches:
            return matches
    for value in script.evaluate(word, script.scope(site), site.source):
        if not value or value in {UNKNOWN, "*"}:
            continue
        basename = os.path.basename(value)
        if UNKNOWN in basename and not re.search(r"[A-Za-z0-9_]", basename.replace(UNKNOWN, "")):
            continue
        value = value.replace(UNKNOWN, "*")
        for base in (script.root, script.root / Path(script.path).parent):
            candidate = os.path.normpath(value if value.startswith("/") else str(base / value))
            if any(char in candidate for char in "*?["):
                selected = [path for path in files if fnmatch.fnmatchcase(str(script.root / path), candidate)]
            else:
                relative = os.path.relpath(candidate, script.root)
                selected = [relative] if relative in files else []
            for path in selected:
                if not executable or os.access(script.root / path, os.X_OK):
                    matches[path] = "possible" if "*" in candidate or executable and "/" not in value else "exact"
        if "*" in value and "/" in value:
            for path in files:
                if fnmatch.fnmatchcase(str(script.root / path), value):
                    if executable and not os.access(script.root / path, os.X_OK):
                        continue
                    matches.setdefault(path, "possible")
    return matches


def source_hint(site):
    lines = site.source.decode(errors="replace").splitlines()
    for line in reversed(lines[max(0, site.node["Pos"]["Line"] - 6):site.node["Pos"]["Line"] - 1]):
        if line.strip() and not line.lstrip().startswith("#"):
            break
        match = re.search(r"#\s*shellcheck\s+source=(\S+)", line)
        if match:
            return match[1].strip("\"'")
    return ""


def command_index(words):
    index = 0
    while index < len(words) and Path(words[index]).name in WRAPPERS:
        wrapper = Path(words[index]).name
        index += 1
        while index < len(words):
            word = words[index]
            if word.startswith("-"):
                index += 2 if word in {"-u", "-g", "-C", "-n", "--unset", "--user", "--group"} else 1
            elif wrapper == "env" and re.match(r"[A-Za-z_][A-Za-z_0-9]*=", word):
                index += 1
            else:
                break
        if wrapper == "timeout" and index < len(words) and re.fullmatch(r"[0-9.]+[smhd]?", words[index]):
            index += 1
    return index


def shell_arguments(words, index):
    """Return the code/script argument and whether Bash only checks syntax."""
    offset, syntax_only, stdin = index + 1, False, False
    while offset < len(words) and words[offset].startswith("-"):
        option = words[offset]
        if option == "--":
            offset += 1
            break
        if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", option):
            return offset + 1, None, syntax_only
        syntax_only |= bool(re.fullmatch(r"-[a-zA-Z]*n[a-zA-Z]*", option))
        stdin |= bool(re.fullmatch(r"-[a-zA-Z]*s[a-zA-Z]*", option))
        offset += 2 if option in {"-o", "-O", "--rcfile", "--init-file"} else 1
    return None, None if stdin or offset >= len(words) else offset, syntax_only


def discover_scripts(root, parser):
    files = set(repository_files(root))
    pending = sorted(shell_files(root, files), reverse=True)
    scripts = {}
    while pending:
        path = pending.pop()
        if path in scripts:
            continue
        script = scripts[path] = Script(root, path, parser)
        for site in script.calls:
            words = [next(iter(result)) if len(result) == 1 else UNKNOWN for arg in site.node["Args"]
                     if (result := script.evaluate(arg, script.scope(site), site.source))]
            index = command_index(words)
            if index >= len(words):
                continue
            hint = ""
            if words[index] in {"source", "."} and index + 1 < len(words):
                index, hint = index + 1, source_hint(site)
            elif Path(words[index]).name in SHELLS:
                _, index, _ = shell_arguments(words, index)
                if index is None:
                    continue
            else:
                continue
            pending.extend(sorted(paths(script, site, site.node["Args"][index], files, hint), reverse=True))
    return [scripts[path] for path in sorted(scripts)]


def yaml_scalar(value):
    value = value.strip()
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    if value.startswith('"') and value.endswith('"'):
        try:
            return json.loads(value)
        except ValueError:
            return ""
    return value


def yaml_commands(path, field):
    """Read literal Task cmds / workflow run scalars, not arbitrary YAML or templates."""
    lines = path.read_text().splitlines()
    task, scope, index = "", None, 0
    tasks_indent, task_indent, step_indent = None, None, None
    while index < len(lines):
        line = lines[index]
        indent, text = len(line) - len(line.lstrip()), line.strip()
        index += 1
        if not text or text.startswith("#"):
            continue
        if field == "cmds":
            if text == "tasks:":
                tasks_indent, task_indent = indent, None
                continue
            if tasks_indent is None:
                continue
            if indent <= tasks_indent:
                tasks_indent, scope = None, None
                continue
            match = re.fullmatch(r"([\w:.-]+):", text)
            if task_indent is None and match:
                task_indent = indent
            if indent == task_indent and match:
                task = match[1]
            if scope is not None and indent <= scope:
                scope = None
            if text == "cmds:" and task:
                scope = indent
                continue
            if scope is None or not text.startswith("- "):
                continue
            value = text[2:]
            if re.match(r"(?:task|cmd):", value):
                continue
        else:
            if text == "steps:":
                scope, step_indent = indent, None
                continue
            if scope is None:
                continue
            if indent <= scope and not (indent == scope and text.startswith("- ")):
                scope = None
                continue
            if text.startswith("- ") and (step_indent is None or indent == step_indent):
                step_indent, text = indent, text[2:]
            elif step_indent is None or indent != step_indent + 2:
                continue
            match = re.fullmatch(r"run:\s*(.*)", text)
            if not match:
                continue
            value = match[1]
        if re.fullmatch(r"[|>][+-]?", value):
            body = []
            while index < len(lines) and (not lines[index].strip() or len(lines[index]) - len(lines[index].lstrip()) > indent):
                body.append(lines[index])
                index += 1
            code = textwrap.dedent("\n".join(body))
            if value.startswith(">"):
                code = " ".join(code.splitlines())
        else:
            code = yaml_scalar(value)
        yield task, code


def checkout_directories(path):
    directories = set()
    checkout, external, directory = False, False, ""
    for line in path.read_text().splitlines() + ["- end"]:
        text = line.strip()
        if text.startswith("- "):
            if checkout and not external and directory:
                directories.add(directory.rstrip("/"))
            checkout, external, directory = False, False, ""
            text = text[2:]
        if text.startswith("uses:"):
            checkout = yaml_scalar(text[5:]).startswith("actions/checkout@")
        elif checkout and text.startswith("repository:"):
            external = yaml_scalar(text[11:]).replace(" ", "") != "${{github.repository}}"
        elif checkout and text.startswith("path:"):
            directory = yaml_scalar(text[5:]).removeprefix("./")
    return directories


class Graph:
    def __init__(self, scripts):
        self.scripts = {script.path: script for script in scripts}
        self.nodes, self.edges, self.unresolved = {}, {}, []
        self.imported, self.symbols, self.resolutions = defaultdict(set), defaultdict(list), {}
        for script in scripts:
            test = bool({"test", "tests"} & set(Path(script.path).parts))
            node = {"id": script.id, "kind": "env" if script.path.endswith(".env") else "script",
                    "name": script.path, "file": script.path, "line": 1, "test": test,
                    "tasks": [], "workflows": []}
            self.nodes[script.id] = node
            for function in script.functions:
                self.nodes[function["id"]] = function | {"test": test}
            if node["kind"] == "env":
                for site in script.assignments:
                    name = site.node["Name"]["Value"]
                    identifier = f"variable:{script.path}:{name}"
                    self.nodes.setdefault(identifier, {"id": identifier, "kind": "variable", "name": name,
                                                       "file": script.path, "line": site.line, "test": test})
        for node in self.nodes.values():
            self.symbols[(node["kind"], node["name"])].append(node)

    def edge(self, script, site, target, kind, certainty="exact"):
        certainty = "possible" if site.callback == "shell -c" else certainty
        key = (site.owner, target, kind)
        edge = self.edges.setdefault(key, {"from": site.owner, "to": target, "kind": kind,
                                          "certainty": certainty, "sites": []})
        if certainty == "exact":
            edge["certainty"] = "exact"
        location = {"file": script.path, "line": site.line, "text": site.text, "certainty": certainty}
        if location not in edge["sites"]:
            edge["sites"].append(location)

    def missing(self, script, site, kind, detail=""):
        entry = {"from": site.owner, "file": script.path, "line": site.line,
                 "kind": kind, "text": site.text, "detail": detail}
        if entry not in self.unresolved:
            self.unresolved.append(entry)

    def words(self, script, site):
        return [next(iter(result)).replace(UNKNOWN, "*") if len(result) == 1 else "*"
                for arg in site.node["Args"] if (result := script.evaluate(arg, script.scope(site), site.source))]

    def callbacks(self, parser):
        for script in self.scripts.values():
            for site in list(script.calls):
                words = self.words(script, site)
                index = command_index(words)
                if index >= len(words):
                    continue
                name = Path(words[index]).name
                code_index, callback = None, ""
                if name == "trap" and index + 1 < len(words) and not words[index + 1].startswith("-"):
                    code_index, callback = index + 1, "trap"
                if name in SHELLS:
                    code_index, _, _ = shell_arguments(words, index)
                    callback = "shell -c"
                if code_index is None or code_index >= len(words):
                    continue
                if words[code_index] in {"*", "", "-"}:
                    self.missing(script, site, callback, "The callback is computed at runtime.")
                    continue
                extra = {str(number): script.evaluate(arg, script.scope(site), site.source)
                         for number, arg in enumerate(site.node["Args"][code_index + 1:])}
                source = words[code_index].encode()
                try:
                    tree = parse(parser, source, script.path)
                except ValueError as error:
                    self.missing(script, site, callback, str(error))
                    continue
                if any(node.get("Type") == "FuncDecl" for node in walk(tree)):
                    self.missing(script, site, callback, "Inline function definitions are not expanded.")
                script.collect(tree, site.owner, source, site.node["Args"][code_index]["Pos"]["Line"] - 1,
                               callback, extra, f"shell:{site.node['Pos']['Offset']}" if callback == "shell -c" else site.context)

    def imports(self):
        source_sites = defaultdict(list)
        for script in self.scripts.values():
            for site in script.calls:
                words = self.words(script, site)
                index = command_index(words)
                if index >= len(words) or words[index] not in {"source", "."}:
                    continue
                if index + 1 >= len(words):
                    self.missing(script, site, "source", "No source path.")
                    continue
                if not site.context:
                    source_sites[site.owner].append((script, site, index + 1))
                matches = paths(script, site, site.node["Args"][index + 1], self.scripts, source_hint(site))
                for path, certainty in matches.items():
                    self.edge(script, site, "file:" + path, "source", certainty)
                    self.imported[(script.path, site.context)].add(path)
                if not matches:
                    self.missing(script, site, "source", "External or unresolved source path.")

        closure, contexts = self.visibility()
        loaders = {self.nodes[owner]["name"] for owner in source_sites if self.nodes[owner]["kind"] == "function"}
        for script in self.scripts.values():
            for site in script.calls:
                words = self.words(script, site)
                index = command_index(words)
                if index >= len(words) or words[index] not in loaders:
                    continue
                if any(word in {"command", "builtin"} for word in words[:index]):
                    continue
                targets = self.resolve(script.path, words[index], "function", closure, contexts, site.context)
                arguments = {str(number): script.evaluate(arg, script.scope(site), site.source)
                             for number, arg in enumerate(site.node["Args"][index + 1:], 1)}
                for target in targets:
                    for helper, source_site, offset in source_sites[target]:
                        bindings = helper.bind(target, helper.bindings[helper.id] | arguments)
                        bound_site = replace(source_site, extra=bindings)
                        matches = paths(helper, bound_site, source_site.node["Args"][offset], self.scripts,
                                        source_hint(source_site))
                        for path in matches:
                            self.edge(script, site, "file:" + path, "source", "possible")
                            self.edge(helper, source_site, "file:" + path, "source", "possible")
                            # A loader imports into its caller; sharing its library does not load that file.
                            self.imported[(script.path, site.context)].add(path)
        self.resolutions.clear()

    def visibility(self):
        closure = {}
        for path, context in {(path, "") for path in self.scripts} | set(self.imported):
            seen = {path} if not context else set(self.imported[(path, context)])
            pending = list(seen)
            while pending:
                for target in self.imported[(pending.pop(), "")] - seen:
                    seen.add(target)
                    pending.append(target)
            closure[(path, context)] = seen
        contexts = {path: set().union(*(scope for scope in closure.values() if path in scope))
                    for path in self.scripts}
        return closure, contexts

    def resolve(self, path, name, kind, closure, contexts, context=""):
        key = path, name, kind, context
        if key in self.resolutions:
            return self.resolutions[key]
        visible = closure.get((path, context), set())
        scopes = ({path}, visible - {path}, contexts[path] - visible) if not context else (visible,)
        for scope in scopes:
            candidates = [node["id"] for node in self.symbols[(kind, name)] if node["file"] in scope]
            if candidates:
                self.resolutions[key] = candidates
                return candidates
        self.resolutions[key] = []
        return []

    def relationships(self):
        closure, contexts = self.visibility()
        forwarders = set()
        for script in self.scripts.values():
            for site in script.calls:
                words = self.words(script, site)
                if (site.owner != script.id and words and words[0] in WRAPPERS
                        and any(re.fullmatch(r'["\']?\$[@*]["\']?', fragment(arg, site.source))
                                for arg in site.node["Args"])):
                    forwarders.add(self.nodes[site.owner]["name"])
        for script in self.scripts.values():
            for site in script.calls:
                words = self.words(script, site)
                index = command_index(words)
                if index >= len(words):
                    continue
                name = words[index]
                if name in {"source", "."}:
                    continue
                if "command" in words[:index] and any(word in {"-v", "-V"} for word in words[:index]):
                    continue
                bypass = any(word in {"command", "builtin"} for word in words[:index])
                targets = [] if bypass else self.resolve(script.path, name, "function", closure, contexts, site.context)
                for target in targets:
                    self.edge(script, site, target, "trap" if site.callback == "trap" else "call",
                              "possible" if len(targets) > 1 else "exact")
                shell_index = index if Path(name).name in SHELLS else next(
                    (offset for offset in range(index + 1, len(words))
                     if name in forwarders and words[offset] in SHELLS), None)
                if shell_index is not None:
                    code_index, offset, syntax_only = shell_arguments(words, shell_index)
                    if code_index is not None:
                        continue
                    if offset is not None:
                        matches = paths(script, site, site.node["Args"][offset], self.scripts)
                        for path, certainty in matches.items():
                            self.edge(script, site, "file:" + path, "check" if syntax_only else "execute",
                                      "possible" if shell_index != index else certainty)
                        if not matches and words[offset] != "-":
                            self.missing(script, site, "execute", "External or unresolved shell script path.")
                elif not targets:
                    raw = fragment(site.node["Args"][index], site.source)
                    matches = paths(script, site, site.node["Args"][index], self.scripts, executable=True)
                    for path, certainty in matches.items():
                        if not path.endswith(".env"):
                            self.edge(script, site, "file:" + path, "execute", certainty)
                    if not matches and ("$" in raw or name == "eval"):
                        self.missing(script, site, "dynamic command", "Command selection is computed at runtime.")
            if script.path.endswith(".env"):
                continue
            for site in script.references:
                if site.node.get("Type") == "ParamExp":
                    names = {site.node["Param"]["Value"]}
                    kind = "read"
                else:
                    names = script.evaluate(site.node, script.scope(site), site.source)
                    kind = "reference"
                for name in names - {UNKNOWN, "*", ""}:
                    name = name.replace(UNKNOWN, "*")
                    if "*" in name:
                        visible = closure.get((script.path, site.context), set()) if site.context else contexts[script.path]
                        candidates = [node["id"] for node in self.nodes.values() if node["kind"] == "variable"
                                      and node["file"] in visible and fnmatch.fnmatchcase(node["name"], name)]
                    else:
                        candidates = self.resolve(script.path, name, "variable", closure, contexts, site.context)
                    for target in candidates:
                        self.edge(script, site, target, kind, "possible" if "*" in name or len(candidates) > 1 else "exact")

    def entrypoints(self, root, parser):
        taskfile = next((root / name for name in ("Taskfile.yml", "Taskfile.yaml", "Taskfile.dist.yml", "Taskfile.dist.yaml")
                         if (root / name).is_file()), None)
        configs = [(taskfile, "cmds")] if taskfile else []
        configs += [(path, "run") for path in sorted((root / ".github/workflows").glob("*"))
                    if path.is_file() and path.suffix in {".yml", ".yaml"}]
        bindings = {"GITHUB_WORKSPACE": {str(root)}, "SHELL_MAP_ROOT": {str(root)}}
        for config, field in configs:
            prefixes = checkout_directories(config) if field == "run" else set()
            for task, code in yaml_commands(config, field):
                code = code.replace("{{.ROOT_DIR}}", "${SHELL_MAP_ROOT}")
                code = re.sub(r"\$\{\{\s*github.workspace\s*\}\}", "${GITHUB_WORKSPACE}", code)
                code = re.sub(r"\$?\{\{.*?\}\}", "${SHELL_MAP_DYNAMIC}", code)
                source = code.encode()
                try:
                    tree = parse(parser, source, str(config))
                except ValueError:
                    continue
                for call in walk(tree, skip_functions=True):
                    if call.get("Type") != "CallExpr" or not call.get("Args"):
                        continue
                    words = [values(arg, bindings, source, "", root) for arg in call["Args"]]
                    literal = [next(iter(word)) if len(word) == 1 else UNKNOWN for word in words]
                    index = command_index(literal)
                    if index >= len(literal):
                        continue
                    if "command" in literal[:index] and any(word in {"-v", "-V"} for word in literal[:index]):
                        continue
                    if Path(literal[index]).name in SHELLS:
                        _, index, syntax_only = shell_arguments(literal, index)
                        if index is None or syntax_only:
                            continue
                    for value in words[index]:
                        if UNKNOWN in value:
                            continue
                        relative = os.path.relpath(value, root) if value.startswith("/") else value.removeprefix("./")
                        candidates = {os.path.normpath(relative)}
                        candidates.update(relative[len(prefix) + 1:] for prefix in prefixes if relative.startswith(prefix + "/"))
                        for candidate in candidates:
                            node = self.nodes.get("file:" + candidate)
                            if node and node["kind"] == "script":
                                node["tasks" if field == "cmds" else "workflows"].append(task if field == "cmds" else str(config.relative_to(root)))
        for script in self.scripts.values():
            node = self.nodes[script.id]
            node["tasks"] = sorted(set(node["tasks"]))
            node["workflows"] = sorted(set(node["workflows"]))
            node["role"] = "configuration" if node["kind"] == "env" else ", ".join(
                role for role, present in (("task entry", node["tasks"]), ("workflow entry", node["workflows"])) if present)

    def data(self):
        for edge in self.edges.values():
            edge["sites"].sort(key=lambda site: (site["file"], site["line"], site["text"]))
        return {"version": 1, "nodes": sorted(self.nodes.values(), key=lambda node: node["id"]),
                "edges": sorted(self.edges.values(), key=lambda edge: (edge["from"], edge["to"], edge["kind"])),
                "unresolved": sorted(self.unresolved, key=lambda site: (site["file"], site["line"], site["kind"]))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mapper_root = Path(__file__).resolve().parents[1]
    parser.add_argument("--root", type=Path, default=mapper_root)
    parser.add_argument("--output", type=Path, help="HTML destination (default: ROOT/maintenance/shell-map.html)")
    parser.add_argument("--json", type=Path, help="Also write the graph as plain JSON")
    parser.add_argument("--shfmt", default=None, help="shfmt executable (default: ROOT/bin/shfmt, mapper's bin/shfmt or PATH)")
    args = parser.parse_args()
    root = args.root.resolve()
    executable = args.shfmt or next((str(base / "bin/shfmt") for base in (root, mapper_root)
                                     if (base / "bin/shfmt").is_file()), shutil.which("shfmt"))
    if not executable:
        parser.error("shfmt is required; run task map to install the pinned parser")
    try:
        scripts = discover_scripts(root, executable)
        if not scripts:
            raise ValueError("No shell scripts found in the Git working tree")
        graph = Graph(scripts)
        graph.callbacks(executable)
        graph.imports()
        graph.relationships()
        graph.entrypoints(root, executable)
        data = graph.data()
        output = (args.output or root / "maintenance/shell-map.html").resolve()
        serialized = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
        # Escaping '<' keeps even a literal </script> inside JSON from closing its HTML element.
        embedded = serialized.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
        template = Path(__file__).with_name("shell-map.template.html").read_text()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(template.replace("__GRAPH_JSON__", embedded))
        if args.json:
            args.json.parent.mkdir(parents=True, exist_ok=True)
            args.json.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n")
        print(f"{output}: {len(scripts)} files, {sum(len(script.functions) for script in scripts)} functions, "
              f"{len(data['edges'])} relations, {len(data['unresolved'])} unresolved sites")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"shell-map: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
