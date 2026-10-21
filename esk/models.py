from pydantic import BaseModel, ConfigDict, Field


class GitHubReleaseAsset(BaseModel):
    model_config = ConfigDict(extra="ignore")

    name: str
    browser_download_url: str


class GitHubRelease(BaseModel):
    model_config = ConfigDict(extra="ignore")

    tag_name: str | None = None
    assets: list[GitHubReleaseAsset] = Field(default_factory=list)


class MetadataPayload(BaseModel):
    target: str
    preset: str
    kernel_version: str
    kernel_name: str
    kernel_commit: str
    kernel_url: str
    builder_commit: str
    toolchain: str
    package_name: str
    variant: str
    ksu_commit: str | None
    susfs_commit: str | None
    features: dict[str, bool]
    compile_seconds: int
    artifacts: dict[str, str]


class TelegramResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    ok: bool
    description: str | None = None


class TelegramMessageRequest(BaseModel):
    chat_id: str
    parse_mode: str = "MarkdownV2"
    disable_web_page_preview: str = "true"
    text: str


class TelegramDocumentRequest(BaseModel):
    chat_id: str
    parse_mode: str = "MarkdownV2"
    disable_web_page_preview: str = "true"
    caption: str
