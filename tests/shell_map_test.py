#!/usr/bin/env python3
"""Functional checks of the exported shell graph and standalone HTML."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GENERATOR = REPO / "maintenance/shell_map.py"
PARSER = str(REPO / "bin/shfmt") if (REPO / "bin/shfmt").is_file() else shutil.which("shfmt")


class ShellMapTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="shell-map-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo with spaces"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, timeout=10)
        self.write("tools.env", """declare -ga TOOLS=(bash task)
declare -gA TOOL_CHECKS=([bash]='version')
declare -gA TOOL_RELEASES=([ubuntu-24.04-x86_64]='confidential-example')
""")
        self.write("scripts/entry", """#!/usr/bin/env bash
ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tools.env"
. "$ROOT/scripts/shared-lib"
helper() { printf 'done\\n'; }
main() { worker; printf '%s\\n' "${TOOLS[@]}"; helper TOOL_RELEASES; }
main
""", executable=True)
        self.write("scripts/shared-lib", """#!/usr/bin/env bash
source "${BASH_SOURCE[0]%/*}/leaf-lib"
worker() { leaf; printf '%s\\n' "${TOOL_CHECKS[bash]}"; }
""")
        self.write("scripts/leaf-lib", """#!/usr/bin/env bash
leaf() { helper; }
""")
        self.write("scripts/unrelated", """#!/usr/bin/env bash
worker() { unrelated; }
unrelated() { true; }
worker
""", executable=True)
        self.write("tests/entry_test.sh", """#!/usr/bin/env bash
repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash "$repo_dir/scripts/entry"
worker
""", executable=True)

    def write(self, path, text, executable=False):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        target.chmod(0o755 if executable else 0o644)

    def generate(self, root=None, output=None, parser=PARSER):
        root = root or self.root
        output = output or self.root / "map.html"
        data_path = self.root / "map.json"
        command = [sys.executable, str(GENERATOR), "--root", str(root), "--output", str(output),
                   "--json", str(data_path)]
        if parser:
            command += ["--shfmt", parser]
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=35,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(data_path.read_text()), output.read_text()

    def node(self, data, path, name=None, kind=None):
        matches = [node for node in data["nodes"] if node["file"] == path
                   and (name is None or node["name"] == name) and (kind is None or node["kind"] == kind)]
        self.assertEqual(len(matches), 1, (path, name, kind, matches))
        return matches[0]["id"]

    def edges(self, data, source, target=None, kind=None):
        return [edge for edge in data["edges"] if edge["from"] == source
                and (target is None or edge["to"] == target) and (kind is None or edge["kind"] == kind)]

    def test_source_visibility_call_chains_and_env_readers(self):
        data, html = self.generate()
        entry = "file:scripts/entry"
        main = self.node(data, "scripts/entry", "main")
        worker = self.node(data, "scripts/shared-lib", "worker")
        leaf = self.node(data, "scripts/leaf-lib", "leaf")
        helper = self.node(data, "scripts/entry", "helper")
        self.assertTrue(self.edges(data, entry, "file:tools.env", "source"))
        self.assertTrue(self.edges(data, entry, "file:scripts/shared-lib", "source"))
        for source, target in ((entry, main), (main, worker), (worker, leaf), (leaf, helper)):
            self.assertTrue(self.edges(data, source, target, "call"), (source, target))
        for owner, field, kind in ((main, "TOOLS", "read"), (main, "TOOL_RELEASES", "reference"),
                                   (worker, "TOOL_CHECKS", "read")):
            self.assertTrue(self.edges(data, owner, self.node(data, "tools.env", field), kind))
        self.assertFalse(self.edges(data, main, self.node(data, "scripts/unrelated", "worker")))
        self.assertFalse(self.edges(data, "file:tests/entry_test.sh", kind="call"))
        self.assertTrue(self.edges(data, "file:tests/entry_test.sh", entry, "execute"))
        metadata = next(node for node in data["nodes"] if node["id"] == entry)
        self.assertEqual(metadata["role"], "")
        self.assertNotIn("confidential-example", html)
        self.assertNotIn("confidential-example", json.dumps(data))

    def test_quotes_comments_heredocs_and_substitutions(self):
        self.write("scripts/syntax", """#!/usr/bin/env bash
