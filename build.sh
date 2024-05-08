#!/bin/bash

# Variables
retype_version="3.5.0"
use_dotnet=false
_ifs="${IFS}"

if [ ! -e "${GITHUB_ACTION_PATH}/functions.inc.sh" ]; then
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Unable to locate functions.inc.sh file."
  exit 1
fi

source "${GITHUB_ACTION_PATH}/functions.inc.sh" || {
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Error including functions.inc.sh."
  exit 1
}

if [ ! -z "${INPUT_CONFIG_PATH}" ]; then
  if [ ! -e "${INPUT_CONFIG_PATH}" ]; then
    fail "Path to Retype config could not be found: ${INPUT_CONFIG_PATH}"
  fi
  echo "Path to Retype config: ${INPUT_CONFIG_PATH}"
fi

echo "Working directory is: $(pwd)"

# We prefer dotnet if available as the package size is (much) smaller.
if which dotnet > /dev/null 2>&1 && [ "$(dotnet --version | cut -f1 -d.)" -ge 5 ]; then
  use_dotnet=true
elif ! which node > /dev/null 2>&1 || [ "$(node --version | cut -f1 -d. | cut -b2-)" -lt 14 ]; then
  fail "Cannot find a suitable dotnet or node installation to install the retype package with."
fi

retype_path="$(which retype 2> /dev/null)"
retstat="${?}"

if [ ${retstat} -eq 0 ]; then
  if [ "$(retype --version | strings)" == "${retype_version}" ]; then
    echo "Using existing retype installation at: ${retype_path}"
  else
    fail "Found existing installation of retype for a different version than this action is intended to work with.
Expected version: ${retype_version}
Available version: $(retype --version | strings)

Action aborted due to mismatched Retype version."
  fi
else
  echo -n "Installing Retype v${retype_version} using "
  if ${use_dotnet}; then
    echo -n "dotnet tool: "

    cmdln=(dotnet tool install --global --version ${retype_version} retypeapp)
    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "unable to install retype using the dotnet tool" "${cmdln[@]}" "${result}"
  else
    case "${RUNNER_OS}" in
      "Linux") plat="linux-x64";;
      "macOS") plat="darwin-x64";;
      "Windows") plat="win-x64";;
      *)
        echo "an unsupported OS."
        if [ -z "${RUNNER_OS}" ]; then
          fail "Unable to determine runner's OS to choose which NPM package to download."
        else
          fail "Unsupported runner OS: ${RUNNER_OS}"
        fi
        ;;
    esac
    echo -n "NPM package manager (${plat}): "

    cmdln=(npm install --global "retypeapp-${plat}@${retype_version}")
    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "unable to install retype using the NPM package manager" "${cmdln[@]}" "${result}"
  fi
  echo "done."
fi

# Check if the shared environment variable already exists for this workflow
if [ -z "${WORKFLOW_RETYPE_DIR}" ]; then
    echo -n "Temporary workflow directory: "
    # by letting it create the directory we can guarantee no other call to mktemp could reference
    # the same path.
    export WORKFLOW_RETYPE_DIR="$(mktemp -d)"
    echo "${WORKFLOW_RETYPE_DIR}"

    # Save the directory to a shared GitHub environment variable so other steps can reuse it
    echo "WORKFLOW_RETYPE_DIR=${WORKFLOW_RETYPE_DIR}" >> "${GITHUB_ENV}"
else
    echo -n "Reusing existing temporary workflow directory: "
    echo "${WORKFLOW_RETYPE_DIR}"
fi

workflowdir="${WORKFLOW_RETYPE_DIR}"
echo "Confirming temporary workflow directory: ${workflowdir}"

subdir=""
if [ -n "${INPUT_SUBDIR}" ]; then
  # Remove leading slash, if present
  subdir="${INPUT_SUBDIR##/}"
  echo "Output subdirectory: ${subdir}"
fi

# Construct the full destination directory path
if [ -n "${subdir}" ]; then
  destdir="${workflowdir}/${subdir}"
  # Create the full directory path with subdirectories
  mkdir -p "${destdir}"
else
  destdir="${workflowdir}"
fi

