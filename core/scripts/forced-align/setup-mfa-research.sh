#!/usr/bin/env bash
# Prepare a research-only Montreal Forced Aligner environment.
#
# MFA is intentionally not part of the native app bundle. It depends on Conda
# packages and Kaldi, so this script creates/uses an isolated environment under
# the LLPlayerNext research cache and downloads the requested MFA models there.
set -euo pipefail

research_root="${LLPLAYERNEXT_MFA_DIR:-$HOME/Library/Caches/LLPlayerNext/research/mfa}"
env_prefix="${LLPLAYERNEXT_MFA_ENV:-$research_root/env}"
dictionary_model="${LLPLAYERNEXT_MFA_DICTIONARY:-english_mfa}"
acoustic_model="${LLPLAYERNEXT_MFA_ACOUSTIC:-english_mfa}"

mkdir -p "$research_root"

if [[ -x "$env_prefix/bin/mfa" ]]; then
  mfa_bin="$env_prefix/bin/mfa"
else
  micromamba_bin="${MICROMAMBA:-$(command -v micromamba || true)}"
  mamba_bin="${MAMBA:-$(command -v mamba || true)}"
  conda_bin="${CONDA:-$(command -v conda || true)}"

  if [[ -n "$micromamba_bin" ]]; then
    "$micromamba_bin" create -y -p "$env_prefix" -c conda-forge montreal-forced-aligner
  elif [[ -n "$mamba_bin" ]]; then
    "$mamba_bin" create -y -p "$env_prefix" -c conda-forge montreal-forced-aligner
  elif [[ -n "$conda_bin" ]]; then
    "$conda_bin" create -y -p "$env_prefix" -c conda-forge montreal-forced-aligner
  else
    cat >&2 <<EOF
No conda-compatible installer found.

Install micromamba, mamba, or conda first, then rerun this script.
Recommended by MFA docs:
  mamba create -n aligner -c conda-forge montreal-forced-aligner

This script will use:
  $env_prefix
EOF
    exit 1
  fi
  mfa_bin="$env_prefix/bin/mfa"
fi

"$mfa_bin" version
"$mfa_bin" model download dictionary "$dictionary_model"
"$mfa_bin" model download acoustic "$acoustic_model"

cat <<EOF
MFA research environment ready:
  $env_prefix

Models:
  dictionary: $dictionary_model
  acoustic:   $acoustic_model

Example:
  $mfa_bin align CORPUS_DIR $dictionary_model $acoustic_model OUTPUT_DIR
EOF
