# shellcheck shell=bash

stop_telegram() {
    if [[ -n ${TG_BOT_API_URL:-} ]]; then
        curl -fsS --max-time 30 -X POST "$TG_BOT_API_URL/bot$TG_BOT_TOKEN/logOut" > /dev/null \
            || echo "::warning::Could not log out of the local Telegram Bot API."
    fi
    if [[ -n ${telegram_pid:-} ]]; then
        kill "$telegram_pid" 2> /dev/null || true
        wait "$telegram_pid" 2> /dev/null || true
    fi
    rm -rf -- "$telegram_dir"
}

# Ref: https://github.com/NextAlone/NagramActionRelated/blob/main/channel-publish/action.yml
start_telegram() {
    if [[ -z $TG_BOT_TOKEN || -z $TG_CHAT_ID || -z $TELEGRAM_API_ID || -z $TELEGRAM_API_HASH ]]; then
        echo "Set TG_BOT_TOKEN, TG_CHAT_ID, TELEGRAM_API_ID and TELEGRAM_API_HASH to enable Telegram."
        return 1
    fi

    telegram_dir="$(mktemp -d "$RUNNER_TEMP/telegram-bot-api.XXXXXX")" || return 1
    trap stop_telegram EXIT

    local asset url=http://127.0.0.1:8081 attempt
    local release=https://api.github.com/repos/NextAlone/NagramActionRelated/releases/latest
    asset="$(GH_TOKEN="$GITHUB_TOKEN" uv run --locked --no-dev esk release asset-url \
        telegram-bot-api-linux-x86_64 --api-url "$release")" || return 1
    curl -fsSLo "$telegram_dir/telegram-bot-api" --retry 3 "$asset" || return 1
    chmod +x "$telegram_dir/telegram-bot-api" || return 1
    "$telegram_dir/telegram-bot-api" --local --http-ip-address=127.0.0.1 --http-port=8081 \
        --dir="$telegram_dir" > /dev/null 2>&1 &
    telegram_pid=$!

    for attempt in {1..30}; do
        if curl --silent --max-time 1 --output /dev/null "$url/"; then
            export TG_BOT_API_URL="$url"
            return 0
        fi
        if [[ $attempt == 30 ]] || ! kill -0 "$telegram_pid" 2> /dev/null; then
            echo "The local Telegram Bot API server did not start."
            return 1
        fi
        sleep 1
    done
}