source scripts/shared-lib
helper() { :; }
main() {
  printf '%s\\n' 'worker' "leaf"
  # worker; source scripts/unrelated
  cat <<'DATA'
fake_definition() { worker; source scripts/unrelated; }
DATA
  answer=$(leaf)
  if worker; then helper; fi
  worker | helper
}
main
""", executable=True)
        data, _ = self.generate()
        main = self.node(data, "scripts/syntax", "main")
        self.assertFalse(any(node["name"] == "fake_definition" for node in data["nodes"]))
        self.assertFalse(self.edges(data, "file:scripts/syntax", "file:scripts/unrelated"))
        worker = self.node(data, "scripts/shared-lib", "worker")
        sites = self.edges(data, main, worker, "call")[0]["sites"]
        self.assertEqual({site["line"] for site in sites}, {11, 12})
        self.assertTrue(self.edges(data, main, self.node(data, "scripts/leaf-lib", "leaf"), "call"))

    def test_test_scenarios_wrappers_and_source_hints(self):
        self.write("tests/scenarios.sh", """#!/usr/bin/env bash
test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/scenarios" && pwd)
scenarios=(alpha beta)
for scenario in "${scenarios[@]}"; do bash "$test_dir/${scenario}_test.sh"; done
""", executable=True)
        for scenario in ("alpha", "beta"):
            self.write(f"tests/scenarios/{scenario}_test.sh", "#!/usr/bin/env bash\ntrue\n", executable=True)
        self.write("scripts/runner", """#!/usr/bin/env bash
ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
run_test() { setsid env MODE=test timeout --kill-after=5s "$@"; }
main() { run_test 30s bash "$ROOT/tests/scenarios.sh"; }
main
""", executable=True)
        self.write("scripts/hinted", """#!/usr/bin/env bash
# shellcheck source=shared-lib
source "$unknown/selected-helper"
worker
source /etc/tools.env
""", executable=True)
        data, _ = self.generate()
        for scenario in ("alpha", "beta"):
            self.assertTrue(self.edges(data, "file:tests/scenarios.sh",
                                       f"file:tests/scenarios/{scenario}_test.sh", "execute"))
        main = self.node(data, "scripts/runner", "main")
        self.assertTrue(self.edges(data, main, "file:tests/scenarios.sh", "execute"))
        self.assertTrue(self.edges(data, main, self.node(data, "scripts/runner", "run_test"), "call"))
        self.assertTrue(self.edges(data, "file:scripts/hinted", "file:scripts/shared-lib", "source"))
        self.assertFalse(self.edges(data, "file:scripts/hinted", "file:tools.env", "source"))
        self.assertTrue(any(site["file"] == "scripts/hinted" and site["kind"] == "source"
                            and "/etc/tools.env" in site["text"] for site in data["unresolved"]))

    def test_trap_callbacks_and_inline_shell_have_separate_visibility(self):
        self.write("scripts/callbacks", """#!/usr/bin/env bash
ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cleanup() { :; }
trap 'cleanup' EXIT
bash -c 'source "$1/scripts/shared-lib"; worker' _ "$ROOT"
worker
eval "$computed_command"
""", executable=True)
        data, _ = self.generate()
        self.assertTrue(self.edges(data, "file:scripts/callbacks",
                                   self.node(data, "scripts/callbacks", "cleanup"), "trap"))
        worker = self.node(data, "scripts/shared-lib", "worker")
        call = self.edges(data, "file:scripts/callbacks", worker, "call")[0]
        self.assertEqual(call["certainty"], "possible")
        self.assertEqual({site["line"] for site in call["sites"]}, {5})
        self.assertTrue(any(site["file"] == "scripts/callbacks" and site["kind"] == "dynamic command"
                            for site in data["unresolved"]))

    def test_unknown_executables_do_not_match_every_script(self):
        self.write("scripts/dynamic", """#!/usr/bin/env bash
