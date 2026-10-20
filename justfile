set shell := ["bash", "-euo", "pipefail", "-c"]

alias b := build
alias f := fmt

default:
    @just --list

fmt:
    git ls-files -z '*.sh' | xargs -0r shfmt -w -i 4 -ci -bn -sr

fmt-check:
    git ls-files -z '*.sh' | xargs -0r shfmt -d -i 4 -ci -bn -sr

bash-check:
    git ls-files -z '*.sh' | xargs -0r -n1 bash -n

lint:
    git ls-files -z '*.sh' | xargs -0r shellcheck -x

py-lint:
    uv run --locked ruff check esk tests pyproject.toml

py-check:
    uv run --locked python -m basedpyright esk

test:
    uv run --locked python -m unittest discover -s tests -v

check: fmt-check bash-check lint py-lint py-check test

[positional-arguments]
build *args:
    uv run esk build "$@"

[positional-arguments]
clean *args:
    uv run esk clean "$@"
