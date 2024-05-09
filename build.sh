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
    echo -n "dotnet tool"

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
    echo -n "NPM package manager (${plat})"

    cmdln=(npm install --global "retypeapp-${plat}@${retype_version}")
    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "unable to install retype using the NPM package manager" "${cmdln[@]}" "${result}"
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

echo ""

workflowdir="${WORKFLOW_RETYPE_DIR}"
echo "Workflow directory: ${workflowdir}"

subdir=""
if [ -n "${INPUT_SUBDIR}" ]; then
  # Remove leading slash, if present
  subdir="${INPUT_SUBDIR##/}"
  echo "Output subdirectory: ${subdir}"``
fi

# Construct the full destination directory path
if [ -n "${subdir}" ]; then
  destdir="${workflowdir}/${subdir}"
  # Create the full directory path with subdirectories
  mkdir -p "${destdir}"
else
  destdir="${workflowdir}"
fi

echo "Target subdirectory: ${destdir}"

echo -n "Setting up build arguments: "

if [ "${INPUT_VERBOSE}" == "true" ]; then
  echo -n "Enable verbose logging during build process"
  cmdargs=(--verbose)
fi

# cf_path ensures path is converted in case we are running from windows
config_output="$(cf_path "${destdir}")" || fail_nl "unable to parse output path: ${destdir}"

overridestr="$(append_json "" "output" "${config_output}")" || \
  fail_nl "Unable to append output path setting while building the 'retype build' argument list."

missing_retypecf=false

if [ ! -z "${INPUT_CONFIG_PATH}" ]; then
  # In case path is a directory and there's no Retype conf file, the process
  # is supposed to fail (we won't try 'retype init')
  echo -n "${INPUT_CONFIG_PATH}, "
  cmdargs+=("${INPUT_CONFIG_PATH}")
else
  if [ -e "retype.yml" ]; then
    echo -n "/retype.yml, "
  elif [ -e "retype.yaml" ]; then
    echo -n "/retype.yaml, "
  elif [ -e "retype.json" ]; then
    echo -n "/retype.json, "
  else
    echo -n "locate, "
    locate_cf="$(find ./ -mindepth 2 -maxdepth 3 -not -path "*/.*" -a \( -iname retype.yml -o -iname retype.yaml -o -iname retype.json \) | cut -b 2-)"

    if [ -z "${locate_cf}" ]; then
      missing_retypecf=true
      echo -n "initialize default configuration"

      # Initialize the command array
      cmdln=(retype init)

      # Add `--verbose` if `INPUT_VERBOSE` is set to "true"
      if [ "${INPUT_VERBOSE}" == "true" ]; then
        cmdln+=("--verbose")
      fi

      # Execute the command
      result="$("${cmdln[@]}" 2>&1)" || \
        fail_cmd comma "'retype init' command failed" "${cmdln[*]}" "${result}"

      echo ", show command output.
::warning::No Retype configuration file found, using default setting values.
::group::See result...
retype init --verbose
${result}
::endgroup::"
      echo -n "Setting up build arguments: resume, "

    else
      cf_count="$(echo "${locate_cf}" | wc -l)"

      if [ ${cf_count} -ne 1 ]; then
       fail_nl "More than one possible Retype configuration file was found. Please remove the extra file(s) or specify the desired path with the 'config' argument (https://github.com/retypeapp/action-build#specify-path-to-the-retypeyml-file). See output for the list of paths found.

Configuration files located:
${locate_cf}"
      else
        echo -n "${locate_cf}, "
        cmdargs+=("${locate_cf:1}")
      fi
    fi
  fi
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

echo ""
echo "Building documentation... "

cmdln=(retype build "${cmdargs[@]}")
result="$("${cmdln[@]}" 2>&1)" || \
  fail_cmd true "retype build command failed with exit code ${retstat}" "${cmdln[*]}" "${result}"

if [ ! -e "${destdir}/resources/js/config.js" ]; then
  fail_nl "Retype output not found after 'retype build' run. At least resources/js/config.js is missing from output."
fi

echo "::group::See result...
${cmdln[@]}

${result}
::endgroup::"

if ${missing_retypecf}; then
  result="$(rm "retype.yml" 2>&1)" || \
    fail_cmd true "unable to remove default retype.yml placed into repo root" "rm \"retype.yml\"" "${result}"
fi

if [ "${config_output}" != "${destdir}" ]; then
  echo " (${config_output})"
fi

# This makes the output path available via the
# 'steps.stepId.outputs.retype-output-path' reference, unique for the step.
echo "retype-output-path=${workflowdir}" >> "${GITHUB_OUTPUT}"

# This makes the output path available via the $RETYPE_OUTPUT_PATH that doesn't
# require referencing but is reset by the last ran build step if more than one
# are assigned to a job.
echo "RETYPE_OUTPUT_PATH=${workflowdir}" >> "${GITHUB_ENV}"

# perform a quick clean-up to remove temporary, untracked files
echo -n "Cleaning up repository with"

result="$(git reset HEAD -- . 2>&1)" || \
  fail_cmd comma "unable to git-reset repository back to HEAD after Retype build." "git reset HEAD -- ." "${result}"

echo -n " git-checkout"
result="$(git checkout -- . 2>&1)" || \
  fail_cmd comma "unable to git-checkout repository after Retype build." "git checkout -- ." "${result}"

echo -n " git-clean"
result="$(git clean -d -x -q -f 2>&1)" || \
  fail_cmd comma "unable to clean up repository after Retype build." "git clean -d -x -q -f" "${result}"

echo ""
echo "Retype build completed successfully"