tools_dir=${TOOLS_DIR:-$PWD/bin}
tool=$1
executable=$tools_dir/$tool
probe() { local executable=$1; "$executable" --version; }
probe "$executable"
""", executable=True)
        data, _ = self.generate()
        probe = self.node(data, "scripts/dynamic", "probe")
        self.assertFalse(self.edges(data, probe, kind="execute"))
        self.assertTrue(any(site["from"] == probe and site["kind"] == "dynamic command"
                            for site in data["unresolved"]))

    def test_shell_checks_and_external_commands_are_not_script_execution(self):
        self.write("tests/fixtures/curl", "#!/usr/bin/env bash\ntrue\n", executable=True)
        self.write("scripts/checks", """#!/usr/bin/env bash
curl https://example.invalid
command -v scripts/entry
bash -n scripts/entry
bash scripts/entry -c ignored-argument
bash -s -- scripts/unrelated <<'INPUT'
printf 'stdin\\n'
INPUT
""", executable=True)
        data, _ = self.generate()
        origin = "file:scripts/checks"
        self.assertFalse(self.edges(data, origin, "file:tests/fixtures/curl"))
        self.assertFalse(self.edges(data, origin, "file:scripts/unrelated", "execute"))
        self.assertTrue(self.edges(data, origin, "file:scripts/entry", "check"))
        execution = self.edges(data, origin, "file:scripts/entry", "execute")
        self.assertEqual({site["line"] for site in execution[0]["sites"]}, {5})

    def test_discovery_no_execution_and_safe_deterministic_html(self):
        marker = self.root / "executed"
        self.write("bash/.bashrc", f"source scripts/shared-lib\ntouch '{marker}'\n")
        self.write(".gitignore", "ignored/\nmap.*\n")
        self.write("ignored/ignored.sh", "#!/usr/bin/env bash\nfalse\n")
        self.write("scripts/special<&>", """#!/usr/bin/env bash
strange() { printf '%s\\n' '</script><script>alert(1)</script>'; }
strange '</script><script>alert(1)</script>'
""", executable=True)
        self.write("scripts/outside-target", "#!/usr/bin/env bash\ntrue\n")
        os.symlink("outside-target", self.root / "scripts/link")
        data, html = self.generate()
        self.assertFalse(marker.exists(), "The generator executed shell code")
        self.assertTrue(any(node["file"] == "bash/.bashrc" for node in data["nodes"]))
        self.assertFalse(any(node["file"] in {"ignored/ignored.sh", "scripts/link"} for node in data["nodes"]))
        embedded = re.search(r'<script id="graph-data" type="application/json">(.*?)</script>', html, re.S)[1]
        self.assertIn("</script>", json.dumps(data), "The HTML escaping check needs a literal closing script tag")
        self.assertEqual(json.loads(embedded), data)
        self.assertNotIn("<script>", embedded)
        self.assertNotRegex(html, r'<(?:script|link)[^>]+(?:src|href)="https?://')
        again, second_html = self.generate()
        self.assertEqual(data, again)
        self.assertEqual(html, second_html)

    def test_source_wrapper_calls_preserve_import_visibility(self):
        self.write("scripts/config-loader", """#!/usr/bin/env bash
