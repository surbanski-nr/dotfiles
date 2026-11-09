#!/usr/bin/env bash

health_yq() {
  local release=$1 health_home=$2 output
  local work=$health_home/yq

  mkdir -p "$work" || return
  local expected
  expected=$(metadata_value "$release/release.env" YQ_VERSION) || return
  output=$("$release/bin/yq" --version) || return
  [[ $output == "yq (https://github.com/mikefarah/yq/) version v${expected#v}" ]] || {
    report_error 'yq is not the pinned Mike Farah implementation'
    return 1
  }
  printf 'name: first\n---\nname: second\n' >"$work/documents.yaml" || return
  output=$("$release/bin/yq" eval -r '.name' "$work/documents.yaml") || return
  [[ $output == $'first\n---\nsecond' ]] || {
    report_error 'yq YAML document check failed'
    return 1
  }
}
