#!/bin/bash
# Copyright 2025 ccorcov
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

JSON_FILE="mainnet-crc.json"       # publish output: sui client publish ... > test_testnet.json
OUT_FILE="launch_out_m1.json"           # where to write the launch tx result (json)

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install jq and retry." >&2
  exit 1
fi


command -v jq >/dev/null || { echo "jq is required"; exit 1; }
test -f "$JSON_FILE" || { echo "Publish JSON not found: $JSON_FILE"; exit 1; }

# Extract package id from publish output
PACKAGE_ID="$(jq -r '.objectChanges[] | select(.type=="published") | .packageId' "${JSON_FILE}")"
if [[ -z "${PACKAGE_ID}" || "${PACKAGE_ID}" == "null" ]]; then
  echo "Could not find packageId in ${JSON_FILE}" >&2
  exit 1
fi

BRIDGE_TOKEN_TYPE="${PACKAGE_ID}::bridge_token::BRIDGE_TOKEN"
TREASURY_TYPE="${PACKAGE_ID}::treasury::Treasury<${BRIDGE_TOKEN_TYPE}>"

# Find the shared Treasury object created during init
TREASURY_ID="$(jq -r --arg TYP "${TREASURY_TYPE}" '
  .objectChanges[]
  | select(.type=="created" and .objectType==$TYP)
  | .objectId
' "${JSON_FILE}" | head -n1)"

if [[ -z "${TREASURY_ID}" || "${TREASURY_ID}" == "null" ]]; then
  echo "Could not locate Treasury object of type ${TREASURY_TYPE} in ${JSON_FILE}" >&2
  exit 1
fi

echo "PACKAGE_ID        = $PACKAGE_ID"
echo "BRIDGE_TOKEN_TYPE = $BRIDGE_TOKEN_TYPE"
echo "TREASURY_TYPE     = $TREASURY_TYPE"
echo "TREASURY_ID       = $TREASURY_ID"
echo

GAS_BUDGET_DEFAULT=100000000

function mint_tokens() {
    local AMOUNT=200000000000000
    local RECEIVER="0x5196874c7677de5ea6b7c04ff0fcc6b090c662747ffd8cc3241c98c6f48a1dfa"
    sui client ptb \
        --move-call "${PACKAGE_ID}::treasury::mint_coin_to_receiver" \
            "<$BRIDGE_TOKEN_TYPE>" \
            @"$TREASURY_ID" \
            $AMOUNT \
            @"$RECEIVER" \
        --json \
        > mint_out_crc_t1.json

    echo "TX output saved to mint_out_crc_t1.json"

    # 7) Try to surface a created Coin<T>
    local COIN_TY="0x2::coin::Coin<${BRIDGE_TOKEN_TYPE}>"
    local NEW_COIN_ID
    NEW_COIN_ID="$(jq -r --arg T "$COIN_TY" '
        .objectChanges[] | select(.type=="created" and .objectType==$T) | .objectId
    ' mint_out_crc_t1.json | head -n1)"
    if [[ -n "$NEW_COIN_ID" && "$NEW_COIN_ID" != "null" ]]; then
        echo "Minted coin: $NEW_COIN_ID"
    else
        echo "Mint done (coin may have merged). Inspect mint_out_crc_t1.json."
    fi
}

function from_coin() {
    local RECEIVER="0x5196874c7677de5ea6b7c04ff0fcc6b090c662747ffd8cc3241c98c6f48a1dfa"
    sui client ptb \
        --move-call "$PACKAGE_ID::treasury::transfer_from_coin_cap" \
            "<$BRIDGE_TOKEN_TYPE>" \
            @"$TREASURY_ID" \
            @"$RECEIVER" \
        --json > grant_from_cap_out_t1.json

    echo "TX output saved to grant_from_cap_out_t1.json"

    # 5) Surface the created cap id (if visible in changes)
    local CAP_TY="${PACKAGE_ID}::treasury::FromCoinCap<${BRIDGE_TOKEN_TYPE}>"
    local CAP_ID
    CAP_ID="$(jq -r --arg T "$CAP_TY" '
        .objectChanges[] | select(.type=="created" and .objectType==$T) | .objectId
    ' grant_from_cap_out_t1.json | head -n1)"

    if [[ -n "$CAP_ID" && "$CAP_ID" != "null" ]]; then
        echo "Granted FromCoinCap id: $CAP_ID"
    else
        echo "Grant done (cap may not show as 'created' if it existed/merged). Inspect grant_from_cap_out_t1.json."
    fi
}

function to_coin() {
    local RECEIVER="0x5196874c7677de5ea6b7c04ff0fcc6b090c662747ffd8cc3241c98c6f48a1dfa"
    sui client ptb \
        --move-call "$PACKAGE_ID::treasury::transfer_to_coin_cap" \
            "<$BRIDGE_TOKEN_TYPE>" \
            @"$TREASURY_ID" \
            @"$RECEIVER" \
        --json > grant_to_cap_out_t1.json

    echo "TX output saved to grant_to_cap_out_t1.json"

    # 5) Surface the created cap id (if visible in changes)
    local CAP_TY="${PACKAGE_ID}::treasury::ToCoinCap<${BRIDGE_TOKEN_TYPE}>"
    local CAP_ID
    CAP_ID="$(jq -r --arg T "$CAP_TY" '
        .objectChanges[] | select(.type=="created" and .objectType==$T) | .objectId
    ' grant_to_cap_out_t1.json | head -n1)"

    if [[ -n "$CAP_ID" && "$CAP_ID" != "null" ]]; then
        echo "Granted ToCoinCap id: $CAP_ID"
    else
        echo "Grant done (cap may not show as 'created' if it existed/merged). Inspect grant_to_cap_out_t1.json."
    fi
}


# This script takes in a function name as the first argument, 
# and runs it in the context of the script.
if [ -z $1 ]; then
  echo "Usage: bash run.sh <function>";
  exit 1;
elif declare -f "$1" > /dev/null; then
  "$@";
else
  echo "Function '$1' does not exist";
  exit 1;
fi
