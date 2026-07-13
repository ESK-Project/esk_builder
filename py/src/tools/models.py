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
    kernel_version: str
    kernel_name: str
    toolchain: str
    package_name: str
    variant: str
    name: str
    out_dir: str
    release_repo: str
    release_branch: str
    kernel_commit: str


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


class TelegramMediaDocument(BaseModel):
    type: str = "document"
    media: str
    caption: str | None = None
    parse_mode: str | None = None


class TelegramMediaGroupRequest(BaseModel):
    chat_id: str
    media: list[TelegramMediaDocument]
