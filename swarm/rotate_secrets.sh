#!/usr/bin/env bash
# =============================================================================
# rotate-secrets.sh — creates/rotates Docker Swarm secrets for compose_swarm.yml
#
# USAGE:
#   ./rotate-secrets.sh [env-file]         (default: ./secrets.env)
#
#   STACK_NAME=avarim ./rotate-secrets.sh secrets.env
#   DRY_RUN=1 ./rotate-secrets.sh                # preview only, no changes
#
#   # inline, no file needed:
#   AVARIM_S3_API_KEY=xxx AVARIM_BUCKET_NAME=avarim-media ./rotate-secrets.sh
#
# VALUE RESOLUTION ORDER, per secret:
#   1. Already-exported shell/environment variable of that exact name
#      (e.g. set inline on the command line as above, or `export`ed earlier
#      in the same shell / CI job). Checked first, so it always wins.
#   2. The env file (KEY=VALUE, one per line, whole-line '#' comments ok),
#      only consulted for any secret NOT found in step 1:
#        AVARIM_S3_STORAGE_ENDPOINT=https://s3.example.com
#        AVARIM_S3_STORAGE_ACCESS_KEY=AKIA...
#        AVARIM_S3_STORAGE_SECRET_KEY=...
#        AVARIM_S3_API_KEY=...
#        AVARIM_BUCKET_NAME=avarim-media
#   3. Anything still unresolved after both falls through to the automatic
#      handling below:
#   - GENERATED with `openssl rand -base64 32`   (passwords, signing/token
#     secrets, Meili master key — pure entropy, safe to invent)
#   - MIRRORED from a related secret              (e.g. AVARIM_MONGODB_USERNAME <-
#     AVARIM_MONGO_INITDB_ROOT_USERNAME, so the app and mongo's root account
#     actually agree — nothing creates a separate app-level Mongo user in
#     this stack, so these two MUST match)
#   - DEFAULTED to a known-good internal value    (e.g. ME_CONFIG_MONGODB_
#     SERVER=mongo, AVARIM_MEILISEARCH_HOST=http://meilisearch:7700 — these are
#     just the in-network service DNS names)
#   - REQUIRED, and the script exits with an error if missing (S3 endpoint/
#     keys, bucket name — these come from your storage provider; auto-
#     generating them would silently break uploads instead of failing loud)
#
# ROTATION MODEL (why secret names get a hash suffix):
#   Docker secrets are immutable. This script content-hashes each resolved
#   value and creates a secret object named "<KEY>_<hash>". If the value
#   hasn't changed since last run, that hashed name already exists and the
#   step is skipped — reruns are idempotent/no-ops until a value changes.
#   When it HAS changed, the script does:
#     docker service update --secret-rm <old> \
#       --secret-add source=<KEY>_<hash>,target=<KEY> <service>
#   so the file inside the container is still /run/secrets/<KEY> regardless
#   of which hashed object backs it.
#
#   FIRST RUN CAVEAT: before any service is deployed, compose_swarm.yml's
#   `secrets:` block uses `external: true` with the *literal* names
#   (AVARIM_MONGODB_USERNAME, etc.) — `docker stack deploy` needs a secret object
#   with that exact name to exist already. So for any secret whose target
#   service isn't deployed yet, this script seeds the literal name instead
#   of a hashed one. Once you've run `docker stack deploy`, every future
#   run of this script switches that secret over to hash+rotate mode
#   automatically. After the first rotation, re-running a plain
#   `docker stack deploy` will NOT pick up further secret changes on its
#   own (it only looks for the original literal name) — use this script,
#   not stack deploy, for all rotations going forward.
# =============================================================================

set -euo pipefail

STACK_NAME="${STACK_NAME:-avarim}"
ENV_FILE="${1:-secrets.env}"
DRY_RUN="${DRY_RUN:-0}"

for bin in docker openssl jq; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "ERROR: '$bin' is required but not found in PATH." >&2
        exit 1
    }
done

