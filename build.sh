#!/bin/bash

retype_version="3.12.0-preview"
use_dotnet=false
_ifs="${IFS}"

echo "Retype version:  v${retype_version}"

if ! command -v node &> /dev/null; then
    echo "Node.js not available"
else
    echo "Node.js version: $(node --version)"
fi

if ! command -v dotnet &> /dev/null; then
    echo "dotnet not available"
else
    echo "dotnet version:  $(dotnet --version)"
fi

if [ ! -e "${GITHUB_ACTION_PATH}/functions.inc.sh" ]; then
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Unable to locate functions.inc.sh file."
  exit 1
fi

source "${GITHUB_ACTION_PATH}"/functions.inc.sh || {
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Error including functions.inc.sh."
  exit 1
}

if [ ! -z "${INPUT_CONFIG_PATH}" ] && [ ! -e "${INPUT_CONFIG_PATH}" ]; then
  fail "Path to Retype config could not be found: ${INPUT_CONFIG_PATH}"
fi

echo "Working directory: $(pwd)"

# We prefer dotnet if available as the package size is (much) smaller.
if command -v dotnet &> /dev/null && [[ $(dotnet --version | cut -f1 -d.) -ge 9 ]]; then
  use_dotnet=true
elif ! command -v node &> /dev/null || [[ $(node --version | cut -f1 -d. | cut -b2-) -lt 18 ]]; then
  fail "Cannot find a suitable dotnet or Node.js installation to install the Retype package with"
fi

retype_path="$(which retype 2> /dev/null)"
retstat="${?}"

if [ ${retstat} -eq 0 ]; then
  if [ "$(retype --version | strings)" == "${retype_version}" ]; then
    echo "Using existing retype installation at: ${retype_path}"
  else
    fail "Found existing installation of Retype for a different version than this action \
is intended to work with.
Expected version: ${retype_version}
Available version: $(retype --version | strings) 

${abortbuildmsg}"

  fi
else
  echo -n "Installing Retype v${retype_version} using "
  if ${use_dotnet}; then
    echo -n "dotnet tool: "

    cmdln=(dotnet tool install --global retypeapp --version ${retype_version})

    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "Unable to install Retype using the dotnet tool" "${cmdln[@]}" "${result}"
    
    echo "done"
  else
    case "${RUNNER_OS}" in
      "Linux") plat="linux-x64";;
      "macOS") plat="darwin-x64";;
      "Windows") plat="win-x64";;
      *)
        echo "an unsupported OS."
        if [ -z "${RUNNER_OS}" ]; then
          fail "Unable to determine runner's OS to choose which NPM package to download"
        else
          fail "Unsupported runner OS: ${RUNNER_OS}"
        fi
        ;;
    esac
    echo -n "NPM package manager (${plat}): "

    cmdln=(npm install --global "retypeapp-${plat}@${retype_version}")

    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "Unable to install Retype using the NPM package manager" "${cmdln[@]}" "${result}"

    echo "done"
    echo "Retype install command: ${cmdln[*]}"
  fi
fi

# Check if the shared environment variable already exists for this workflow
if [ -z "${WORKFLOW_RETYPE_DIR}" ]; then
    # by letting it create the directory we can guarantee no other call to mktemp could reference
    # the same path.
    export WORKFLOW_RETYPE_DIR="$(mktemp -d)"

    # Save the directory to a shared GitHub environment variable so other steps can reuse it
    echo "WORKFLOW_RETYPE_DIR=${WORKFLOW_RETYPE_DIR}" >> "${GITHUB_ENV}"
else
    echo -n "Reusing existing temporary workflow directory: "
    echo "${WORKFLOW_RETYPE_DIR}"
fi

workflowdir="${WORKFLOW_RETYPE_DIR}"
echo "Workflow directory: ${workflowdir}"

subdir=""
if [ -n "${INPUT_OUTPUT}" ]; then
  # Remove leading slash, if present
  subdir="${INPUT_OUTPUT##/}"
fi

# Construct the full destination directory path
if [ -n "${subdir}" ]; then
  destdir="${workflowdir}/${subdir}"
  # Create the full directory path with subdirectories
  mkdir -p "${destdir}"
else
  destdir="${workflowdir}"
fi

echo "Target directory: ${destdir}"

# cf_path ensures path is converted in case we are running from windows
config_output="$(cf_path "${destdir}")" || fail_nl "Unable to parse output path: ${destdir}"

