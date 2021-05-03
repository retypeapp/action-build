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

echo "- Querying latest Retype release from nuget.org/packages/retypeapp..."
result="$(curl -si https://www.nuget.org/packages/retypeapp)" || \
 fail "Unable to fetch retype package page from nuget.org website."

if [ "$(echo "${result}" | head -n1 | cut -f2 -d" ")" != 200 ]; then
 httpstat="$(echo "${result}" | head -n1 | cut -f2 -d" ")"
 fail "HTTP response ${httpstat} received while trying to query latest Retype Release from NuGet."
fi

latest="$(echo "${result}" | egrep '\| retypeapp ' | sed -E "s/^.*\| retypeapp //" | head -n1 | strings)"

if [ -z "${latest}" ]; then
 fail "Unable to extract latest version number from NuGet website."
elif ! echo "${latest}" | egrep -q '^([0-9]+\.){2}[0-9]+$'; then
 fail "Invalid version number extracted from NuGet website: ${latest}"
fi

major="${latest%%.*}"
majorminor="${latest%.*}"
minor="${majorminor#*.}"
build="${latest##*.}"
latest_re="${latest//\./\\\.}"

echo " Version ${latest}."

echo "- Fetching tags..."
git fetch --tag || fail "Unable to fetch tags from origin."

echo "- Checking tags..."
overtags=()
if git tag | egrep -q "^v${latest_re}\$"; then
 overtags+=("v${latest}")
fi

if [ "${build}" == 0 ]; then
 if git tag | egrep -q "^v${majorminor}\$"; then
  overtags+=("v${majorminor}")
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
# four spaces are matched here because the return is an array with objects
varnames=(tag_name draft name id html_url)
IFS=$'\n'
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

echo "Setting git committer info."
git config user.name "New Release bot"
git config user.email "hello+retypeapp-action-build@object.net"

echo "Updating build.sh."
sed -Ei "s/^(retype_version=\")[^\"]+(\")\$/\1${latest}\2/" build.sh

if ! git status --porcelain | egrep "^ M build\.sh"; then
 # script is already updated to use latest retype version. Check if version tags points to this ref in history
 echo "The build.sh script is already up-to-date."
 echo "Checking whether tags points to current commit."
 currsha="$(git log -n1 --pretty='format:%H')"

 outdated_tags=()

 # there's a %(HEAD) format in git command to show an '*' if the major tag matches current checked out
 # ref, but it seems it does not work, so let's not rely on it
 if ! git tag --format='%(objectname)%(refname:strip=2)' | egrep -q "^${currsha}v${major}\$"; then
  outdated_tags+=(":v${major}")
 fi

 if [ ${build} -ne 0 ]; then
  if ! git tag --format='%(objectname)%(refname:strip=2)' | egrep -q "^${currsha}v${majorminor}\$"; then
   outdated_tags+=(":v${majorminor}")
  fi
 fi

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
else
 echo "Committing changes to build.sh."
 git add build.sh || fail "Unable to stage modified 'build.sh' script for commit."
 git commit -m "Updates Retype reference to version ${latest}." || fail "Unable to commit changes to 'build.sh' script."

 removetags=()
 if git tag | egrep -q "^v${major}\$"; then
  removetags=(":v${major}")
 fi
 if [ ${build} -ne 0 ]; then
  removetags+=(":v${majorminor}")
 fi

 echo "Pushing commit."
 git push origin HEAD

 if [ ${#removetags[@]} -gt 0 ]; then
   echo "Removing local and remote copies of outdated tags."
   git push origin "${removetags[@]}" || fail "Unable to remove one or more remote tags among: ${removetags[@]#:}"
   git tag -d "${removetags[@]#:}" || fail "Unable to remove one or more local tags among: ${removetags[@]#:}"
 fi

 echo "Creating '${major}', '${majorminor}' and '${latest}' tags."
 newtags=()
 for tag in ${major} ${majorminor} ${latest}; do
  git tag v${tag} || fail "Unable to create tag: v${tag}"
  newtags+=("v${tag}")
 done

 echo "Pushing tags."
 git push origin "${newtags[@]}"
fi

if ${found_rel}; then
 if ${republish}; then
  publishmsg="Re-publishing"
 else
  publishmsg="Publishing existing draft"
 fi
 publishmsg+=" release for v${major} tag: ${gh_rel[name]}"

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
  "body": "Retype Build GitHub Action release version '"${major}"'",
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