# This VPS runs docker under sudo. Route every `docker ...` call in this
# script through here instead of prefixing each call site individually, so
# nothing gets missed if more docker calls are added later. Set
# DOCKER_SUDO=0 to drop sudo (e.g. if the deploy user is later added to the
# docker group).
DOCKER_SUDO="${DOCKER_SUDO:-1}"
docker() {
    if [[ "$DOCKER_SUDO" == "1" ]]; then
        command sudo docker "$@"
    else
        command docker "$@"
    fi
}

if command -v sha256sum >/dev/null 2>&1; then
    hash_of() { printf '%s' "$1" | sha256sum | cut -c1-12; }
elif command -v shasum >/dev/null 2>&1; then
    hash_of() { printf '%s' "$1" | shasum -a 256 | cut -c1-12; }
else
    echo "ERROR: need sha256sum or shasum in PATH." >&2
    exit 1
fi

docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active ||
    {
        echo "ERROR: this node is not part of an active Swarm." >&2
        exit 1
    }

# -----------------------------------------------------------------------------
# Ordered list of secrets this stack uses. Order matters: mirror/default
# entries assume their source secret has already been resolved above them.
# -----------------------------------------------------------------------------
SECRET_ORDER=(
    AVARIM_MELIPAYAMAK_USERNAME
    AVARIM_MELIPAYAMAK_API_KEY
    AVARIM_MELIPAYAMAK_FROM
    AVARIM_ZARINPAL_MERCHANT_ID
    AVARIM_ZIBAL_MERCHANT_ID
    AVARIM_TTS_API_KEY
    AVARIM_BUCKET_NAME
    AVARIM_S3_STORAGE_ENDPOINT
    AVARIM_S3_STORAGE_ACCESS_KEY
    AVARIM_S3_STORAGE_SECRET_KEY
    AVARIM_S3_API_KEY
    AVARIM_MONGODB_USERNAME
    AVARIM_MONGODB_PASSWORD

    AVARIM_STREAM_SIGNING_SECRET
    AVARIM_ACCESS_TOKEN_SECRET
    AVARIM_REFRESH_TOKEN_SECRET

    AVARIM_MONGO_INITDB_ROOT_USERNAME
    AVARIM_MONGO_INITDB_ROOT_PASSWORD

    AVARIM_ME_CONFIG_MONGODB_ADMINUSERNAME
    AVARIM_ME_CONFIG_MONGODB_ADMINPASSWORD

    AVARIM_REDIS_USERNAME
    AVARIM_REDIS_PASSWORD
    AVARIM_REDIS_MASTER_PASSWORD

    AVARIM_GF_SECURITY_ADMIN_USER
    AVARIM_GF_SECURITY_ADMIN_PASSWORD

    AVARIM_MEILI_MASTER_KEY
    AVARIM_MEILISEARCH_KEY
)

declare -A MODE=(
    [AVARIM_MELIPAYAMAK_USERNAME]="required"
    [AVARIM_MELIPAYAMAK_API_KEY]="required"
    [AVARIM_MELIPAYAMAK_FROM]="required"
    [AVARIM_ZARINPAL_MERCHANT_ID]="required"
    [AVARIM_ZIBAL_MERCHANT_ID]="required"
    [AVARIM_TTS_API_KEY]="required"
    [AVARIM_BUCKET_NAME]="required"
    [AVARIM_S3_STORAGE_ENDPOINT]="required"
    [AVARIM_S3_STORAGE_ACCESS_KEY]="required"
    [AVARIM_S3_STORAGE_SECRET_KEY]="required"
    [AVARIM_S3_API_KEY]="required"
    [AVARIM_MONGODB_USERNAME]="required"
    [AVARIM_MONGODB_PASSWORD]="required"

    [AVARIM_STREAM_SIGNING_SECRET]="generate"
    [AVARIM_ACCESS_TOKEN_SECRET]="generate"
    [AVARIM_REFRESH_TOKEN_SECRET]="generate"

    [AVARIM_MONGO_INITDB_ROOT_USERNAME]="mirror:AVARIM_MONGODB_USERNAME"
    [AVARIM_MONGO_INITDB_ROOT_PASSWORD]="mirror:AVARIM_MONGODB_PASSWORD"

    [AVARIM_ME_CONFIG_MONGODB_ADMINUSERNAME]="mirror:AVARIM_MONGODB_USERNAME"
    [AVARIM_ME_CONFIG_MONGODB_ADMINPASSWORD]="mirror:AVARIM_MONGODB_PASSWORD"

    [AVARIM_REDIS_USERNAME]="mirror:AVARIM_MONGODB_USERNAME"
    [AVARIM_REDIS_PASSWORD]="mirror:AVARIM_MONGODB_PASSWORD"
    [AVARIM_REDIS_MASTER_PASSWORD]="mirror:AVARIM_MONGODB_PASSWORD"

    [AVARIM_GF_SECURITY_ADMIN_USER]="mirror:AVARIM_MONGODB_USERNAME"
    [AVARIM_GF_SECURITY_ADMIN_PASSWORD]="mirror:AVARIM_MONGODB_PASSWORD"

    [AVARIM_MEILI_MASTER_KEY]="generate"
    [AVARIM_MEILISEARCH_KEY]="mirror:AVARIM_MEILI_MASTER_KEY"
)

