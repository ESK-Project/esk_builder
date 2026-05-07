set shell := ["bash", "-euo", "pipefail", "-c"]

alias b := build
alias f := fmt
alias gd := git-diff
alias gl := git-log
alias gs := git-status
alias gsh := git-show

default:
    @just --list

fmt:
    find . -type f -name '*.sh' -print0 | xargs -0r shfmt -w -i 4 -ci -bn -sr

fmt-check:
    find . -type f -name '*.sh' -print0 | xargs -0r shfmt -d -i 4 -ci -bn -sr

lint:
    find . -type f -name '*.sh' -print0 | xargs -0r shellcheck -x

check: fmt-check lint

git-status:
    git status --short --branch

git-diff *args:
    git diff {{args}}

git-log limit="20":
    git log --oneline --decorate --graph -n {{limit}}

git-show ref="HEAD":
    git show --stat --patch {{ref}}

build *args:
    env {{args}} bash ./build.sh

clean:
    rm -rf out work build.log github.json
