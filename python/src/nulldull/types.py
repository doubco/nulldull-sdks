"""Response types (SPEC.md section 9).

Every response is the API's JSON object, returned as a plain ``dict`` with the API's own camelCase
keys. These ``TypedDict`` definitions describe the known fields for type checkers; new fields can
appear at any time and are kept. Enum-like fields are typed as ``str`` because the API may add
values. Times are Unix epoch milliseconds.
"""

from __future__ import annotations

import builtins
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, TypedDict

__all__ = [
    "Asset",
    "AssetObject",
    "AssetPage",
    "AssetVersion",
    "AssetVersionPage",
    "Document",
    "DocumentPage",
    "DocumentSummary",
    "Download",
    "Folder",
    "FolderAncestor",
    "FolderCounts",
    "FolderList",
    "FolderSummary",
    "GridAssetRef",
    "GridCover",
    "GridDocument",
    "GridPage",
    "GridPageList",
    "GridPageSummary",
    "GridPageTarget",
    "GridPool",
    "LinkResolution",
    "LocaleExport",
    "LocaleExportNote",
    "LocaleFile",
    "LocaleFormat",
    "LocaleFormatCapabilities",
    "LocaleFormatFile",
    "LocaleFormatList",
    "LocationPathItem",
    "Placement",
    "Scope",
    "ScopePage",
    "SearchPage",
    "SearchResult",
    "TagCount",
    "TagPage",
]

JSONObject = Dict[str, Any]

# --------------------------------------------------------------------------- Grid


class GridAssetRef(TypedDict):
    id: str
    version: int
    """Publication-pinned asset version."""
    url: str
    """Absolute URL, normalized by ``grid.asset_url``."""
    filename: str
    mediaType: str
    byteSize: int
    checksum: str
    """SHA-256, hex."""


class GridCover(GridAssetRef):
    alt: str
    """Alternative text; empty means decorative."""


class _GridPageSummaryBase(TypedDict):
    id: str
    pool: str
    slug: str
    locale: str
    title: str
    summary: str
    version: int
    """The publication's own version."""
    sourceVersion: int
    """The saved editor version that was published."""
    publishedAt: int


class GridPageSummary(_GridPageSummaryBase, total=False):
    folderId: Optional[str]
    cover: Optional[GridCover]


class _GridDocumentBase(TypedDict):
    layout: JSONObject
    breakpoints: List[JSONObject]
    nodes: List[JSONObject]


class GridDocument(_GridDocumentBase, total=False):
    """The published Grid document. Its full schema belongs to ``@nulldull/grid-core``; treat it as opaque JSON."""

    baseLayoutIndex: int
    baseLayoutName: str


class GridPageTarget(TypedDict):
    entryId: str
    published: bool
    pool: str
    slug: str
    locale: str


class _GridPageLinks(TypedDict, total=False):
    pageTargets: Dict[str, GridPageTarget]


class GridPage(GridPageSummary, _GridPageLinks):
    document: GridDocument
    assets: List[GridAssetRef]


class GridPool(TypedDict):
    key: str
    name: str


class GridPageList(TypedDict):
    pool: GridPool
    items: List[GridPageSummary]
    nextCursor: Optional[str]


# --------------------------------------------------------------------------- Memory


class _LocationIcon(TypedDict, total=False):
    iconKind: Optional[str]
    iconValue: Optional[str]
    iconVersion: int


class Scope(_LocationIcon):
    id: str
    name: str
    kind: str
    """``workspace``, ``customer-product`` or ``project``."""
    parentId: Optional[str]


LocationPathItem = Scope


class Placement(TypedDict):
    repository: Optional[str]
    path: str
    folderPath: str


class _FolderBase(TypedDict):
    workspaceId: str
    id: str
    scopeId: str
    parentId: Optional[str]
    name: str
    createdBy: str
    preferredRepository: Optional[str]
    preferredPath: Optional[str]
    metadataVersion: int


class FolderSummary(_FolderBase):
    folderCount: int
    documentCount: int
    assetCount: int
    secretCount: int
    placement: Placement


class FolderCounts(TypedDict):
    folders: int
    documents: int
    assets: int
    secrets: int


class _FolderListBase(TypedDict):
    items: List[FolderSummary]
    nextCursor: Optional[str]


class FolderList(_FolderListBase, total=False):
    here: FolderCounts
    """Only on the first page when both ``scope_id`` and ``parent_id`` were given."""