declare -A TARGET_SERVICE=(
    [AVARIM_MELIPAYAMAK_USERNAME]="avarim"
    [AVARIM_MELIPAYAMAK_API_KEY]="avarim"
    [AVARIM_MELIPAYAMAK_FROM]="avarim"
    [AVARIM_ZARINPAL_MERCHANT_ID]="avarim"
    [AVARIM_ZIBAL_MERCHANT_ID]="avarim"
    [AVARIM_REDIS_USERNAME]="avarim"
    [AVARIM_REDIS_PASSWORD]="avarim"
    [AVARIM_TTS_API_KEY]="avarim"
    [AVARIM_MONGODB_USERNAME]="avarim"
    [AVARIM_MONGODB_PASSWORD]="avarim"
    [AVARIM_BUCKET_NAME]="avarim"
    [AVARIM_S3_STORAGE_ENDPOINT]="avarim"
    [AVARIM_S3_STORAGE_ACCESS_KEY]="avarim"
    [AVARIM_S3_STORAGE_SECRET_KEY]="avarim"
    [AVARIM_S3_API_KEY]="avarim"
    [AVARIM_MEILISEARCH_KEY]="avarim"

    [AVARIM_MONGO_INITDB_ROOT_USERNAME]="mongo"
    [AVARIM_MONGO_INITDB_ROOT_PASSWORD]="mongo"

    [AVARIM_ME_CONFIG_MONGODB_ADMINUSERNAME]="mongo-express"
    [AVARIM_ME_CONFIG_MONGODB_ADMINPASSWORD]="mongo-express"

    [AVARIM_GF_SECURITY_ADMIN_USER]="grafana"
    [AVARIM_GF_SECURITY_ADMIN_PASSWORD]="grafana"

    [AVARIM_MEILI_MASTER_KEY]="meilisearch"

    [AVARIM_STREAM_SIGNING_SECRET]="avarim"
    [AVARIM_ACCESS_TOKEN_SECRET]="avarim"
    [AVARIM_REFRESH_TOKEN_SECRET]="avarim"

    [AVARIM_REDIS_MASTER_PASSWORD]="redis"
)

