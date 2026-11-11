#!/usr/bin/env bash

health_stage() {
  local label=$1 status
  shift

  printf '%s: checking %s\n' "${0##*/}" "$label"
  "$@" && return
  status=$?
  report_error "$label health check failed (status $status)" || true
  return "$status"
}

health_chart() {
  local chart=$1
  mkdir -p "$chart/templates" || return
  printf '%s\n' 'apiVersion: v2' 'name: offline-health' 'version: 0.1.0' \
    >"$chart/Chart.yaml"
  printf '{}\n' >"$chart/values.yaml" || return
  printf '{}\n' >"$chart/values.lint.yaml" || return
  printf '%s\n' 'apiVersion: v1' 'kind: ConfigMap' 'metadata:' \
    '  name: {{ .Release.Name }}' >"$chart/templates/config.yaml" || return
}

health_kubeconfig() {
  local kubeconfig=$1
  printf '%s\n' \
    'apiVersion: v1' \
    'kind: Config' \
    'clusters:' \
    '- name: offline-a' \
    '  cluster: {server: https://127.0.0.1:1}' \
    '- name: offline-b' \
    '  cluster: {server: https://127.0.0.1:1}' \
    'users:' \
    '- name: offline' \
    '  user: {token: offline}' \
    'contexts:' \
    '- name: offline-a' \
    '  context: {cluster: offline-a, user: offline, namespace: default}' \
    '- name: offline-b' \
    '  context: {cluster: offline-b, user: offline, namespace: default}' \
    'current-context: offline-a' >"$kubeconfig" || return
}
