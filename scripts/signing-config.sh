#!/bin/bash

load_signing_config() {
  # Empty and unset values both use the file fallback, matching ${VAR:-}.
  local environment_identity="${SIGNING_IDENTITY:-}"
  local environment_team="${TEAM_ID:-}"
  local environment_profile="${NOTARY_PROFILE:-}"
  if [[ -f "$1" ]]; then
    # This is the user's trusted shell configuration, not a dotenv file.
    source "$1"
  fi
  export SIGNING_IDENTITY="${environment_identity:-${SIGNING_IDENTITY:-}}"
  export TEAM_ID="${environment_team:-${TEAM_ID:-}}"
  export NOTARY_PROFILE="${environment_profile:-${NOTARY_PROFILE:-}}"
}
