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
    ksu_commit: str | None = None
    susfs_commit: str | None = None
    features: dict[str, bool]
    compile_seconds: int
    artifacts: dict[str, str]


class PlannedBuild(BaseModel):
    target: str
    preset: str
    kernel_ref: str


class ReleaseBuild(BaseModel):
    target: str
    preset: str
    kernel_name: str
    kernel_version: str
    kernel_url: str
    kernel_commit: str
    builder_commit: str
    toolchain: str
    ksu_commit: str | None = None
    susfs_commit: str | None = None
    features: dict[str, bool]
    source_package: str
    release_package: str
    sha256: str


class ReleaseManifest(BaseModel):
    schema_version: int = 1
    version: str
    prerelease: bool = True
    builds: list[ReleaseBuild] = Field(min_length=1)
