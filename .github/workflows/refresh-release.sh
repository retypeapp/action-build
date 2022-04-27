#!/bin/bash

github_token=""

function fail() {
 >&2 echo "::error::${@}"
 exit 1
}

for param in "${@}"; do
 case "${param}" in
  '--github-token='*) github_token="${param#*=}";;
  *) fail "Unknown argument '${param}'.";;
 esac
done

if [ ${#github_token} -lt 10 ]; then
 fail "GitHub token (--github-token) is invalid."
fi

echo "- Querying latest Retype release from NuGet.org..."
result="$(curl -s https://api.nuget.org/v3/registration5-gz-semver2/retypeapp/index.json | gunzip)" || \
 fail "Unable to fetch retype package page from nuget.org website as a gzipped response."

# Wrap a node script to parse the response JSON string.
nodescp="const stdin = process.stdin;
let data='';
stdin.setEncoding('utf8');
stdin.on('data', function (chunk) {
 data += chunk;
});
stdin.on('end', function() {
 var objdata = JSON.parse(data);
 var pkmeta=objdata.items[0];
 console.log(pkmeta.items[pkmeta.items.length-1].catalogEntry.version);
});
stdin.on('error', console.error);"

latest="$(echo "${result}" | node -e "${nodescp}")" || fail "Unable parse latest version from NuGet API Json response."

if [ -z "${latest}" ]; then
 fail "Unable to extract latest version number from NuGet website."
elif ! echo "${latest}" | egrep -q '^([0-9]+\.){2}[0-9]+(-.*)?$'; then
 fail "Invalid version number extracted from NuGet website: ${latest}"
fi

if [[ "${latest}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
 major="${BASH_REMATCH[1]}"
 majorminor="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
 minor="${BASH_REMATCH[2]}"
 build="${BASH_REMATCH[3]}"
 ver_suffix="${BASH_REMATCH[4]}"
 latest_re="${latest//\./\\\.}"
else
 fail "Unsupported version format fetched from NuGet.org: ${latest}"
fi

echo -n " Version ${latest}"

prerelease=false
if [ ${#ver_suffix} -gt 0 ]; then
 echo " (prerelease)."
 prerelease=true
 taglist=(next)
else
 echo " (stable)."
 taglist=(latest "v${major}" "v${majorminor}")
fi

echo "- Fetching tags..."
git fetch --tag || fail "Unable to fetch tags from origin."

echo "- Checking tags..."
overtags=()
if git tag | egrep -q "^v${latest_re}\$"; then
 overtags+=("v${latest}")
fi

if ! ${prerelease}; then
 if [ "${build}" == 0 ]; then
  if git tag | egrep -q "^v${majorminor}\$"; then
   overtags+=("v${majorminor}")
  fi
 fi
fi

if [ ${#overtags[@]} -gt 0 ]; then
 failmsg="Tag"
 if [ ${#overtags[@]} -gt 1 ]; then
  failmsg+="s"
 fi
 pos=0
 beforelastpos=$(( 10#${#overtags[@]} - 2 ))
 for tag in "${overtags[@]}"; do
  failmsg+=" ${overtags[pos]}"
  if [ ${pos} -eq ${beforelastpos} ]; then
   failmsg+=" and"
  elif [ ${pos} -lt ${beforelastpos} ]; then
   failmsg+=","
  fi
  pos="$(( 10#${pos} + 1 ))"
 done

 failmsg+=" already exists. To release this version afresh, remove"
 if [ ${#overtags[@]} -gt 1 ]; then
  failmsg+=" them"
 else
  failmsg+=" it"
 fi
 failmsg+=" from GitHub and try again."

 fail "${failmsg}"
fi

# We also skip releases during pre-releases in this case, because in this repo, releases
# are only towards major tags, and we won't bump major tags on prerelease.
if ${prerelease}; then
 echo "Not checking GitHub Releases during pre-release (won't bump major tags)."
else
 echo "Querying releases."
 # FIXME: implement multi-page support
 releases_query="$(curl --silent --include \
  --header 'accept: application/vnd.github.v3+json' \
  --header 'authorization: Bearer '"${github_token}" \
  "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases" 2>&1)" || \
  fail "Unable to fetch list of releases. Curl command returned non-zero exit status."

 if [ "$(echo "${releases_query}" | head -n1 | cut -f2 -d" ")" != 200 ]; then
  fail "HTTP non-OK result status from releases query."
 fi

 _ifs="${IFS}"
 varnames=(tag_name draft name id html_url)
 IFS=$'\n'
 # four spaces are matched here because the return is an array with objects
 releases_data=($(echo "${releases_query}" | egrep "^    \"($(IFS='|'; echo "${varnames[*]}"))\": "))
 IFS="${_ifs}"
 found_rel=false
 republish=false
 declare -A var_read gh_rel
 for line in "${releases_data[@]}"; do
  var_name="${line%%\":*}"
  var_name="${var_name#*\"}"
  var_data="${line#*\": }"

  if [ "${var_data: -1}" == "," ]; then
   var_data="${var_data::-1}"
  fi
  if [ "${var_data::1}" == '"' ]; then
   var_data="${var_data:1:-1}"
  fi

  var_read[${var_name}]=true
  gh_rel[${var_name}]="${var_data}"

  all_read=true
  for var in "${varnames[@]}"; do
   if [ "${var_read[${var}]}" != "true" ]; then
    all_read=false
    break
   fi
  done

  if $all_read; then
   if [ "${gh_rel[tag_name]}" == "v${major}" ]; then
    found_rel=true
    if [ "${gh_rel[draft]}" == "false" ]; then
     republish=true
    fi
    break
   fi
   for var in "${varnames[@]}"; do
    var_read[${var}]=false
   done
  fi
 done

 if ${found_rel}; then
  if [ -z "${gh_rel[id]}" ]; then
   fail "Found release but GitHub release ID was not properly filled in."
  fi

  if ${republish}; then
   echo "Found active release '${gh_rel[name]}' for tag v${major}."
  else
   echo "Found draft release '${gh_rel[name]}' for tag v${major}."
  fi
  echo "Release URL: ${gh_rel[html_url]}"
 else
  echo "No current release for v${major} tag. Will create a new one."
 fi
fi

echo "Setting git committer info."
git config user.name "New Release bot"
git config user.email "hello+retypeapp-action-build@retype.com"

echo "Updating build.sh."
sed -Ei "s/^(retype_version=\")[^\"]+(\")\$/\1${latest}\2/" build.sh

if ! git status --porcelain | egrep "^ M build\.sh"; then
 # script is already updated to use latest retype version. Check if version tags points to this ref in history
 echo "The build.sh script is already up-to-date."
 echo "Checking whether tags points to current commit."
 currsha="$(git log -n1 --pretty='format:%H')"

 # there's a %(HEAD) format in git command to show an '*' if the major tag matches current checked out
 # ref, but it seems it does not work, so let's not rely on it
 existing_tags="$(git tag --format='%(objectname)%(refname:strip=2)')"

 outdated_tags=()
 for tag in "${taglist[@]}"; do
  if ! echo "${existing_tags}" | egrep -q "^${currsha}${tag//\./\\.}\$"; then
   outdated_tags+=(":${tag}")
  fi
 done

 if [ ${#outdated_tags[@]} -gt 0 ]; then
  echo "Removing local and remote copies of outdated tags."
  git push origin "${outdated_tags[@]}" || fail "Unable to remove one or more remote tags among: ${outdated_tags[@]#:}"
  git tag -d "${outdated_tags[@]#:}" || fail "Unable to delete one or more local tags among: ${outdated_tags[@]#:}"

  echo "Updating tags."
  for tag in "${outdated_tags[@]#:}"; do
   git tag "${tag}" || fail "Unable to create tag: ${tag}"
  done
 fi

 echo "Creating version tag (v${latest})."
 git tag "v${latest}" || fail "Unable to create tag: v${latest}"

 echo "Pushing tags."
 git push origin "${outdated_tags[@]#:}" "v${latest}" || fail "Unable to push new tags to GitHub."
else
 echo "Committing changes to build.sh."
 git add build.sh || fail "Unable to stage modified 'build.sh' script for commit."
 git commit -m "Updates Retype reference to version ${latest}." || fail "Unable to commit changes to 'build.sh' script."

 removetags=()

 for tag in "${taglist[@]}"; do
  if git tag | egrep -q "^${tag//\./\\.}\$"; then
   removetags+=(":${tag}")
  fi
 done

 echo "Pushing commit."
 git push origin HEAD || fail "Unable to push version changes to GitHub."

 if [ ${#removetags[@]} -gt 0 ]; then
   echo "Removing local and remote copies of outdated tags."
   git push origin "${removetags[@]}" || fail "Unable to remove one or more remote tags among: ${removetags[@]#:}"
   git tag -d "${removetags[@]#:}" || fail "Unable to remove one or more local tags among: ${removetags[@]#:}"
 fi

 echo "Creating tags: v${latest} ${taglist[@]}"
 newtags=()
 for tag in "${taglist[@]}" v${latest}; do
  git tag ${tag} || fail "Unable to create tag: ${tag}"
  newtags+=("${tag}")
 done

 echo "Pushing tags."
 git push origin "${newtags[@]}" || fail "Unable to push new tags to GitHub."
fi

if ! ${prerelease}; then
 if ${found_rel}; then
  if ${republish}; then
   publishmsg="Re-publishing"
  else
   publishmsg="Publishing existing draft"
  fi
  publishmsg+=" release for v${major} (latest) tag: ${gh_rel[name]}"

  # API endpoint docs
  # https://docs.github.com/en/rest/reference/repos#update-a-release (set "draft" to false)
  result="$(curl --silent --include --request PATCH \
   --header 'accept: application/vnd.github.v3+json' \
   --header 'authorization: Bearer '"${github_token}" \
   "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases/${gh_rel[id]}" \
   --data '{
   "tag_name": "v'"${major}"'",
   "draft": false,
   "prerelease": false
  }' 2>&1)" || \
  fail "Unable to create GitHub release. Curl command returned non-zero exit status."

  result_stat="$(echo "${result}" | head -n1 | cut -f2 -d" ")"

  if [ "${result_stat}" != 200 ]; then
   fail "Received HTTP response code ${result_stat} while 200 (ok) was expected."
  fi

  # two spaces are matched because response is a single object; thus one indent space
  release_url="$(echo "${result}" | egrep "^  \"html_url\": \"" | head -n1 | cut -f4 -d\")"

  if [ -z "${release_url}" ]; then
   fail "Unable to fetch updated release URL from GitHub response. We cannot tell the release was properly updated."
  fi

  echo "::warning::Release re-published, available at ${release_url}"
 else
  echo "Creating GitHub release v${major}."

  # API endpoint docs
  # https://docs.github.com/en/rest/reference/repos#create-a-release
  result="$(curl --silent --include --request POST \
   --header 'accept: application/vnd.github.v3+json' \
   --header 'authorization: Bearer '"${github_token}" \
   "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases" \
   --data '{
   "tag_name": "v'"${major}"'",
   "name": "Version '"${major}"'",
   "body": "Retype Build GitHub Action release version v'"${major}"'",
   "draft": false,
   "prerelease": false
  }' 2>&1)" || \
  fail "Unable to create GitHub release. Curl command returned non-zero exit status."

  result_stat="$(echo "${result}" | head -n1 | cut -f2 -d" ")"

  if [ "${result_stat}" != 201 ]; then
   fail "Received HTTP response code ${result_stat} while 201 (created) was expected."
  fi

  # two spaces are matched because response is a single object; thus one indent space
  release_url="$(echo "${result}" | egrep "^  \"html_url\": \"" | head -n1 | cut -f4 -d\")"

  if [ -z "${release_url}" ]; then
   fail "Unable to fetch release URL from GitHub response. We cannot tell the release was made."
  fi

  echo "::warning::Release created, available at ${release_url}"
 fi
else
 echo "::warning::No GitHub release is created during pre-releases."
fi