missing_retypecf=false
if [ ! -z "${INPUT_CONFIG_PATH}" ]; then
  # In case path is a directory and there's no Retype conf file,
  # the process is supposed to fail (we won't try 'retype init')
  cmdargs+=("${INPUT_CONFIG_PATH}")
else
  if [ -e "retype.yml" ]; then
    echo "/retype.yml"
  elif [ -e "retype.yaml" ]; then
    echo "/retype.yaml"
  elif [ -e "retype.json" ]; then
    echo "/retype.json"
  else
    locate_cf="$(find ./ -mindepth 2 -maxdepth 3 -not -path "*/.*" -a \( \
      -iname retype.yml -o -iname retype.yaml -o -iname retype.json \) | cut -b 2-)"

    if [ -z "${locate_cf}" ]; then
      missing_retypecf=true
      echo "Initialize default configuration:"
      result="$(retype init --verbose 2>&1)" || \
        fail_cmd comma \
          "'retype init' command failed with exit code ${retstat}" \
          "retype init --verbose" "${result}"
      echo "::warning::No Retype project configuration file found, using default values.
::group::Command: retype init --verbose
${result}
::endgroup::"
    else
      cf_count="$(echo "${locate_cf}" | wc -l)"

      if [ ${cf_count} -ne 1 ]; then
        fail_nl "More than one possible Retype configuration files found. Please remove extra \
files or specify the desired path with the 'config' argument \
(https://github.com/retypeapp/action-build#specify-path-to-the-retypeyml-file). See \
output for the list of paths found. Configuration files located: 
${locate_cf}"
      else
        echo "${locate_cf}, "
        cmdargs+=("${locate_cf:1}")
      fi
    fi
  fi
fi

# Check if destdir has a value and append it to cmdargs
if [ -n "${destdir}" ]; then
  cmdargs+=("--output" "${destdir}")
fi

if [ ! -z "${INPUT_KEY}" ]; then
  cmdargs+=("--key" "${INPUT_KEY}")
elif [ ! -z "${INPUT_SECRET}" ]; then
  # For backward compatibility
  cmdargs+=("--key" "${INPUT_SECRET}")
fi

if [ ! -z "${INPUT_PASSWORD}" ]; then
  cmdargs+=("--password" "${INPUT_PASSWORD}")
fi

if [ "${INPUT_STRICT}" == "true" ]; then
  cmdargs+=("--strict")
fi

if [ ! -z "${INPUT_OVERRIDE}" ]; then
  cmdargs+=("--override" "${INPUT_OVERRIDE}")
fi

if [ "${INPUT_VERBOSE}" == "true" ]; then
  cmdargs+=("--verbose")
fi

# Create the initial command with mandatory parts
cmdln=("retype" "build")

# Only append cmdargs if it is not empty
if [ ${#cmdargs[@]} -gt 0 ]; then
  cmdln+=("${cmdargs[@]}")  # Append all elements of cmdargs to cmdln
fi

result="$("${cmdln[@]}" 2>&1)" || \
  fail_cmd true "Retype build command failed with exit code ${retstat}" "${cmdln[*]}" "${result}"

if [ ! -e "${destdir}/resources/js/config.js" ]; then
  fail_nl "Retype output not found after building."
fi

echo "::group::Retype build command: ${cmdln[@]}
${result}
::endgroup::"

if ${missing_retypecf}; then
  result="$(rm "retype.yml" 2>&1)" || \
    fail_cmd true "Unable to remove default retype.yml placed into repo root" "rm \"retype.yml\"" "${result}"
fi

if [ "${config_output}" != "${destdir}" ]; then
  echo -n " (${config_output})"
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
echo -n "Cleaning up repository: git-reset"

result="$(git reset HEAD -- . 2>&1)" || \
  fail_cmd comma "Unable to git-reset repository back to HEAD after Retype build." "git checkout -- ." "${result}"

echo -n ", git-checkout"
result="$(git checkout -- . 2>&1)" || \
  fail_cmd comma "Unable to git-checkout repository afresh after Retype build." "git checkout -- ." "${result}"

echo -n ", git-clean"
result="$(git clean -d -x -q -f 2>&1)" || \
  fail_cmd comma "Unable to clean up repository after Retype build." "git clean -d -x -q -f" "${result}"

echo ", done
Retype build completed successfully"