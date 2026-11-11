#!/usr/bin/env bash

health_terraform() {
  local bin=$1 health_home=$2
  local work=$health_home/terraform

  mkdir -p "$work" || return
  printf 'terraform{required_version=">= 1.0"}\n' >"$work/main.tf" || return
  printf 'example_value="offline"\n' >"$work/terraform.tfvars" || return
  "$bin/terraform" fmt "$work/main.tf" "$work/terraform.tfvars" || return
  "$bin/terraform" fmt -check "$work/main.tf" "$work/terraform.tfvars" || return
  grep --fixed-strings 'example_value = "offline"' "$work/terraform.tfvars" || return
}
