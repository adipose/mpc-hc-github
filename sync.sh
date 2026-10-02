#!/usr/bin/env bash
# Daily sync for the GitHub-only copy of MPC-HC.
#
#   clsid2/mpc-hc develop     ->  <owner>/mpc-hc-github  branch develop
#   clsid2/LAVFilters @ pin   ->  <owner>/LAVFilters     branch github-submodules
#   gitea.1f0.de/LAV/<repo>   ->  <owner>/<repo>         every branch and tag
#
# A derived commit is upstream's own tree with the submodule URLs that point
# off GitHub rewritten to the copies above. Its parents are the previous
# derived commit and the upstream commit, so all of upstream's history stays
# reachable and the derived branches only ever move forward.
#
# The gitea repos are found from the pinned LAV commit's .gitmodules, so a new
# one is mirrored without editing this script.
set -euo pipefail

OWNER=${OWNER:-${GITHUB_REPOSITORY_OWNER:?set OWNER}}
# KEY_DIR holds one write deploy key per target repo, named after the repo.
# Without it, pushes go over HTTPS with whatever credentials git already has.
KEY_DIR=${KEY_DIR:-}
DRY=${DRY_RUN:-}

MPC_UPSTREAM=https://github.com/clsid2/mpc-hc.git
MPC_BRANCH=develop
LAV_UPSTREAM=https://github.com/clsid2/LAVFilters.git
LAV_PATH=src/thirdparty/LAVFilters/src
GITEA='https://gitea\.1f0\.de/LAV/([A-Za-z0-9_-]+)(\.git)?'

gh_url() { echo "https://github.com/$OWNER/$1.git"; }
fetch()  { git fetch -q --no-tags "$@"; }

# push REPO ARGS... - push to github.com/OWNER/REPO with that repo's own key.
push() {
    local repo=$1
    shift
    if [ -n "$DRY" ]; then echo "DRY RUN: push $repo $*"; return; fi
    if [ -z "$KEY_DIR" ]; then git push -q "$(gh_url "$repo")" "$@"; return; fi
    if [ ! -s "$KEY_DIR/$repo" ]; then
        echo "no deploy key for $repo: add one with write access and a DEPLOY_KEY_ secret" >&2
        exit 1
    fi
    GIT_SSH_COMMAND="ssh -i $KEY_DIR/$repo -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
        git push -q "git@github.com:$OWNER/$repo.git" "$@"
}

rm -rf work
git init -q work
cd work
git config user.name "mpc-hc-github sync"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# derive REPO BRANCH SOURCE SED [GITLINK_PATH GITLINK]
# Prints the derived commit for SOURCE. Reuses the branch tip when its tree is
# already what SOURCE produces, so an unchanged upstream makes no new commit.
derive() {
    local repo=$1 branch=$2 src=$3 sedexpr=$4 path=${5:-} link=${6:-} old tree blob
    old=$(git ls-remote "$(gh_url "$repo")" "refs/heads/$branch" | cut -f1)
    [ -n "$old" ] && fetch "$(gh_url "$repo")" "$old"
    export GIT_INDEX_FILE=$PWD/.git/derive-index
    rm -f "$GIT_INDEX_FILE"
    git read-tree "$src"
    blob=$(git cat-file blob "$src:.gitmodules" | sed -E "$sedexpr" | git hash-object -w --stdin)
    git update-index --cacheinfo "100644,$blob,.gitmodules"
    if [ -n "$path" ]; then git update-index --cacheinfo "160000,$link,$path"; fi
    tree=$(git write-tree)
    unset GIT_INDEX_FILE
    if [ -n "$old" ] && [ "$(git rev-parse "$old^{tree}")" = "$tree" ]; then
        echo "$old"
        return
    fi
    local parents=(-p "$src")
    [ -n "$old" ] && parents=(-p "$old" -p "$src")
    git commit-tree "$tree" "${parents[@]}" -m "Sync with upstream $(git rev-parse --short "$src")

Upstream's tree, with submodule URLs that point off GitHub rewritten to the
copies under github.com/$OWNER.

Source: $src"
}

# 1. Upstream MPC-HC, and the LAV Filters commit it pins.
fetch "$MPC_UPSTREAM" "$MPC_BRANCH"
U=$(git rev-parse FETCH_HEAD)
X=$(git ls-tree "$U" "$LAV_PATH" | awk '{print $3}')
[ -n "$X" ] || { echo "no LAV Filters gitlink at $LAV_PATH in $U" >&2; exit 1; }
fetch "$LAV_UPSTREAM" "$X"
echo "mpc-hc $MPC_BRANCH $U pins LAV Filters $X"

# 2. Mirror every gitea repo that commit uses, and check its pin is reachable.
lavmods=$PWD/.git/lav-gitmodules
git cat-file blob "$X:.gitmodules" > "$lavmods"
for name in $(git config --file "$lavmods" --name-only --get-regexp '^submodule\..*\.url$' | sed 's/^submodule\.//; s/\.url$//'); do
    url=$(git config --file "$lavmods" "submodule.$name.url")
    [[ $url =~ ^$GITEA$ ]] || continue
    repo=${BASH_REMATCH[1]}
    path=$(git config --file "$lavmods" "submodule.$name.path")
    pin=$(git ls-tree "$X" "$path" | awk '{print $3}')
    git fetch -q "$url" "+refs/heads/*:refs/mirror/$repo/heads/*" "+refs/tags/*:refs/mirror/$repo/tags/*"
    if [ -z "$(git for-each-ref --contains "$pin" "refs/mirror/$repo")" ]; then
        echo "$repo: pinned $pin is not on any gitea branch or tag" >&2
        exit 1
    fi
    push "$repo" --force --prune \
        "refs/mirror/$repo/heads/*:refs/heads/*" "refs/mirror/$repo/tags/*:refs/tags/*"
    echo "mirrored $repo (pin $pin)"
done

# 3. LAV Filters with the gitea URLs rewritten, then MPC-HC pointing at it.
L=$(derive LAVFilters github-submodules "$X" "s#$GITEA#https://github.com/$OWNER/\1.git#g")
D=$(derive mpc-hc-github develop "$U" \
    "s#https://github\.com/clsid2/LAVFilters(\.git)?#https://github.com/$OWNER/LAVFilters.git#" \
    "$LAV_PATH" "$L")
push LAVFilters "$L:refs/heads/github-submodules"
push mpc-hc-github "$D:refs/heads/develop"
echo "LAVFilters github-submodules = $L"
echo "mpc-hc-github develop       = $D"
