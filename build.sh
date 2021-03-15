#!/bin/bash

retype_version="1.0.0"

use_dotnet=false
_ifs="${IFS}"

if [ ! -e "functions.inc.sh" ]; then
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Unable to locate functions.inc.sh file."
  exit 1
fi

source functions.inc.sh || {
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Error including functions.inc.sh."
  exit 1
}

# We prefer dotnet if available as the package size is (much) smaller.
if which dotnet > /dev/null 2>&1 && [ "$(dotnet --version | cut -f1 -d.)" == "5" ]; then
  use_dotnet=true
elif ! which node > /dev/null 2>&1 || [ "$(node --version | cut -f1 -d. | cut -b2-)" -lt 14 ]; then
  fail "Can't find suitable dotnet or node installation to install retype package with."
fi

echo -n "Determining root for documentation in repository: "

if [ ! -z "${INPUT_INPUT_ROOT}" ]; then
  docsroot="${INPUT_INPUT_ROOT}"

  # remove any heading slashes to the root path
  while [ "${docsroot::1}" == "/" ]; do
    docsroot="${docsroot:1}"
  done

  if [ -z "${docroot}" ]; then
    fail_nl "Invalid documentation root directory: ${INPUT_INPUT_ROOT}"
  fi

  if [ ! -d "${docroot}" ]; then
    fail_nl "Input documentation root directory not found: ${docroot}"
  fi
else
  IFS=$'\n'
  markdown_files=($(find ./ -type f -name "*.md"))
  IFS="${_ifs}"

  if [ ${#markdown_files[@]} -eq 0 ]; then
    fail_nl "Unable to locate markdown documentation files."
  elif [ ${#markdown_files[@]} -eq 1 ]; then
    docsroot="${markdown_files[0]}"
    docsroot="${docsroot%/*}"
  else
    depth=1
    while [ ${depth} -lt 100 ]; do
      if [ $(IFS=$'\n'; echo "${markdown_files[*]}" | cut -f1-${depth} -d/ | sort -u | wc -l) -ne 1 ]; then
        docsroot="$(echo "${markdown_files[0]}" | cut -f1-$(( 10#${depth} - 1 )) -d/)"
        break
      fi
      depth=$(( 10#${depth} + 1 ))
    done

    # point to root if failed
    if [ -z "${docsroot}" ]; then
      docsroot="."
    fi
  fi
fi

echo "${docsroot}/"

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
config_input="$(cf_path "$(pwd)/${docsroot#./}")" || fail_nl "unable to parse input path: $(pwd)/${docsroot#./}"
config_output="$(cf_path "${destdir}/output")" || fail_nl "unable to parse output path: ${destdir}/output"

if [ -e retype.json ]; then
  echo -n "/retype.json"
  cp retype.json "${destdir}/retype.json"
  echo -n ", "
else
  cd "${destdir}"
  echo -n "initializing default retype.json"
  result="$(retype init --verbose 2>&1)" || \
    fail_cmd comma "'retype init' command failed with exit code ${retstat}" "retype init --verbose" "${result}"
  cd - > /dev/null 2>&1
fi

echo -n "update"
sedpat="s#(\"input\": *\")[^\"](\")#\1${config_input//#/\\#}\2#;
        s#(\"output\": *\")[^\"](\")#\1${config_output//#/\\#}\2#;"

if [ ! -z "${INPUT_OVERRIDE_BASE}" ]; then
  sedpat="${sedpat}
        s#(\"base\": *\")[^\"](\")#\1${INPUT_OVERRIDE_BASE//#/\\#}\2#;"
fi

if [ ! -z "${INPUT_PROJECT_NAME}" ]; then
  sedpat="${sedpat}
        s#(\"title\": *\")[^\"](\")#\1${INPUT_PROJECT_NAME//#/\\#}\2#;"
fi

inplace_sed "${sedpat}" "${destdir}/retype.json"

echo ", done."

echo -n "Building documentation: "
cd "${destdir}"
result="$(retype build --verbose 2>&1)" || \
  fail_cmd true "retype build command failed with exit code ${retstat}" "retype build --verbose" "${result}"

cd - > /dev/null 2>&1

echo -n "done.
Documentation built to: ${destdir}/output"
if [ "${config_output}" != "${destdir}/output" ]; then
  echo -n " (${config_output})"
fi

echo "::set-output name=retype-output-root::${destdir}"
echo "Retype documentation build completed successfully."