load_any() {
    local config_file=$2
    builtin source "$config_file"
}
load_in_child() { bash -c 'source "$1"' child "$1"; }
""")
        self.write("scripts/extra-lib", "#!/usr/bin/env bash\nloaded() { true; }\n")
        self.write("scripts/load-entry", """#!/usr/bin/env bash
ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/config-loader"
load_any ignored "$ROOT/tools.env"
load_any ignored "$ROOT/scripts/extra-lib"
consume() { loaded; printf '%s\\n' "${TOOLS[@]}"; }
consume
""", executable=True)
        self.write("scripts/load-unrelated", """#!/usr/bin/env bash
ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/config-loader"
load_in_child "$ROOT/tools.env"
command load_any ignored "$ROOT/tools.env"
consume() { printf '%s\\n' "${TOOLS[@]}"; }
consume
""", executable=True)
        data, _ = self.generate()
        loader = self.node(data, "scripts/config-loader", "load_any")
        consume = self.node(data, "scripts/load-entry", "consume")
        self.assertTrue(self.edges(data, "file:scripts/load-entry", loader, "call"))
        self.assertTrue(self.edges(data, "file:scripts/load-entry", "file:tools.env", "source"))
        self.assertTrue(self.edges(data, loader, "file:tools.env", "source"))
        self.assertTrue(self.edges(data, consume, self.node(data, "tools.env", "TOOLS"), "read"))
        self.assertTrue(self.edges(data, consume, self.node(data, "scripts/extra-lib", "loaded"), "call"))
        self.assertFalse(self.edges(data, "file:scripts/load-unrelated", "file:tools.env", "source"))
        self.assertFalse(self.edges(data, self.node(data, "scripts/load-unrelated", "consume"),
                                    self.node(data, "tools.env", "TOOLS"), "read"))

    def test_repository_setup_and_split_test_chains(self):
        data, _ = self.generate(root=REPO)
        main = self.node(data, "setup-tools", "main")
        self.assertTrue(self.edges(data, main, self.node(data, "setup-tools", "preflight"), "call"))
        self.assertTrue(self.edges(data, main, self.node(data, "tools.env", "TOOLS"), "read"))
        self.assertTrue(self.edges(data, "file:setup-system", "file:system.env", "source"))
        self.assertTrue(self.edges(data, "file:setup-system", self.node(data, "scripts/setup-lib", "load_config"), "call"))
        self.assertTrue(self.edges(data, "file:setup-tools", "file:scripts/setup-recipes-lib", "source"))
        self.assertTrue(self.edges(data, "file:bash/.bashrc", "file:bash/.bash_history_lib", "source"))
        self.assertTrue(any(node["kind"] == "function" and node["file"] == "bash/.bash_history_lib" for node in data["nodes"]))
        entry = next(node for node in data["nodes"] if node["id"] == "file:setup-tools")
        self.assertEqual(entry["role"], "")
        self.assertTrue(self.edges(data, "file:tests/dotfiles_release_runner.sh",
                                   "file:tests/dotfiles_release/health_test.sh", "execute"))
        self.assertTrue(self.edges(data, "file:tests/setup_tools_runner.sh", "file:tests/setup_tools/install_test.sh", "execute"))

    def test_entry_labels_use_launch_commands_only(self):
        self.write("automation/publish", "#!/usr/bin/env bash\nsource scripts/shared-lib\nworker\n", executable=True)
        self.write("automation/ci-check.sh", "#!/usr/bin/env bash\ntrue\n")
        self.write("README.md", "```bash\nbash scripts/entry\n```\n")
        self.write("Taskfile.yaml", """version: '3'
tasks:
    publish:
        summary: |
            bash scripts/unrelated
        cmds:
            - bash "{{.ROOT_DIR}}/automation/publish"
            - |
                printf '%s\\n' 'bash scripts/unrelated'
                command -v scripts/unrelated
                bash -n scripts/unrelated
                source scripts/shared-lib
                unused() { bash scripts/unrelated; }
            - task: other
    other:
        cmds:
            - 'bash automation/publish'
""")
        self.write(".github/workflows/check.yaml", """name: Checks
