#!/bin/bash

set -o errexit
set -o nounset

case $OSTYPE in
darwin*) SED=gsed;;
*) SED=sed;;
esac

release_date="$(date +%Y-%m-%d)"

verify_args() {
  echo "Cutting a release for version $version with commit $commit"
  while true; do
    read -rp "Is this correct (y/n)?" yn
    case $yn in
    [Yy]*) break;;
    [Nn]*) exit;;
    *) echo "Please answer y or n.";;
    esac
  done
}

update_version() {
  echo "$version" > VERSION
  echo "VERSION set to $version"
}

update_changelog() {
  # cut out empty "Fixed", "Added", or "Changed" sections
  remove_empty_sections

  local match="## \[unreleased\] \- unreleased"
  local heading="## [$version] - $release_date"
  $SED -i "/$match/c $heading" CHANGELOG.md
}

remove_empty_sections() {
  local unreleased_section
  unreleased_section="$($SED -n "/## \[unreleased\] - unreleased/,/## \[/p" < CHANGELOG.md)"
  if [[ "$unreleased_section" != "" ]]; then
    for section in "Fixed" "Added" "Changed"; do
      local section_text
      local first
      section_text="$(echo "$unreleased_section" | $SED -n "/### $section/{:a;n;/##/b;p;ba}")"
      first="$(echo "$section_text" | $SED "/^\s*$/d" | cut -c 1)"
      if [[ "$first" == "" ]]; then
        echo "Removing empty CHANGELOG section: $section"
        local line_num
        line_num="$(grep -n -m1 "$section" CHANGELOG.md | cut -d : -f 1)"
        $SED -i "$line_num{N;N;d}" CHANGELOG.md
      fi
    done
  fi
}

add_changelog_unreleased_section() {
  echo "Adding unreleased section to CHANGELOG"
  local replace='## [unreleased] - unreleased\n\n### Fixed\n\n\n### Added\n\n\n### Changed\n\n\n'
  $SED -i "/## \[$version\] \- $release_date/i $replace" CHANGELOG.md
}

check_for_commit_and_push() {
  printf "Would you like to push CHANGELOG updates to master (y/n)? "
  while true; do
    read -r yn
    case $yn in
    [Yy]*) break;;
    [Nn]*) exit;;
    *) echo "Please answer y or n.";;
    esac
  done
}

if [ $# -le 2 ]; then
  echo "version and commit arguments required"
fi

set -eu
version=$1
commit=$2

verify_args

# create version release branch
git checkout master
git pull
if ! git diff --exit-code master origin/master
then
  echo "ERROR! There are local-only changes on branch 'master'!"
  exit 1
fi
git checkout -b "release-$version" "$commit"

# update VERSION and CHANGELOG
update_version
update_changelog

# commit VERSION and CHANGELOG updates
git add CHANGELOG.md VERSION
git commit -m "Prep for $version release

[skip ci]"

# merge into release
git checkout release
if ! git diff --exit-code release origin/release
then
  echo "ERROR! There are local-only changes on branch 'release'!"
  exit 1
fi
git merge "release-$version" -m "Release $version"

# tag release
git tag "$version"

# push to release branch
git push origin release
git push origin "$version"

# update CHANGELOG for new entries
git checkout master
git merge "release-$version"
add_changelog_unreleased_section

# check if user wants to continue
check_for_commit_and_push

# commit changelog and push to master
git add CHANGELOG.md
git commit -m "Add unreleased section to CHANGELOG post $version release prep

[skip ci]"
git push origin master
