#!/bin/bash

retype_version="3.6.0"

use_dotnet=false
_ifs="${IFS}"

if [ ! -e "${GITHUB_ACTION_PATH}/functions.inc.sh" ]; then
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Unable to locate functions.inc.sh file."
  exit 1
fi

source "${GITHUB_ACTION_PATH}"/functions.inc.sh || {
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

${abortbuildmsg}"
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

echo -n "Determining temporary target folder to place parsed documentation: "
# by letting it create the directory we can guarantee no other call of mktemp could reference
# the same path.
destdir="$(mktemp -d)"
echo "${destdir}"

echo -n "Setting up build arguments: "

# cf_path ensures path is converted in case we are running from windows
config_output="$(cf_path "${destdir}")" || fail_nl "unable to parse output path: ${destdir}"
cmdargs=(--verbose)
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
      result="$(retype init --verbose 2>&1)" || \
        fail_cmd comma "'retype init' command failed with exit code ${retstat}" "retype init --verbose" "${result}"
      echo ", show command output.
::warning::No Retype configuration file found, using default setting values.
::group::Command: retype init --verbose
${result}
::endgroup::"
      echo -n "Setting up build arguments: resume, "

    else
      cf_count="$(echo "${locate_cf}" | wc -l)"

      if [ ${cf_count} -ne 1 ]; then
       fail_nl "More than one possible Retype configuration files found. Please remove extra files or specify the desired path with the 'config' argument (https://github.com/retypeapp/action-build#specify-path-to-the-retypeyml-file). See output for the list of paths found.

Configuration files located:
${locate_cf}"
      else
        echo -n "${locate_cf}, "
        cmdargs+=("${locate_cf:1}")
      fi
    fi
  fi
fi

if [ ! -z "${INPUT_OVERRIDE_BASE}" ]; then
  echo -n "base, "
  overridestr="$(append_json "${overridestr}" "base" "${INPUT_OVERRIDE_BASE}")" || \
    fail_nl "Unable to append 'base' setting while building the 'retype build' argument list."
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

echo -n "Documentation built to: ${destdir}"
if [ "${config_output}" != "${destdir}" ]; then
  echo -n " (${config_output})"
fi
echo "" # break line after the message above is done being composed.

# This makes the output path available via the
# 'steps.stepId.outputs.retype-output-path' reference, unique for the step.
echo "retype-output-path=${destdir}" >> "${GITHUB_OUTPUT}"

# This makes the output path available via the $RETYPE_OUTPUT_PATH that doesn't
# require referencing but is reset by the last ran build step if more than one
# are assigned to a job.
echo "RETYPE_OUTPUT_PATH=${destdir}" >> "${GITHUB_ENV}"

# perform a quick clean-up to remove temporary, untracked files
echo -n "Cleaning up repository: git-reset"

result="$(git reset HEAD -- . 2>&1)" || \
  fail_cmd comma "unable to git-reset repository back to HEAD after Retype build." "git checkout -- ." "${result}"

echo -n ", git-checkout"
result="$(git checkout -- . 2>&1)" || \
  fail_cmd comma "unable to git-checkout repository afresh after Retype build." "git checkout -- ." "${result}"

echo -n ", git-clean"
result="$(git clean -d -x -q -f 2>&1)" || \
  fail_cmd comma "unable to clean up repository after Retype build." "git clean -d -x -q -f" "${result}"

echo ", done.
Retype documentation build completed successfully."