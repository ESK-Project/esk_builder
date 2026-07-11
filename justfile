set shell := ["bash", "-euo", "pipefail", "-c"]

alias b := build
alias f := fmt
alias g := generic
alias x := plato

default:
    @just --list

fmt:
    git ls-files -z '*.sh' | xargs -0r shfmt -w -i 4 -ci -bn -sr

fmt-check:
    git ls-files -z '*.sh' | xargs -0r shfmt -d -i 4 -ci -bn -sr

bash-check:
    git ls-files -z '*.sh' | xargs -0r bash -n

lint:
    git ls-files -z '*.sh' | xargs -0r shellcheck -x

py-lint:
    cd py && uv run ruff check src pyproject.toml

py-check:
    cd py && uv run python -m basedpyright src

check: fmt-check bash-check lint py-lint py-check

build *args:
    env {{args}} ./build.sh

plato *args:
    env BUILD_TARGET=plato {{args}} ./build.sh

generic *args:
    env BUILD_TARGET=generic {{args}} ./build.sh

clean:
    rm -rf out work staged boot_image build.log github.json
