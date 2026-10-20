import fnmatch

from pydantic import ValidationError

from .common import die, get_json_text
from .models import GitHubRelease


def asset_url(data: GitHubRelease, pattern: str) -> str:
    matches = [asset for asset in data.assets if fnmatch.fnmatch(asset.name, pattern)]

    if not matches:
        die(f"No release asset found matching pattern: {pattern}")

    if len(matches) > 1:
        names = ", ".join(asset.name for asset in matches)
        die(f"Multiple release assets matched pattern {pattern}: {names}")

    return matches[0].browser_download_url


def asset_url_json(stdin_text: str, pattern: str) -> str:
    try:
        data = GitHubRelease.model_validate_json(stdin_text)
    except ValidationError as e:
        die(f"Invalid GitHub release JSON: {e}")

    return asset_url(data, pattern)


def asset_url_api(api_url: str, pattern: str) -> str:
    try:
        data = GitHubRelease.model_validate_json(get_json_text(api_url))
    except ValidationError as e:
        die(f"GitHub release API did not return a valid release object: {e}")
    return asset_url(data, pattern)