# -----------------------------------------------------------------------------
# Load user-provided values. Whole-line comments only (a line starting with
# '#') — we deliberately do NOT strip inline '#' so a secret value that
# happens to contain '#' isn't silently truncated.
# -----------------------------------------------------------------------------
declare -A PROVIDED=()
if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
        '' | '#'*) continue ;;
        esac
        [[ "$line" != *=* ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        PROVIDED["$key"]="$val"
    done <"$ENV_FILE"
    echo "Loaded ${#PROVIDED[@]} value(s) from $ENV_FILE"
else
    echo "No $ENV_FILE found — proceeding with generated/mirrored/default values only."
fi

# -----------------------------------------------------------------------------
# Resolve final value for every secret
# -----------------------------------------------------------------------------
declare -A VALUES=()
MISSING_REQUIRED=()

for key in "${SECRET_ORDER[@]}"; do
    # 1. Already-exported env var (inline on the command line, or exported
    #    earlier in this shell/CI job) always wins over the .env file.
    if [[ -n "${!key:-}" ]]; then
        VALUES["$key"]="${!key}"
        continue
    fi

    # 2. Fall back to whatever the .env file provided.
    if [[ -n "${PROVIDED[$key]:-}" ]]; then
        VALUES["$key"]="${PROVIDED[$key]}"
        continue
    fi

    mode="${MODE[$key]}"
    case "$mode" in
    generate)
        VALUES["$key"]="$(openssl rand -base64 32 | tr -d '\n')"
        ;;
    default:*)
        VALUES["$key"]="${mode#default:}"
        ;;
    mirror:*)
        src="${mode#mirror:}"
        if [[ -z "${VALUES[$src]:-}" ]]; then
            echo "ERROR: cannot mirror $key from $src — $src has no resolved value." >&2
            exit 1
        fi
        VALUES["$key"]="${VALUES[$src]}"
        ;;
    required)
        MISSING_REQUIRED+=("$key")
        ;;
    *)
        echo "ERROR: unknown mode '$mode' for $key" >&2
        exit 1
        ;;
    esac
done

if ((${#MISSING_REQUIRED[@]} > 0)); then
    echo "" >&2
    echo "ERROR: these secrets have no safe default and were not found in $ENV_FILE:" >&2
    printf '  - %s\n' "${MISSING_REQUIRED[@]}" >&2
    echo "They come from your storage provider, not entropy — add them to $ENV_FILE." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Create / rotate each secret
# -----------------------------------------------------------------------------
for key in "${SECRET_ORDER[@]}"; do
    value="${VALUES[$key]}"
    hashed_name="${key}_$(hash_of "$value")"
    service_short="${TARGET_SERVICE[$key]}"
    service_name="${STACK_NAME}_${service_short}"

    if docker service inspect "$service_name" >/dev/null 2>&1; then
        # Service is already deployed -> hash + rotate mode.
        if docker secret inspect "$hashed_name" >/dev/null 2>&1; then
            echo "OK        $key: unchanged (secret $hashed_name already exists)"
            continue
        fi

        echo "CREATE    $hashed_name"
        if [[ "$DRY_RUN" != "1" ]]; then
            printf '%s' "$value" | docker secret create "$hashed_name" - >/dev/null
        fi

        old_name="$(docker service inspect "$service_name" \
            --format '{{json .Spec.TaskTemplate.ContainerSpec.Secrets}}' 2>/dev/null |
            jq -r --arg target "$key" '.[]? | select(.File.Name == $target) | .SecretName' |
            head -n1 || true)"

        if [[ -n "$old_name" && "$old_name" != "$hashed_name" ]]; then
            echo "ROTATE    $service_name: $key  ($old_name -> $hashed_name)"
            if [[ "$DRY_RUN" != "1" ]]; then
                docker service update \
                    --secret-rm "$old_name" \
                    --secret-add "source=${hashed_name},target=${key}" \
                    "$service_name" >/dev/null
            fi
        else
            echo "ATTACH    $service_name: $key  (no previous secret found — attaching $hashed_name)"
            if [[ "$DRY_RUN" != "1" ]]; then
                docker service update \
                    --secret-add "source=${hashed_name},target=${key}" \
                    "$service_name" >/dev/null
            fi
        fi
    else
        # Service not deployed yet -> seed the literal name compose's
        # `external: true` secret expects, so the first `docker stack deploy`
        # just works.
        if docker secret inspect "$key" >/dev/null 2>&1; then
            echo "OK        $key: literal secret already exists (bootstrap already done)"
            continue
        fi
        echo "BOOTSTRAP creating literal secret '$key' for initial stack deploy"
        if [[ "$DRY_RUN" != "1" ]]; then
            printf '%s' "$value" | docker secret create "$key" - >/dev/null
        fi
    fi
done

echo ""
echo "Done — secret values are never printed above, only names/hashes."
[[ "$DRY_RUN" == "1" ]] && echo "(DRY_RUN=1 — nothing was actually created or updated.)"