class FolderAncestor(TypedDict):
    id: str
    name: str


class Folder(_FolderBase):
    canManage: bool
    canDelete: bool
    placement: Placement
    ancestors: List[FolderAncestor]
    contents: str
    """``empty``, ``visible`` or ``hidden``."""


class _FileLabels(TypedDict):
    tags: List[str]
    labelKind: Optional[str]
    labelLifecycle: Optional[str]
    labelSource: Optional[str]
    labelStatus: str


class DocumentSummary(_FileLabels):
    id: str
    name: str
    scopeId: str
    folderId: Optional[str]
    headRevisionId: Optional[str]
    preferredRepository: Optional[str]
    preferredPath: Optional[str]
    metadataVersion: int
    role: str


class Document(DocumentSummary):
    headAuthorMemberId: Optional[str]
    content: Optional[str]
    """Markdown, up to 128 KiB."""
    contentHash: Optional[str]
    placement: Placement
    locationPath: List[LocationPathItem]


class SearchResult(_FileLabels):
    id: str
    name: str
    scopeId: str
    folderId: Optional[str]
    headRevisionId: Optional[str]
    metadataVersion: int
    role: str
    excerpt: str
    locationPath: List[LocationPathItem]
    folderPath: str


class TagCount(TypedDict):
    tag: str
    count: int


class _LinkResolutionBase(TypedDict):
    status: str
    """``found``, ``unavailable`` or ``ambiguous``."""


class LinkResolution(_LinkResolutionBase, total=False):
    id: str
    fragment: str


class AssetObject(TypedDict):
    id: str
    filename: str
    mediaType: str
    byteSize: int
    checksum: str
    authorMemberId: str
    createdAt: int


class Asset(TypedDict):
    id: str
    name: str
    scopeId: str
    kind: str
    folderId: Optional[str]
    folderPath: List[FolderAncestor]
    headRevisionId: Optional[str]
    revisionId: Optional[str]
    metadataVersion: int
    role: str
    description: str
    tags: List[str]
    tagSource: str
    summary: Optional[str]
    insightStatus: str
    object: Optional[AssetObject]
    """``None`` before the first upload."""
    locationPath: List[LocationPathItem]


class AssetVersion(TypedDict):
    id: str
    createdAt: int
    authorMemberId: str


class ScopePage(TypedDict):
    items: List[Scope]
    nextCursor: Optional[str]


class DocumentPage(TypedDict):
    items: List[DocumentSummary]
    nextCursor: Optional[str]


class SearchPage(TypedDict):
    items: List[SearchResult]
    nextCursor: Optional[str]


class TagPage(TypedDict):
    items: List[TagCount]
    nextCursor: Optional[str]


class AssetPage(TypedDict):
    items: List[Asset]
    nextCursor: Optional[str]


class AssetVersionPage(TypedDict):
    items: List[AssetVersion]
    nextCursor: Optional[str]


# --------------------------------------------------------------------------- Locale


class LocaleFormatCapabilities(TypedDict):
    layout: str
    """``single`` or ``multi``."""
    plurals: str
    variables: str
    status: bool
    description: bool
    variableTypes: bool


class LocaleFormatFile(TypedDict):
    role: str
    extension: str
    contentType: str
    required: bool


class LocaleFormat(TypedDict):
    id: str
    label: str
    capabilities: LocaleFormatCapabilities
    files: List[LocaleFormatFile]


class LocaleFormatList(TypedDict):
    items: List[LocaleFormat]


class LocaleFile(TypedDict):
    path: str
    """Relative path, may contain ``/``."""
    contentType: str
    content: str
    """UTF-8 text."""


class _LocaleExportNoteBase(TypedDict):
    code: str
    key: str


class LocaleExportNote(_LocaleExportNoteBase, total=False):
    language: str


class LocaleExport(TypedDict):
    format: str
    files: List[LocaleFile]
    notes: List[LocaleExportNote]
    contentVersion: int


# --------------------------------------------------------------------------- Download


@dataclass(frozen=True)
class Download:
    """A downloaded file."""

    bytes: builtins.bytes
    """The whole body."""
    content_type: Optional[str]
    """The ``Content-Type`` header."""
    filename: Optional[str]
    """From ``Content-Disposition`` (RFC 5987 ``filename*`` first), else ``None``."""
    size: int
    """The byte length of ``bytes``."""
