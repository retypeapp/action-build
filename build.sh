#!/bin/bash

retype_version="1.1.0"

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

# We prefer dotnet if available as the package size is (much) smaller.
if which dotnet > /dev/null 2>&1 && [ "$(dotnet --version | cut -f1 -d.)" == "5" ]; then
  use_dotnet=true
elif ! which node > /dev/null 2>&1 || [ "$(node --version | cut -f1 -d. | cut -b2-)" -lt 14 ]; then
  fail "Can't find suitable dotnet or node installation to install retype package with."
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
    echo -n "NPM package manager: "

    cmdln=(npm install --global "retypeapp@${retype_version}")
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

echo -n "Setting up configuration file: "

# cf_path ensures path is converted in case we are running from windows
config_output="$(cf_path "${destdir}/output")" || fail_nl "unable to parse output path: ${destdir}/output"
sedpat="s#(\"output\": *\")[^\"]+(\")#\1${config_output//#/\\#}\2#;"

if [ -e retype.json ]; then
  existing_retypejson=true
  echo -n "/retype.json"
  cp retype.json "${destdir}/retype.json"
  echo -n ", "
else
  existing_retypejson=false
  cd "${destdir}"
  echo -n "initializing default retype.json"
  result="$(retype init --verbose 2>&1)" || \
    fail_cmd comma "'retype init' command failed with exit code ${retstat}" "retype init --verbose" "${result}"

  cd - > /dev/null 2>&1
fi

echo -n "update"

if [ ! -z "${INPUT_OVERRIDE_BASE}" ]; then
  sedpat="${sedpat}
        s#(\"base\": *\")[^\"]+(\")#\1${INPUT_OVERRIDE_BASE//#/\\#}\2#;"
fi

if [ ! -z "${INPUT_PROJECT_NAME}" ]; then
  sedpat="${sedpat}
        s#(\"title\": *\")[^\"]+(\")#\1${INPUT_PROJECT_NAME//#/\\#}\2#;"
elif ! ${existing_retypejson}; then
  sedpat="${sedpat}
        s#(\"title\": *\")[^\"]+(\")#\1${GITHUB_REPOSITORY##*/}\2#;"
fi

inplace_sed "${sedpat}" "${destdir}/retype.json"

echo ", done."

echo -n "Building documentation: "
result="$(cp "${destdir}/retype.json" . 2>&1)" || \
  fail_cmd true "unable to deploy adjusted retype.json file to repo root" "cp \"${destdir}/retype.json\"" "${result}"

result="$(retype build "retype.json" --verbose 2>&1)" || \
  fail_cmd true "retype build command failed with exit code ${retstat}" "retype build \"${destdir}/retype.json\" --verbose" "${result}"

if ${existing_retypejson}; then
  result="$(git checkout -- "retype.json" 2>&1)" || {
    echo "::warning::Unable to revert temporary changes to retype.json in the repository. This may affect next steps relying in the git state."
  }
else
  # we may safely ignore if this errors, which is unlikely to happen.
  result="$(rm retype.json 2>&1)"
fi

echo -n "done.
Documentation built to: ${destdir}/output"
if [ "${config_output}" != "${destdir}/output" ]; then
  echo -n " (${config_output})"
fi
echo "" # break line after the message above is done being composed.

echo "::set-output name=retype-output-root::${destdir}"
echo "RETYPE_OUTPUT_ROOT=${destdir}" >> "${GITHUB_ENV}"

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