jobs:
  check:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          path: 'tooling'
      - name: Run checks
        env:
          run: bash scripts/unrelated
        run: >-
          env MODE=ci bash tooling/automation/ci-check.sh
          --check
      - run: |
          printf '%s\\n' 'bash scripts/unrelated'
          command -v scripts/unrelated
          bash -n scripts/unrelated
          unused() { bash scripts/unrelated; }
          bash "$GITHUB_WORKSPACE/tooling/automation/publish"
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          repository: example/other
          path: external
      - run: bash external/scripts/unrelated
""")
        data, _ = self.generate()
        files = {node["file"]: node for node in data["nodes"] if node["kind"] in {"script", "env"}}
        self.assertEqual(files["automation/publish"]["role"], "task entry, workflow entry")
        self.assertEqual(files["automation/publish"]["tasks"], ["other", "publish"])
        self.assertEqual(files["automation/ci-check.sh"]["role"], "workflow entry")
        self.assertEqual(files["automation/ci-check.sh"]["workflows"], [".github/workflows/check.yaml"])
        self.assertEqual(files["tools.env"]["role"], "configuration")
        for path in ("scripts/entry", "scripts/shared-lib", "scripts/unrelated", "tests/entry_test.sh"):
            self.assertEqual(files[path]["role"], "", path)

    def test_another_repository_uses_its_own_paths_and_env_names(self):
        self.root = self.root.parent / "different checkout"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, timeout=10)
        self.write("config/runtime.env", """declare -ga FEATURES=(one two)
POLICY_ALLOW=confidential-example
POLICY_DENY=confidential-example
""")
        self.write("modules/shell helpers/common.inc", """. "${BASH_SOURCE[0]%/*}/leaf.bits"
load_spec() { local selected=$1; source "$selected"; }
work() { leaf; printf '%s\\n' "${FEATURES[@]}"; }
""")
        self.write("modules/shell helpers/leaf.bits", "leaf() { true; }\n")
        self.write("automation/run jobs", """#!/usr/bin/env bash
root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/modules/shell helpers/common.inc"
load_spec "$root/config/runtime.env"
start() {
    local group=$1
    work
    declare -p "POLICY_$group"
    "$root/automation/child"
    curl https://example.invalid
}
start "$@"
""", executable=True)
        self.write("automation/child", "#!/usr/bin/env bash\ntrue\n", executable=True)
        self.write("test/smoke.sh", '#!/usr/bin/env bash\nbash "automation/run jobs"\n')
        self.write("test/fixtures/curl", "#!/usr/bin/env bash\ntrue\n", executable=True)
        data, html = self.generate(parser=None)
        start = self.node(data, "automation/run jobs", "start")
        work = self.node(data, "modules/shell helpers/common.inc", "work")
        leaf = self.node(data, "modules/shell helpers/leaf.bits", "leaf")
        self.assertTrue(self.edges(data, "file:automation/run jobs", "file:config/runtime.env", "source"))
        self.assertTrue(self.edges(data, start, work, "call"))
        self.assertTrue(self.edges(data, work, leaf, "call"))
        self.assertTrue(self.edges(data, work, self.node(data, "config/runtime.env", "FEATURES"), "read"))
        for name in ("POLICY_ALLOW", "POLICY_DENY"):
            references = self.edges(data, start, self.node(data, "config/runtime.env", name), "reference")
            self.assertEqual(len(references), 1)
            self.assertEqual(references[0]["certainty"], "possible")
        self.assertTrue(self.edges(data, start, "file:automation/child", "execute"))
        self.assertFalse(self.edges(data, start, "file:test/fixtures/curl"))
        self.assertTrue(self.edges(data, "file:test/smoke.sh", "file:automation/run jobs", "execute"))
        self.assertTrue(next(node for node in data["nodes"] if node["id"] == "file:test/smoke.sh")["test"])
        self.assertNotIn("confidential-example", html)
        self.assertFalse(any(node["file"] in {"setup-tools", "tools.env", "system.env"} for node in data["nodes"]))


if __name__ == "__main__":
    if not PARSER:
        raise SystemExit("shfmt is required; run task map or task validate:scripts")
    unittest.main()
