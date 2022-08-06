#! /usr/bin/env sh
set -eux

rm -rf public/
hugo

export GIT_INDEX_FILE=$(mktemp -u)
git add public/
TREE=$(git write-tree --prefix public/)
COMMIT=$(git commit-tree ${TREE} < /dev/null)
git branch -f gh-pages ${COMMIT}