echo "Confirming temporary target folder: ${destdir}"

echo -n "Setting up build arguments: "

if [ "${INPUT_VERBOSE}" == "true" ]; then
  echo -n "Enable verbose logging during build process"
  cmdargs=(--verbose)
fi

# cf_path ensures path is converted in case we are running from windows
config_output="$(cf_path "${destdir}")" || fail_nl "unable to parse output path: ${destdir}"

overridestr="$(append_json "" "output" "${config_output}")" || \
  fail_nl "Unable to append output path setting while building the 'retype build' argument list."

# Initialize an empty variable to store the config file path
config_file_path=""

# Use the provided path if available
if [ -n "${INPUT_CONFIG_PATH}" ] && [ -e "${INPUT_CONFIG_PATH}" ]; then
  config_file_path="${INPUT_CONFIG_PATH}"
  echo "Using provided configuration file: ${config_file_path}"

# Check for known configuration file names sequentially
elif [ -e "retype.yml" ]; then
  config_file_path="retype.yml"
  echo "Found retype.yml"

elif [ -e "retype.yaml" ]; then
  config_file_path="retype.yaml"
  echo "Found retype.yaml"

elif [ -e "retype.json" ]; then
  config_file_path="retype.json"
  echo "Found retype.json"

else
  # No valid configuration file was found
  echo "::warning file=${BASH_SOURCE},line=${LINENO}::No Retype configuration file found. Please provide a valid file or path."
fi

# Ensure the path variable is passed to subsequent commands if a file was found
if [ -n "${config_file_path}" ]; then
  cmdargs+=("${config_file_path}")
fi

if [ "${INPUT_STRICT}" == "true" ]; then
  echo -n "strict mode, "
  cmdargs+=("--strict")
fi

if [ ! -z "${INPUT_LICENSE_KEY}" ]; then
  echo -n "license key, "
  cmdargs+=("--secret" "${INPUT_LICENSE_KEY}")
fi

overridestr="{
${overridestr}
}"
cmdargs+=("--override" "${overridestr}")

echo "done."

echo -n "Building documentation: "

cmdln=(retype build "${cmdargs[@]}")
result="$("${cmdln[@]}" 2>&1)" || \
  fail_cmd true "retype build command failed with exit code ${retstat}" "${cmdln[*]}" "${result}"

if [ ! -e "${destdir}/resources/js/config.js" ]; then
  fail_nl "Retype output not found after 'retype build' run. At least resources/js/config.js is missing from output."
fi

echo "done."

echo "::group::Command: ${cmdln[@]}
${result}
::endgroup::"

if ${missing_retypecf}; then
  result="$(rm "retype.yml" 2>&1)" || \
    fail_cmd true "unable to remove default retype.yml placed into repo root" "rm \"retype.yml\"" "${result}"
fi

echo "Output sent to: ${destdir}"
if [ "${config_output}" != "${destdir}" ]; then
  echo " (${config_output})"
fi
echo "" # break line after the message above is done being composed.

# This makes the output path available via the
# 'steps.stepId.outputs.retype-output-path' reference, unique for the step.
echo "retype-output-path=${workflowdir}" >> "${GITHUB_OUTPUT}"

# This makes the output path available via the $RETYPE_OUTPUT_PATH that doesn't
# require referencing but is reset by the last ran build step if more than one
# are assigned to a job.
echo "RETYPE_OUTPUT_PATH=${workflowdir}" >> "${GITHUB_ENV}"

# perform a quick clean-up to remove temporary, untracked files
echo -n "Cleaning up repository..."

result="$(git reset HEAD -- . 2>&1)" || \
  fail_cmd comma "unable to git-reset repository back to HEAD after Retype build." "git reset HEAD -- ." "${result}"

echo -n ", git-checkout"
result="$(git checkout -- . 2>&1)" || \
  fail_cmd comma "unable to git-checkout repository afresh after Retype build." "git checkout -- ." "${result}"

echo -n ", git-clean"
result="$(git clean -d -x -q -f 2>&1)" || \
  fail_cmd comma "unable to clean up repository after Retype build." "git clean -d -x -q -f" "${result}"

echo " done.
Retype build completed successfully."