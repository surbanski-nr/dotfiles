# Tool updates and rollback notes

Use this runbook to test a new version before changing the normal setup.
Archive candidates need an exact version and an upstream SHA-256 digest;
Git plugins need a repository and full commit pin. Run the same checks used
for normal installation. Keep current and candidate installations until
rollback has been tested.

Run the commands below from the repository root.

For adding a new tool or disabling an existing one, follow
[adding and removing tools](setup.md#adding-and-removing-tools).
This runbook covers version changes and rollback.

## Local development VM

Use an independent development clone, not the checkout used by the host's active
dotfiles symlinks. The checkout is shared writable, so editing a live configuration
would affect the host too. Keep the editor, tmux and Git operations on the host;
open guest shells in other host tmux panes to run installers and checks. There is
no need for nested tmux, SSH configuration or GitHub authentication in the VM.

The Linux x86-64 host needs KVM, an initialized LXD installation and access to
`lxc`, `jq`, `flock`, `curl` and the pinned Task executable. By default the task
explicitly selects LXD project `default`, network `lxdbr0` and storage `default`.
It does not change the client's current project or initialize LXD for you.
See [LXD projects, networks and host firewall](#lxd-projects-networks-and-host-firewall)
below to inspect these resources, configure a bridge or diagnose blocked traffic.
`dev` never edits host firewall rules. Bootstrap network failures are warnings:
the guest shell still opens so the VM can be repaired; missing prerequisites and
Task can be retried later.

```bash
bash scripts/install-validation-tool task
bin/task dev
bin/task dev -- debian13
bin/task dev -- ubuntu2404
bin/task dev -- ubuntu2604
bin/task dev -- amazonlinux2023
```

The native Task `--` separator forwards the short platform name. In `release.env`,
`PLATFORM_ALIASES` maps these names to release platform IDs and
`DEFAULT_DEV_PLATFORM` selects the VM opened without an argument.
`LXD_IMAGES` and `LXD_IMAGE_SHA256` select VM images; `DOCKER_IMAGES` selects
the independently pinned containers for `task test`. Debian and Ubuntu use
LXD cloud images; Amazon Linux uses the official KVM image with a checked SHA256
and a small cloud-init bootstrap for the LXD agent. Adding an alias or changing
an image does not require editing `Taskfile.yml`.

The Amazon Linux entries in `images:` currently provide containers, not VM
images. Amazon's generic KVM image is not preconfigured with the guest LXD agent
needed for `lxc exec` and the checkout mount. Its first-boot cloud-config runs
LXD's [documented agent installation](https://documentation.ubuntu.com/lxd/latest/howto/instances_create/#install-the-lxd-agent-into-virtual-machine-instances),
using the agent and installer exposed by LXD through its `config` filesystem
(9p or virtiofs). It does not reinstall host LXD or download/install dotfiles.
The script-local `lxc_command` wrapper only adds an explicit project and timeout
to noninteractive client operations; it does not override the daemon's `lxd`
command or change the client's default project.

The default VM has 1 vCPU, 16 GiB RAM and an 80 GiB root disk. The current Azure
host is itself a Hyper-V VM; both two- and eight-vCPU nested guests stalled under
full validation, although short two-vCPU probes passed. One vCPU passed native
validation on all supported OSes without changing host services or QEMU CPU
flags. Increase `DEV_CPUS` only after checking the larger allocation on your
host. Set resources when creating a VM; existing VMs keep their allocation.
Put overrides before `--`:

```bash
bin/task dev DEV_CPUS=1 DEV_MEMORY=8GiB DEV_DISK=40GiB -- ubuntu2404
# Custom initialized LXD resources:
bin/task dev DEV_PROJECT=default DEV_NETWORK=lxdbr0 DEV_STORAGE=default -- debian13
```

One persistent VM is reused per checkout and platform. Its name includes the
platform, checkout hash and creation timestamp; the task prints it on entry.
First boot can take several minutes; `dev` waits up to ten minutes for the LXD
agent after starting the VM. Guest preparation allows up to three attempts for
transient LXD connection failures; other preparation errors stop the task.
Run the same command in another host tmux pane for another shell in that VM.
`lxc exec` opens a local terminal session, not an SSH connection. Exiting a shell
does not stop the VM or other sessions.

The checkout is mounted at `/workspace/dotfiles`, the shell's initial directory.
The ordinary guest user has the host's UID/GID and passwordless guest-only sudo.
Only this checkout is shared. The guest has its own kernel, systemd, HOME,
the managed release store, asdf installations, history and Docker storage. Host HOME, SSH keys and
Docker sockets are never mounted. The checkout's `bin/` is masked with a guest
bind mount backed by `~/.local/share/dotfiles-validation`; host executables and
absolute Python venv paths are neither used nor changed. The task bootstraps
only minimal download/Git/sudo prerequisites and the pinned private Task, exposed
through a guest-local `/usr/local/bin/task` link.

Prepare the actual candidate inside the VM, using the normal installers:

```bash
./setup-system
./setup-tools
./setup-asdf

./scripts/dotfiles-release set online
./bstow stow mc
exit
```

Reopen with `task dev` on the host to pick up Docker group membership and the
new shell configuration. `dev` itself does not preinstall editor or tmux
plugins. The normal `./setup-tools` step above installs tmux plugins; use
Nvim's normal setup when testing that profile. Edit and commit on the host,
then run the relevant checks in the guest:

```bash
./setup-tools nvim
hash -r
nvim --version
dotfiles-check
task validate
bash nvim2/.config/nvim2/tests/check_runner.sh
task test -- debian13
# In Nvim2: :checkhealth
```

`setup-tools` reuses an intact installation. A new version needs its complete
`version|full_URL|SHA256` record; rerunning installs it and switches the link
in `online/bin`. Earlier payloads remain in `online/tools` for rollback. Restart the
affected application after switching versions.

`task test` still uses Docker, building complete archives and installing them
as an ordinary user in separate containers with networking disabled. In the VM
it uses the VM's own Docker daemon; on the host it uses the host daemon. The
checkout must be clean and committed. Logs and packages remain under the printed
temporary directory in that environment, not in a host dotfiles installation.
Without a platform argument it checks `OFFLINE_TEST_PLATFORMS` in `release.env`.
Publication is selected separately by `OFFLINE_RELEASE_PLATFORMS` in that file.
Build and verification workers run in batches bounded by `nproc`, so a one-vCPU
guest runs one platform at a time rather than competing with three other builds.
A failed platform does not stop the remaining platforms, and verification only
runs for successful builds.

No extra down task or local VM-state database is needed. To stop an idle VM or
recreate it, use the exact name and project printed by `dev`:

```bash
vm_name=dotfiles-dev-debian13-CHECKOUT_HASH-TIMESTAMP
lxc --project default stop "$vm_name"
# Delete only that VM when its experiments are no longer needed:
lxc --project default delete "$vm_name"
task dev
```

Deleting a VM removes its installed tools, private validation files and Docker
data. The shared development checkout stays on the host. A stopped VM restarts
with `task dev`, which reapplies the private `bin/` bind mount after reboot.

## LXD projects, networks and host firewall

Run the commands in this section on the LXD host, not inside the development VM.
Inspection commands are read-only. Creating projects/bridges, changing network
settings and adding firewall rules are explicit administrator operations; `dev`
does not perform them. Review existing users of a resource before changing it.

### Select the project and bridge

`DEV_PROJECT` selects an LXD project, not a Git repository or a cloud project.
Projects separate instance names and can have their own profiles, images and
networks, depending on their `features.*` settings. `DEV_PROJECT=default` keeps
development VMs in the default LXD project even if the client's current project
is something else. Every `dev` LXC command explicitly passes `--project`.

`DEV_NETWORK` selects a managed LXD network for the VM's NIC. `lxdbr0` is the
usual bridge created by `lxd init`, similar to Docker's `docker0`: a virtual
switch with DHCP and normally NAT for outbound traffic. Its name is conventional,
not mandatory. A project name or a separate bridge alone is not a network
security boundary; VMs sharing a bridge can communicate unless policy blocks it.
The Docker daemon and `docker0` inside the VM are separate from the host's Docker.

```bash
lxc project list
lxc project show default
lxc --project default profile show default
lxc --project default storage list
lxc --project default network list
lxc --project default network show lxdbr0
ip -brief address show
ip -4 route show
```

Choose a network with type `bridge`, `MANAGED=YES`, the intended subnet and working
outbound connectivity. Inspect `ipv4.address`, `ipv4.nat`, and `used_by`; do not
select the host's physical NIC or Docker's unmanaged `docker0` as `DEV_NETWORK`.
With `features.networks=false`, a project shares the default project's networks.
With `features.profiles=false` or `features.images=false`, those resources are
also shared with `default`. Inspect the selected project's settings rather than
assuming a bridge or default profile is available there.

Normally use `bin/task dev` with no network override when the host firewall allows
`lxdbr0` forwarding. On the Azure host checked on 2026-11-04, both `lxdbr0` and
`k8cbr0` exist with IPv4 NAT enabled. The host's Docker firewall
has `FORWARD DROP`, but `DOCKER-USER` explicitly permits traffic from `k8cbr0`
and established replies to it, not `lxdbr0`. `k8cbr0` was already used by other
LXD VMs; it is a local workaround, not a dotfiles isolation requirement:

```bash
bin/task dev DEV_NETWORK=k8cbr0 -- debian13
```

This override applies only when creating a VM. If the task prints `Reusing`, the
existing NIC keeps its network: rerunning this command does not move a VM from
`lxdbr0` to `k8cbr0`. Use the explicit procedure in
[Move an existing VM to another bridge](#move-an-existing-vm-to-another-bridge)
below instead of deleting and recreating the VM.

If a separate instance namespace is useful, optionally create a project sharing
the default project's profiles, images and bridges. This avoids rebuilding the
default profile/storage setup; it does not create a separate host firewall:

```bash
lxc project create dotfiles-dev \
  -c features.profiles=false -c features.images=false -c features.networks=false
lxc project show dotfiles-dev
bin/task dev DEV_PROJECT=dotfiles-dev DEV_NETWORK=lxdbr0 -- debian13
```

### Inspect blocking and allowing rules

```bash
sysctl net.ipv4.ip_forward
sudo iptables --version
sudo iptables -S FORWARD
sudo iptables -L FORWARD -n -v --line-numbers
sudo iptables -S DOCKER-USER
sudo iptables -L DOCKER-USER -n -v --line-numbers
sudo iptables -S DOCKER-FORWARD
sudo iptables -S INPUT
sudo iptables -t nat -S POSTROUTING
# All IPv4 chains, including those reached through jumps:
sudo iptables-save -c
# LXD or another firewall manager may also install native nftables rules:
sudo nft list ruleset
```

Working guest DNS and a reachable bridge gateway do not prove outbound forwarding
works. On the Azure host above, guest TCP connections to `deb.debian.org:80` and
`github.com:443` timed out while host HTTPS requests succeeded. The missing
`lxdbr0` exception in Docker's forwarding rules caused the fetch failures despite
working DHCP, DNS and NAT configuration. Compare guest and host connectivity and
inspect forwarding rules before changing guest DNS or bridge addresses.

IPv4 forwarding must be `1`; NAT alone does not bypass a firewall drop. In
`iptables -S` output, `-P FORWARD DROP` is the fallback policy, `-j ACCEPT` allows
matching traffic, and `-j DROP` or `-j REJECT` blocks it. Follow jumps such as
`DOCKER-USER` and `DOCKER-FORWARD`; their order and the first matching terminal
rule matter. Packet counters help identify which rules receive the failed
connection's traffic. An accept in one nftables base chain can still be followed
by a drop in another, so inspect the complete ruleset when both tools are used.

`iptables --version` reporting `nf_tables` is the iptables compatibility frontend
and still supports the commands below. Docker's native nftables firewall backend
is different and has no `DOCKER-USER` chain. If that chain is absent, or UFW,
firewalld or another manager owns the policy, configure that manager's forwarding
rules; do not create a disconnected `DOCKER-USER` chain or mix backends blindly.
For enabled IPv6, inspect `sudo ip6tables -S FORWARD` too; IPv4 exceptions do not
fix or secure IPv6 forwarding.

If the VM has no DHCP lease or cannot reach the bridge's DNS service, inspect
host `INPUT` rules as well. LXD normally supplies these rules for its managed
bridge. Opening `FORWARD` does not open DHCP/DNS ports on the host, and allowing
all host input is not an appropriate repair.

### Configure a new bridge or repair the standard one

Create a separate managed bridge only if one is actually wanted. LXD can choose
an IPv4 subnet automatically; inspect it for conflicts with host, VPN, Docker,
other LXD and remote networks before use. This example keeps the new bridge
IPv4-only and does not change existing bridges:

```bash
lxc --project default network create devbr0 \
  ipv4.address=auto ipv4.nat=true ipv6.address=none
lxc --project default network show devbr0
```

Alternatively, retain the existing `lxdbr0` and enable NAT only if it is missing:

```bash
lxc --project default network show lxdbr0
lxc --project default network set lxdbr0 ipv4.nat=true
```

Changing `ipv4.address` is not needed to fix a forwarding drop and can disrupt
every VM using that bridge. Review `used_by`, plan new DHCP leases and route
changes, and keep a recovery path before changing a shared subnet.

If IPv4 forwarding was disabled, enable it only after reviewing host policy:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

This sysctl change is temporary. For a deliberate persistent setting, use the
host's existing sysctl configuration, or edit an administrator-owned file such
as `/etc/sysctl.d/60-lxd-dev-forwarding.conf` containing
`net.ipv4.ip_forward=1`. Do not overwrite unrelated sysctl settings.

On a host using Docker's iptables backend, allow the chosen bridge's outbound
traffic and established replies in `DOCKER-USER`. Replace `dev_bridge` with
`devbr0` for the new bridge; choose `dev_uplink` from `ip -4 route show`, not from
the example name. These exceptions are limited to that bridge and uplink:

```bash
dev_bridge=lxdbr0
dev_uplink=eth0
ip link show dev "$dev_bridge"
ip link show dev "$dev_uplink"
sudo iptables -S DOCKER-USER

sudo iptables -C DOCKER-USER -i "$dev_bridge" -o "$dev_uplink" -j ACCEPT ||
  sudo iptables -I DOCKER-USER 1 -i "$dev_bridge" -o "$dev_uplink" -j ACCEPT
sudo iptables -C DOCKER-USER -i "$dev_uplink" -o "$dev_bridge" \
  -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT ||
  sudo iptables -I DOCKER-USER 1 -i "$dev_uplink" -o "$dev_bridge" \
    -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Check that the interfaces and chain exist before running the insertion commands.
The `-C` checks prevent adding duplicates on repeat runs. Inserting at the start
places these scoped exceptions before an existing blocking rule. They allow VMs
to initiate connections through the chosen uplink, including reachable LAN/VPN
destinations; they do not allow unsolicited inbound connections or isolate VMs
from each other. Do not flush chains, disable the firewall, or set the whole
`FORWARD` policy to `ACCEPT` to fix one bridge.

These are runtime rules. Use the host's existing firewall persistence mechanism
for the same scoped exceptions and recheck them after reboot or Docker restart.
Do not blindly save/restore Docker's and LXD's generated NAT/container rules.
To remove only the two exceptions added above, reuse the same interface values:
do not remove pre-existing rules that the `-C` checks merely reused.

```bash
sudo iptables -D DOCKER-USER -i "$dev_bridge" -o "$dev_uplink" -j ACCEPT
sudo iptables -D DOCKER-USER -i "$dev_uplink" -o "$dev_bridge" \
  -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

### Move an existing VM to another bridge

After repairing `lxdbr0`, use `bin/task dev`. After preparing `devbr0`, use
`bin/task dev DEV_NETWORK=devbr0`. `DEV_NETWORK` is applied when creating a VM;
changing it does not move an already-existing VM. For a dev-created VM, inspect
its local NIC, stop only that VM, and change its device explicitly. Stopping closes
its active shells but preserves the VM's disk, installed tools and Docker data.
Choose `k8cbr0` for the Azure host above, or another inspected working bridge:

```bash
dev_vm=dotfiles-dev-debian13-CHECKOUT_HASH-TIMESTAMP
dev_network=k8cbr0
lxc --project default config device show "$dev_vm"
lxc --project default stop "$dev_vm" --timeout 60
lxc --project default config device set "$dev_vm" eth0 "network=$dev_network"
bin/task dev DEV_NETWORK="$dev_network" -- debian13
```

Replace the VM name, project and NIC device name with the inspected values.
Dev-created VMs have a local `eth0` device; an inherited NIC on another VM needs
`lxc config device override` instead. Do not change the shared default profile
just to move one VM. Reconnecting can change its address, so verify routes, DNS
and a bounded HTTPS request inside the guest, then inspect host counters again:

```bash
ip -4 route show
getent ahostsv4 github.com
curl --fail --show-error --location --connect-timeout 5 --max-time 20 \
  --output /dev/null https://github.com
```

## Disposable candidate

Start from an independent clone. The build scripts require a real `.git`
directory. A clone contains committed files only. If the candidate depends on
local changes, copy them deliberately and inspect the resulting diff:

```bash
candidate_root=$(mktemp -d "$HOME/dotfiles-candidate.XXXXXX")
git clone --local --no-hardlinks "$PWD" "$candidate_root/current"
git diff --binary HEAD -- . ':!.cache' >"$candidate_root/working.patch"
if [[ -s $candidate_root/working.patch ]]; then
  git -C "$candidate_root/current" apply "$candidate_root/working.patch"
fi
git ls-files --others --exclude-standard -z |
  tar --null --files-from=- -cf - |
  tar -C "$candidate_root/current" -xf -
git -C "$candidate_root/current" status --short

cp -a "$candidate_root/current" "$candidate_root/candidate"
```

Edit only the intended records in `candidate/tools.env` or builder images in
`candidate/release.env`. `TOOL_RELEASES` stores ordered
`version|full_URL|SHA256` records. The first record is the
default and cannot fall back if its artifact is absent. Actionlint, ShellCheck
and Task use `TOOL_RELEASES` for setup and offline releases. Repository
validation and GitHub Actions use independent `VALIDATION_RELEASES` in
`validation.env`. Yamllint's validation pin is independent of its editor
and offline-package Python locks.
`ASDF_PLUGINS` owns plugin repository and commit pins, while runtime versions
still come from `TOOL_RELEASES`.
`TMUX_PLUGINS` uses the same `repository|commit` records. For a tmux plugin
bump, change its commit there, and the repository only when deliberately moving
upstream. Plugin targets in `TOOLS` and `OFFLINE_RELEASE_TOOLS` use the same
installer; their ordered profile entries also define startup order.

For a normal dependency bump, edit only its first record in `tools.env`. Run
the focused setup in the disposable candidate, then `task validate` and the
affected platform build and offline checks. To go back, restore the earlier
record as the first record and rerun the same checks. Do not edit generated
Python locks for an unrelated tool bump.

For a repository validation tool bump, edit its record in `validation.env`
and run `task validate`. For yamllint, edit `YAMLLINT_VERSION` in that file.

Htop and tmux records point to official source archives. Both connected setup
and offline release builds compile them through the shared source-build helper,
so test both paths when changing either record.

For a daily tool, install the current selection first, record its version and
canonical link, then run the candidate from the other read-only checkout. This
tested example uses Debian 13 and an immutable image digest. Replace `TOOL` and
the version check for another daily tool:

```bash
image='debian@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a'
tool=k9s

docker run --rm \
  --tmpfs /home/candidate:exec,uid=1000,gid=1000 \
  --mount "type=bind,src=$candidate_root/current,dst=/src-current,readonly" \
  --mount "type=bind,src=$candidate_root/candidate,dst=/src-candidate,readonly" \
  "$image" sh -euxc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl
    useradd --uid 1000 --home-dir /home/candidate candidate
    chown candidate:candidate /home/candidate
    su candidate -s /bin/bash -c '\''set -euo pipefail
      HOME=/home/candidate /src-current/setup-tools '"$tool"'
      readlink "$HOME/dotfiles-releases/online/bin/'"$tool"'" >"$HOME/baseline-link"
      "$HOME/dotfiles-releases/online/bin/'"$tool"'" version --short
      HOME=/home/candidate /src-candidate/setup-tools '"$tool"'
      "$HOME/dotfiles-releases/online/bin/'"$tool"'" version --short
      test -x "$HOME/dotfiles-releases/online/bin/$(cat "$HOME/baseline-link")"'\''
  '
```

The checkout mounts are read-only and the candidate home is a disposable
`tmpfs`. Never mount the normal home, asdf data or working checkout writable.
Delete a rejected candidate with `rm -rf -- "$candidate_root"`; it cannot have
changed the normal selection.

For an offline candidate, build and verify a complete platform release using
[setup.md](setup.md#complete-offline-release). Do not assemble or import
individual tool archives with `setup-tools`; that script is connected-only.

After the disposable trial, run the setup qualification on Debian 13, Ubuntu
24.04, Ubuntu 26.04 and Amazon Linux 2023. A successful container trial alone
does not qualify a new selection.

## Daily-tool rollback

Versioned installations and their state are retained under
`~/dotfiles-releases/online/tools` and `online/state/setup-tools`. Inspect them before switching:

```bash
ls -l "$HOME/dotfiles-releases/online/bin/k9s" "$HOME/dotfiles-releases/online/tools/bin/k9s-"*
"$HOME/dotfiles-releases/online/tools/bin/k9s-0.50.18" version --short
```

For a persistent rollback, put the earlier complete
`version|full_URL|SHA256` record first for that tool in `TOOL_RELEASES`, then
run this command from that reviewed revision:

```bash
./setup-tools k9s
```

If the retained installation is intact, the script reuses it without a new
download. If it is absent, the script downloads the pinned release again.
The same procedure applies to `gh`, `oh-my-posh`, `rg`, Task, actionlint,
ShellCheck and the complete `nvim-VERSION` executable tree. Their records
also supply offline builds. The private validation bootstrap keeps its own
selection in `validation.env`.
Mason ShellCheck keeps its own editor pin.

A temporary switch may update only an existing managed relative link. Check
both the current target and requested executable first:

```bash
cd "$HOME/dotfiles-releases/online/bin"
case $(readlink k9s) in
  ../tools/bin/k9s-*)
    ;;
  *)
    exit 1
    ;;
esac
test -x ../tools/bin/k9s-0.50.18
ln -s ../tools/bin/k9s-0.50.18 .k9s.rollback
mv -T .k9s.rollback k9s
hash -r
type -a k9s
k9s version --short
```

The next `setup-tools k9s` selects the first catalog record again. Keep the
older complete record in `tools.env` for a persistent rollback. Treat `uv`
with `uvx`, `kubectx` with `kubens`, and the complete Go SDK with `gofmt`, as
paired selections. Do not switch only one of the Go SDK links.

## Isolated k9s and MC skin previews

### k9s tasks inside the development VM

From the dotfiles checkout inside `task dev`, run:

```bash
task k9s
# After closing k9s, clean up whenever the preview is no longer needed:
task k9s:clean
```

The Taskfile only invokes `scripts/k9s-preview`. The script creates or reuses
one checkout-specific kind cluster, applies `tests/k9s-preview.yaml`, starts
an immediate Job when absent and opens k9s in its preview namespace with
`--readonly`. Exiting k9s, including Ctrl+C, does not clean up the cluster;
reopening the task reuses it. Cleanup refuses to run while that preview is open.
Read-only mode is a UI guard, not an RBAC or filesystem sandbox.

Have Task, kubectl, kind, k9s and a running local Docker Engine available first.
`docker info` must succeed for the intended user. Normal `./setup-system`
installs and starts Docker and adds the invoking user to its group; log out and
back in afterward. See the [Docker setup notes](setup.md#docker).
`./setup-tools kubectl kind k9s` provides the clients. The preview task does not
install software, change group membership or use remote Docker contexts.
Docker daemon access is root-equivalent.

Budget roughly two CPUs, 2 GiB of available memory and a few GiB of disk space.
The first start downloads the kind node and workload images and may take a few
minutes. The pinned node-image digest lives only in `scripts/k9s-preview`;
keep it compatible with the kind version in `tools.env` when updating.
Offline releases include the clients, not Docker or container images.

The private profile is `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-k9s/<checkout-hash>/`.
It contains a private kubeconfig, caches, logs and writable k9s directories.
Only existing configuration and skin YAML files are symlinked to the checkout,
not the entire k9s directory. The pinned k9s reads existing configuration but
creates context history, benchmarks, dumps and missing default files alongside it;
those generated files must not land in the repository. No configuration is
copied. Edit `k9s/.config/k9s/skins/surb.yaml` or `config.yaml` in the checkout
and reopen `task k9s` to see the changes without relying on live reload.
The normal kubeconfig and application profiles are not changed.

`task dev` forwards the host's `TERM` and `COLORTERM` into the guest shell.
K9s uses `COLORTERM=truecolor` (or `24bit`) to recognize RGB support; without
it, `tmux-256color` can reduce skin colors to the 256-color palette, making
blue-grey accents appear neutral grey. Re-enter `task dev` after updating an
older shell. If the host terminal supports truecolor, an existing guest shell
can also run `COLORTERM=truecolor task k9s`. The task does not force RGB support
when the host has not advertised it.

The checkout path and local Docker endpoint identify the owned preview. If
creation or deployment fails, its private directory remains available for a
retry or `task k9s:clean`. Cleanup deletes only this cluster and its profile;
Docker images and an empty sibling `<checkout-hash>.lock` file remain. The lock
stays outside the deleted profile so cleanup cannot race with another session.

### Manual preview profile

The following manual commands are for an existing disposable Kubernetes
cluster or an MC preview. The k9s tasks above do not need these copy steps.
Run these Bash commands from the root of a dotfiles clone. They copy the
candidate configuration rather than stowing it or pointing a writable app
directly at the checkout. Only the child processes receive the temporary
environment; normal host settings and the shell's current directory are not
changed.

Prepare a private preview directory:

```bash
preview_checkout=$(pwd -P)
preview_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-skin-preview.XXXXXX")
mkdir -p "$preview_root/.config/mc" "$preview_root/.cache" \
  "$preview_root/.local/share/mc" "$preview_root/.local/state"
cp -R "$preview_checkout/k9s/.config/k9s" "$preview_root/.config/"
cp "$preview_checkout/mc/.config/mc/ini" "$preview_root/.config/mc/"
cp -R "$preview_checkout/mc/.local/share/mc/skins" "$preview_root/.local/share/mc/"
printf 'Preview directory: %s\n' "$preview_root"
```

### k9s on an existing disposable cluster

Use only a disposable cluster where you are allowed to create and delete a
namespace. Do not use a production context. Set its explicit context below;
the commands never change the original kubeconfig's current context.
Flattening a private, single-context copy also preserves relative certificate
paths and works when `KUBECONFIG` names multiple files. This copy contains
credentials; keep it private and remove it after the preview.

```bash
preview_context='REPLACE-WITH-DISPOSABLE-CONTEXT'
kubectl --context "$preview_context" config view --minify --flatten --raw \
  >"$preview_root/kubeconfig"
```

#### Deploy the fixture

```bash
preview_kubectl() {
  command kubectl --kubeconfig "$preview_root/kubeconfig" \
    --cache-dir "$preview_root/.cache/kube" \
    --context "$preview_context" --namespace dotfiles-k9s-preview "$@"
}

preview_kubectl create namespace dotfiles-k9s-preview &&
  preview_kubectl apply -f "$preview_checkout/tests/k9s-preview.yaml" &&
  preview_kubectl rollout status deployment/preview-logger --timeout=90s
```

Namespace creation must succeed. If it already exists, stop and inspect it;
do not reuse or delete someone else's namespace. The fixture contains a
logging Deployment, a ConfigMap and Secret with deliberately fake values, and
a CronJob scheduled every minute. Each Job stays running for ten seconds,
then randomly exits with 0 or 1. Retries are disabled; five successful and five
failed scheduled Jobs are retained so their different states remain visible.
Several runs may be needed to see both outcomes. No Service, persistent volume,
privileged container or Kubernetes API access from a Pod is required.

After successful deployment, optionally start a Job immediately rather than
waiting for the next minute:

```bash
preview_kubectl create job preview-now --from=cronjob/preview-random
```

The pinned BusyBox image must be available to the cluster. In a disconnected
cluster, preload it using that cluster's image import mechanism. Starting kind
without network access additionally requires Docker and the pinned node image
to be prepared in advance. The dotfiles offline archive includes kind, not
Docker or container images. This fixture is opt-in; setup and offline-release
installation do not deploy it. A metrics-server is not required for skin
previews; without one, CPU and memory columns show unavailable values.

Launch the copied skin and config:

```bash
env XDG_CONFIG_HOME="$preview_root/.config" \
  XDG_DATA_HOME="$preview_root/.local/share" \
  XDG_CACHE_HOME="$preview_root/.cache" \
  XDG_STATE_HOME="$preview_root/.local/state" \
  K9S_CONFIG_DIR="$preview_root/.config/k9s" \
  K9S_LOGS_DIR="$preview_root/.local/state/k9s" \
  KUBECACHEDIR="$preview_root/.cache/kube" \
  k9s --kubeconfig "$preview_root/kubeconfig" --context "$preview_context" \
  --namespace dotfiles-k9s-preview --readonly
```

Use `:pods`, `:deployments`, `:jobs`, `:cronjobs`, `:configmaps`,
`:secrets` and `:events`. In Pods, press `l` for logs; use `y` for YAML,
`d` for describe and `?` for the available keys in each view. Inspect running,
completed and failed rows, selected rows, headers, dialogs, logs and YAML.
Read-only mode is a UI guard, not an RBAC or filesystem sandbox.

The `surb` skin uses `bgColor: default` to preserve the terminal background.
Use a dark terminal background with its light foreground palette. Selected
table rows keep black text on a light background so their contrast does not
depend on the terminal's default foreground color. K9s uses each row's status
color as its selection background, so these colors must contrast with black
text. Running rows use explicit `white` (`#ffffff`), while Completed uses
`steelblue` to remain distinct by hue as well as brightness. Running does not
use `default`: that would also use the terminal background for its selected
row, losing contrast with the black selection text. Other light UI accents
retain `#d0d0d0`.
Breadcrumbs such as `<pod>` and `<namespace>` use black text on the muted
white accent; the active breadcrumb uses `aqua`. These small backgrounds are
deliberately explicit so their contrast does not depend on the terminal theme.
The `active` palette anchor is shared with active namespace/context rows and
view-title highlights, keeping the active accent in one place.
Namespace labels such as `all` in view titles are bold `aqua`. Added and
initializing rows use `ghostwhite`, and errors use `pink`, as in
[BlackAndWtf](https://github.com/derailed/k9s/blob/master/skins/black-and-wtf.yaml).
Active namespace/context rows use k9s's default `aqua` instead of that theme's
low-contrast `darkslategray`. K9s shares `frame.status.highlightColor` between
those active rows and Initialized pods, so Initialized uses `aqua` too. This
is separate from `frame.title.highlightColor`, also set to `aqua` in titles.
Like BlackAndWtf, `surb` leaves `pendingColor` unset, so Pending and
ContainerCreating inherit k9s's `darkorange`.

YAML keys and the `:` separator share the same `ghost` foreground anchor.
Keep the explicit `colonColor` alias: omitting it would inherit stock `white`,
not the key color. The upstream BlackAndWtf file uses the unsupported spelling
`colorColor`; the pinned k9s recognizes `colonColor`.

Edit the copied `$preview_root/.config/k9s/skins/surb.yaml` to experiment, or
edit the clone and copy the changed skin over again. To try another bundled
skin, change `k9s.ui.skin` in the copied `config.yaml`. Restart k9s with the
same command after each change; this does not depend on live reload being
enabled. Config, context history, dumps and logs remain under the preview root.
The Kubernetes discovery cache is also isolated; XDG variables alone do not
redirect its default `~/.kube/cache` location.

### Midnight Commander

MC stores its skin and history under the data directory, not just its config
directory. `MC_PROFILE_ROOT` explicitly isolates all three MC directories;
`--skin` selects the copied skin even if the host has an `MC_SKIN` override.
`--nosubshell` avoids sourcing the host's Bash startup files. Run the executable
through `env` so shell aliases/functions are not used.

Prepare a scratch file list so preview operations cannot accidentally change
files in the checkout:

```bash
mkdir -p "$preview_root/files/directory"
touch "$preview_root/files/regular.txt" "$preview_root/files/source.py"
cp "$preview_checkout/tests/fixtures/bash/command" "$preview_root/files/executable"
chmod +x "$preview_root/files/executable"
ln -s regular.txt "$preview_root/files/symlink"
ln -s missing "$preview_root/files/broken-symlink"

env MC_PROFILE_ROOT="$preview_root" \
  XDG_CONFIG_HOME="$preview_root/.config" \
  XDG_DATA_HOME="$preview_root/.local/share" \
  XDG_CACHE_HOME="$preview_root/.cache" \
  XDG_STATE_HOME="$preview_root/.local/state" \
  mc --nosubshell --skin="$preview_root/.local/share/mc/skins/surb.ini" \
  "$preview_root/files" "$preview_root/files"
```

Use Insert to mark files, F9 for menus, F1 for help and F10 to exit.
F5/F6/F8 and confirmation dialogs can be tried only on the scratch files.
Edit the copied `surb.ini`, or copy it again after editing the clone, then
restart MC with the same command. MC remains a file manager with ordinary user
permissions; temporary config is not a filesystem sandbox.

### Manual cleanup

After closing both applications, delete only the namespace created above and
the private preview directory. This route does not create or delete a cluster.
Skip the namespace command for an MC-only trial. For the VM task's cluster,
use `task k9s:clean` instead of these commands.

```bash
preview_kubectl delete namespace dotfiles-k9s-preview --wait=true --timeout=90s
unset -f preview_kubectl
find "$preview_root" -depth -delete
unset preview_checkout preview_context preview_root
```

## Go SDK and editor tools

The SDK version, official archive and SHA-256 live in `tools.env`. Go is a
direct `setup-tools go` installation, not an asdf runtime. Keep the full
`go-VERSION` tree when testing an upgrade or rollback; it contains the compiler
and standard library, not just two executables.

The gopls, goimports, golangci-lint and Delve pins live in
`nvim2/.config/nvim2/lua/custom/lsp.lua`. Keep their supported Go versions
compatible with the SDK. Mason performs its normal Go package builds in the
connected builder with `CGO_ENABLED=0` and `GOTOOLCHAIN=local`; no separate Go
installer or dependency-building logic is duplicated in shell or Lua. The
upstream golangci-lint binary must also support the selected project Go version.
Go changes do not require regenerating Python locks.

Run `task validate`, rebuild complete artifacts for every
`OFFLINE_TEST_PLATFORMS` target, and qualify them
with network access disabled as ordinary users. The tool-enabled Nvim2 suite
checks a real multi-file package, SDK compile/run/test, offline vendoring,
gopls diagnostics/navigation/hover/completion, import formatting, configured
golangci-lint diagnostics and real Delve breakpoint/variables/goroutines/step,
nearest-test and process cleanup. Test `set ID` between current packages with
and without `go` selected. Projects requiring another SDK, uncached modules or
CGO libraries need their own separately prepared dependencies.

## Python environments

The prompt deliberately does not display Python virtual environments. Bash
exports `VIRTUAL_ENV_DISABLE_PROMPT=1` so activation scripts do not add their
own prefix, and the Oh My Posh theme performs no venv discovery or rendering.

The Kubernetes segment starts toggled off in each shell session. Run `kp` to
toggle it. This uses Oh My Posh's segment toggle, so the disabled segment is
skipped before it reads or parses kubeconfig files.

The Python-backed Mason packages in a complete release are derived from
`custom.lsp` and the actual Mason receipts. Change a direct version only in
`nvim2/.config/nvim2/lua/custom/lsp.lua`, then regenerate both input and lock
files on a connected machine:

```bash
bash scripts/install-validation-tool task
bin/task update:python-locks
git diff -- tools.env nvim2/.config/nvim2/lua/custom/lsp.lua \
  nvim2/.config/nvim2/python-locks
```

The generator creates an empty HOME, installs the pinned `PIP_TOOLS_VERSION`
into a venv made with the pinned standalone Python, and reads `M.tools` plus
fresh Mason receipts through Neovim/Lua before resolving against
`https://pypi.org/simple`. It writes
the checked-in `.in` and hashed `.lock` files. For a preinstalled receipt tree,
set `DOTFILES_PYTHON_RECEIPTS` and `NVIM_BIN` explicitly. This is still a
connected operation unless every pip-tools and target dependency is supplied
through an explicitly complete index or `--find-links` workflow. Normal builds
do not resolve dependencies again. The target installs only the locked binary
wheels with `--no-index --require-hashes --only-binary=:all:` and runs
`pip check`; the standalone interpreter alone does not contain ansible-core,
ansible-lint, yamllint or debugpy. The resulting venv executables remain below the
Mason package tree. The release launcher keeps `~/bin` ahead of the private
release paths, followed by the ansible-lint venv, `release/bin` and `mason/bin`.

The Python debugger uses Mason's `debugpy` venv to run its adapter, not the
interpreter selected for the project. After changing the debugpy pin, regenerate
its lock, rebuild complete artifacts, and run the tool-enabled Nvim2 suite on
each platform with networking disabled. That suite starts real launch and
loopback-attach sessions and checks venv selection, locals, stepping, modules,
cursor-selected unittest, exceptions and process cleanup. Browser/TypeScript
adapters are deliberately not part of this profile.

## Offline kubectl and Helm versions

Keep each needed exact client version in `tools.env` as a complete
`version|full_URL|SHA256` record. The builder bundles every kubectl and Helm
record into each release, with the first record as its default. To add a
version, append a verified upstream record; to change the default, move the
required record first. Remove an old record only when it is no longer needed.
Do not change the launcher, regenerate Python locks or edit `release.env`.
Run `task validate`, build the matching platform package and qualify its
offline install and full CI qualification before deploying.

```bash
KUBECTL_VERSION=1.34.12 kubectl version --client
HELM_VERSION=3.21.0 helm version --short
unset KUBECTL_VERSION HELM_VERSION
```

A missing selection fails rather than downloading or using asdf. Whole-release
`dotfiles-release set ID` selects that installed payload and its defaults;
a shell override stays set until you unset it, so it must also exist there.

The offline Helm launcher accepts bare versions and one leading `v`. Its
default stays `4.3.0`; `3.21.0` is available for NetReveal.
Connected setup still selects direct links and does not implement
environment-based version selection.

The `helm-schema` artifact record in `tools.env` pins the offline `schema`
addon. Bump that record, then rebuild the ready binary and minimal no-hook
manifest through `build-dotfiles-release`. Keep the plugin's upstream license
when changing its distribution. yq uses the shared raw-artifact path and both
tool lists; jq stays an OS runtime prerequisite.
Do not edit generated metadata, installed plugin directories or Python locks.

Qualify new candidates on all four supported platforms with the prepared OS
baseline and network disabled for installation and CI qualification. Check every
Helm version with the bundled plugin, actual schema generation with local
references, yq multi-document processing and jq overlay merges. Qualification ignores
caller plugin overrides and user-owned `~/bin`. The tool-enabled editor checks must
opt in explicitly when they qualify save formatting; ordinary sessions start
with format on save disabled. Manual formatting is a one-time action.

Then run NetReveal's `task validate` and the PR `split-generate` path in a
disposable clone with project network inputs allowed. Use the private release
Python to create a suitable project venv, and export project Helm pins for the
entire invocation as shown in
[setup.md](setup.md#helm-schema-plugin-and-project-validation). Keep evidence
of Task/kubeconform compatibility; command availability alone is insufficient.
Use `set ID` to switch between packages built with the current archive
contract. For installations using an obsolete layout, follow the rebuild and
uninstall instructions in the setup guide before installing a new package.

## Online project runtime rollback

Python uses uv; Node.js, Terraform and Terragrunt remain under asdf. Offline releases do not
install or use asdf. Put the earlier release record first for
the tool in `TOOL_RELEASES`, then reconcile it:

```bash
./setup-tools python
uv python find --show-version
./setup-asdf terraform nodejs terragrunt
asdf current
```

Python setup installs the configured versions without public interpreter links,
then pins the first globally for uv. It does not migrate project version files.
Recreate a project's `.venv` deliberately when changing its interpreter; a
global pin does not replace an existing venv. Python artifacts are managed by
the pinned uv release's own download catalog, while offline builds keep their
explicit URL/SHA-256-pinned standalone runtime.

For asdf, the first version becomes the home default. A project's `.tool-versions` and
an `ASDF_<TOOL>_VERSION` environment override still take precedence. Keep all
required project versions in the list, use the asdf shims, and do not add
same-named launchers in `~/bin`. After changing Node.js or global npm tools,
run `asdf reshim nodejs VERSION` and check both `node --version` and
`npm --version`.

Kubectl and Helm are installed directly by `setup-tools` and included in the
default `TOOLS` list, not managed by `setup-asdf`.

Outside complete releases, online direct kubectl and Helm installations are
the multi-version case in `setup-tools`. Run a version-qualified executable
temporarily, or put the required version first and rerun setup:

```bash
"$HOME/dotfiles-releases/online/bin/kubectl-1.27.11" version --client
"$HOME/dotfiles-releases/online/bin/helm-3.21.0" version --short
./setup-tools kubectl helm
```

To roll back asdf itself or a plugin, restore its executable version, digest
or plugin commit in `tools.env`, run `setup-asdf`, and verify every retained
runtime. For connected tmux, restore the commit in `TMUX_PLUGINS` and rerun
`./setup-tools PLUGIN`, without deleting tmux-resurrect data. Both flows load
plugins directly without TPM. Offline rollback selects the complete retained
release, including its pinned plugins. Use Krew's supported manager install or
downgrade process so its plugin inventory is retained.

`setup-asdf` requires its own SHA-256 installation record even for the
current pin. It does not adopt an unrecorded historical binary or link.
A conflicting direct launcher, modified binary, different target or unrecorded
installation is left untouched and must be resolved explicitly before retrying.

For a recorded, intact asdf binary, the relative `online/bin/asdf` link is the selected
version. A manual switch between those verified binaries is accepted; the next
`setup-asdf` selects the catalog pin again. Old `asdf-target` and
`pending-selection` records do not override that link. Both online installers
share the release-root directory lock with the release manager. Do not run
installation and selection concurrently or replace the store to bypass a lock.

## Nvim2 candidate and health evidence

For retained offline releases, `dotfiles-release health [ID]` checks integrity
and light runtime probes without activation, defaulting to `current`.
Install and set share those probes. Their `--skip-health` flag bypasses runtime
diagnostics only, not integrity; it is not a way to edit installed payloads.
Full offline functional qualification remains part of `task test`.

Test a plugin change in the disposable checkout and data directories. Use the
documented `vim.pack` update command to regenerate `nvim-pack-lock.json`; never
edit that generated file. A quick copied-data trial does not replace a release
build from empty data.

Run the synchronous tool installation and full check with a timeout. Tool
checks must remain enabled for qualification:

```bash
timeout --signal=TERM --kill-after=30s 1200s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+Nvim2ToolsInstallSync' '+qa'
timeout --signal=TERM --kill-after=30s 1200s \
  env NVIM2_CHECK_TOOLS=1 nvim2/.config/nvim2/tests/check_runner.sh
```

Each Lua case has a 120-second limit, overridable with
`NVIM2_CHECK_TIMEOUT_SECONDS`. Cold TypeScript server/formatter startup and
asynchronous YAML formatting can wait up to 15 seconds; ESLint has 30 seconds.
The first Go SDK run and the first package/test debug builds have 60 seconds.
Other Go commands keep 30 seconds, and adapter requests, stepping and cleanup
keep 15 seconds. Exact formatting and debugger assertions remain enabled, and
startup benchmarks still report the measured times.

Capture unfiltered health and command output after asynchronous checks have
had time to finish:

```bash
evidence_dir=${1:-"$PWD/nvim2-health"}
mkdir -p "$evidence_dir"
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+Nvim2Check' '+checkhealth' '+sleep 10' \
  "+silent write! $evidence_dir/checkhealth.txt" \
  "+redir! > $evidence_dir/messages.txt" '+silent messages' '+redir END' \
  '+qa'
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+Mason' '+sleep 2' \
  "+silent write! $evidence_dir/mason.txt" '+qa'
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+ConformInfo' "+silent write! $evidence_dir/conform.txt" '+qa'
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+checkhealth vim.lsp' '+sleep 2' \
  "+silent write! $evidence_dir/lsp.txt" \
  '+qa'
cp "${XDG_STATE_HOME:-$HOME/.local/state}/nvim2/mason.log" \
  "$evidence_dir/mason.log"
```

The commands above capture `:ConformInfo`, `:checkhealth vim.lsp` and custom health output
for review. Review every warning and error. Record optional unavailable host
services instead of hiding their messages. Open representative Python, Lua,
Bash, TypeScript/TSX, Terraform, Ansible, Helm and YAML files and check LSP,
diagnostics, formatting, highlighting, folds and keys. Measure comparable
startup runs before and after the candidate.

Run `task validate`, build and disconnect-test every affected platform release,
then repeat the four-distribution qualification before transferring the
reviewed diff to the normal checkout.

## Complete offline release selection

Use `dotfiles-release set ID` to select an installed unit, including
all tools, configuration, plugins and language support. Existing Neovim and
tmux processes remain pinned to the physical release from which they started.
Follow
[the offline release runbook](../nvim2/.config/nvim2/offline-releases.md) for
checksum verification, activation and exact-ID uninstall. Older artifacts may
use their documented `~/.local/opt` executable roots; retain those roots during
migration.

Do not combine an older editor with arbitrary newer plugin data. Keep the
earlier release until editing and disconnected qualification checks pass.
`uninstall ID` deletes that retained directory. Removing the current ID also
restores adjacent original-file backups and clears `current`; plain
`uninstall` does this for the current ID. It does not select another release.
Close processes using the ID before removing it.

For an editor-independent recovery path, use `vi FILE` or `vim FILE`. To bypass
optional Vim configuration and plugins, use `vim -Nu NONE FILE`. For a Git
operation whose normal editor selects Neovim, run it with `GIT_EDITOR=vim`.
