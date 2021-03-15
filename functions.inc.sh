abortbuildmsg="Aborting documentation build process."

if [ "${OSTYPE}" == "msys" ]; then
  MSYS_TMPDIR="$(mount | egrep "^[^ ]+ on /tmp type" | cut -f1 -d" ")"

  if [ -z "${MSYS_TMPDIR}" ]; then
    fail "unable to query MSYS mounted /tmp/ directory. Current mtab:
$(mount)
----

${abortbuildmsg}"
  fi

  function cf_path() {
    local linuxpath="${@}"
    local drivepath

    if [ "${linuxpath::1}" != "/" ]; then
      #relative path
      echo "${linuxpath}"
      return 0
    else
      drivepath="${linuxpath::3}"
      if [ -z "${drivepath/\/[a-zA-Z]\/}" ]; then
        echo "${drivepath:1:1}:${linuxpath#/?}"
        return 0
      elif [ "${linuxpath::5}" == "/tmp/" ]; then
        echo "${MSYS_TMPDIR}/${linuxpath#/*/}"
      else
        # could be a network drive, something we don't support or suppose will ever
        # be used as absolute path under windows.
        return 1
      fi
    fi
  }
else
  function cf_path() {
    echo "${@}"
    return 0
  }
fi

function fail() {
  local msg="${@}"

  >&2 echo "::error::${msg}"
  exit 1
}

function fail_nl() {
  local msg="${@}"

  echo "error."
  fail "${msg}"
}

function fail_cmd() {
  local nl="${1}" msg="${2}" cmd="${3}" output="${4}"
  local multiline_msg

  multiline_msg="${msg}.
Failed command and output:

\$ ${cmd}

${output}
----

${abortbuildmsg}"

  if [ "${nl}" == comma ]; then
    echo -n ", "
    fail_nl "${multiline_msg}"
  elif [ "${nl}" == true ]; then
    fail_nl "${multiline_msg}"
  else
    fail "${multiline_msg}"
  fi
}

if [ "${OSTYPE::6}" == "darwin" ]; then
  function inplace_sed() {
    sed -Ei '' "${@}"
  }
else
  function inplace_sed() {
    sed -Ei "${@}"
  }
fi