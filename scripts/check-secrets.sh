#!/usr/bin/env bash

set -euo pipefail

if git ls-files | grep -Eq '(^|/)(\.env($|\.)|.*\.(p8|p12|mobileprovision)$)'; then
  echo "Tracked environment or signing files are not allowed."
  git ls-files | grep -E '(^|/)(\.env($|\.)|.*\.(p8|p12|mobileprovision)$)'
  exit 1
fi

secret_pattern='(sk-(live|test|proj|or-v1)-?[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9]{20,}|xai-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|phc_[A-Za-z0-9]{20,}|sb_(secret|publishable)_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})'

if git grep -nEI "$secret_pattern" -- . \
  ':(exclude)scripts/check-secrets.sh'; then
  echo "Potential credential material found in tracked files."
  exit 1
fi

echo "Tracked-file credential scan passed."
