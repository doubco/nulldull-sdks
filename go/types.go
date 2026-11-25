package nulldull

import "encoding/json"

// Response types mirror the API's JSON objects (SPEC.md section 9). Field
// names on the wire are unchanged. Fields the SDK does not know yet are kept
// in each type's Extra and written back by MarshalJSON. Enum-like string
// types accept values that are not listed as constants.
//
// Pointer fields are null or missing in the API response when nil. Times are
// Unix epoch milliseconds.

// ---------------------------------------------------------------- Grid

// GridAssetRef is a publication-pinned asset of a Grid page.
type GridAssetRef struct {
	ID string `json:"id"`
	// Version is the publication-pinned asset version.
	Version int `json:"version"`
	// URL is absolute after normalization by GridService.AssetURL.
	URL       string `json:"url"`
	Filename  string `json:"filename"`
	MediaType string `json:"mediaType"`
	ByteSize  int64  `json:"byteSize"`
	// Checksum is the SHA-256 of the file, hex.
	Checksum string `json:"checksum"`
	Extra    Extra  `json:"-"`
}

// GridCover is a page's cover image.
type GridCover struct {
	ID        string `json:"id"`
	Version   int    `json:"version"`
	URL       string `json:"url"`
	Filename  string `json:"filename"`
	MediaType string `json:"mediaType"`
	ByteSize  int64  `json:"byteSize"`
	Checksum  string `json:"checksum"`
	// Alt is the alternative text; "" means decorative.
	Alt   string `json:"alt"`
	Extra Extra  `json:"-"`
}

// GridPageSummary is a published page in a list, without its document.
type GridPageSummary struct {
	ID      string `json:"id"`
	Pool    string `json:"pool"`
	Slug    string `json:"slug"`
	Locale  string `json:"locale"`
	Title   string `json:"title"`
	Summary string `json:"summary"`
	// Version is the publication's own version.
	Version int `json:"version"`
	// SourceVersion is the saved editor version that was published.
	SourceVersion int   `json:"sourceVersion"`
	PublishedAt   int64 `json:"publishedAt"`
	// FolderID is the direct parent folder at publication; older snapshots may omit it.
	FolderID *string    `json:"folderId,omitempty"`
	Cover    *GridCover `json:"cover,omitempty"`
	Extra    Extra      `json:"-"`
}

// GridPageTarget contains a readable target's current publication coordinates.
type GridPageTarget struct {
	EntryID   string `json:"entryId"`
	Published bool   `json:"published"`
	Pool      string `json:"pool"`
	Slug      string `json:"slug"`
	Locale    string `json:"locale"`
	Extra     Extra  `json:"-"`
}

// GridPage is a published page with its document and asset manifest.
type GridPage struct {
	ID            string     `json:"id"`
	Pool          string     `json:"pool"`
	Slug          string     `json:"slug"`
	Locale        string     `json:"locale"`
	Title         string     `json:"title"`
	Summary       string     `json:"summary"`
	Version       int        `json:"version"`
	SourceVersion int        `json:"sourceVersion"`
	PublishedAt   int64      `json:"publishedAt"`
	FolderID      *string    `json:"folderId,omitempty"`
	Cover         *GridCover `json:"cover,omitempty"`
	// Document is the published Grid document as raw JSON. Its schema belongs
	// to @nulldull/grid-core; the SDK does not validate or render it.
	Document json.RawMessage `json:"document"`
	Assets   []GridAssetRef  `json:"assets"`
	Extra    Extra           `json:"-"`
}

// PageTargets decodes this document's current target bindings from Extra.
// The returned map is a snapshot. Missing or malformed bindings return nil.
func (p GridPage) PageTargets() map[string]GridPageTarget {
	raw := p.Extra["pageTargets"]
	if len(raw) == 0 {
		return nil
	}
	var targets map[string]GridPageTarget
	if err := json.Unmarshal(raw, &targets); err != nil {
		return nil
	}
	return targets
}

// PageTarget looks up a single document-local alias.
func (p GridPage) PageTarget(alias string) (GridPageTarget, bool) {
	target, ok := p.PageTargets()[alias]
	return target, ok
}

// GridPool identifies the pool of a page list.
type GridPool struct {
	Key   string `json:"key"`
	Name  string `json:"name"`
	Extra Extra  `json:"-"`
}

// GridPageList is one page of a pool's published pages.
type GridPageList struct {
	Pool  GridPool          `json:"pool"`
	Items []GridPageSummary `json:"items"`
	// NextCursor is nil on the last page; otherwise pass it back as After.
	NextCursor *string `json:"nextCursor"`
	Extra      Extra   `json:"-"`
}

// ---------------------------------------------------------------- Memory

// LocationKind is the kind of a Memory location.
type LocationKind string

// Known location kinds.
const (
	LocationWorkspace       LocationKind = "workspace"
	LocationCustomerProduct LocationKind = "customer-product"
	LocationProject         LocationKind = "project"
)

// FileKind is a document's kind label.
type FileKind string

// Known file kinds.
const (
	KindRules     FileKind = "rules"
	KindTasks     FileKind = "tasks"
	KindPlan      FileKind = "plan"
	KindReference FileKind = "reference"
	KindProcedure FileKind = "procedure"
	KindNotes     FileKind = "notes"
	KindUnknown   FileKind = "unknown"
)

// FileLifecycle is a document's lifecycle label.
type FileLifecycle string

// Known file lifecycles.
const (
	LifecycleMaintained FileLifecycle = "maintained"
	LifecycleOneTime    FileLifecycle = "one-time"
	LifecycleUnknown    FileLifecycle = "unknown"
)

// FileRole is "senior" or "junior".
type FileRole string

// Scope is a Memory location: the workspace root, a customer product or a project.
type Scope struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Kind        LocationKind `json:"kind"`
	ParentID    *string      `json:"parentId"`
	IconKind    *string      `json:"iconKind,omitempty"`
	IconValue   *string      `json:"iconValue,omitempty"`
	IconVersion *int         `json:"iconVersion,omitempty"`
	Extra       Extra        `json:"-"`
}

// LocationPathItem is one level of a location path, root first.
type LocationPathItem = Scope

// Placement is where a file or folder maps to in a repository.
type Placement struct {
	Repository *string `json:"repository"`
	Path       string  `json:"path"`
	// FolderPath is folder names joined with "/"; "" at the location root.
	FolderPath string `json:"folderPath"`
	Extra      Extra  `json:"-"`
}

// FolderRef is a folder's ID and name.
type FolderRef struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Extra Extra  `json:"-"`
}

// FolderSummary is a folder in a list.
type FolderSummary struct {
	WorkspaceID         string    `json:"workspaceId"`
	ID                  string    `json:"id"`
	ScopeID             string    `json:"scopeId"`
	ParentID            *string   `json:"parentId"`
	Name                string    `json:"name"`
	CreatedBy           string    `json:"createdBy"`
	PreferredRepository *string   `json:"preferredRepository"`
	PreferredPath       *string   `json:"preferredPath"`
	MetadataVersion     int       `json:"metadataVersion"`
	FolderCount         int       `json:"folderCount"`
	DocumentCount       int       `json:"documentCount"`
	AssetCount          int       `json:"assetCount"`
	SecretCount         int       `json:"secretCount"`
	Placement           Placement `json:"placement"`
	Extra               Extra     `json:"-"`
}

// FolderCounts counts the items directly at a location level.
type FolderCounts struct {
	Folders   int   `json:"folders"`
	Documents int   `json:"documents"`
	Assets    int   `json:"assets"`
	Secrets   int   `json:"secrets"`
	Extra     Extra `json:"-"`
}

// FolderList is one page of folders.
type FolderList struct {
	Items      []FolderSummary `json:"items"`
	NextCursor *string         `json:"nextCursor"`
	// Here is only on the first page when both ScopeID and a parent filter were given.
	Here  *FolderCounts `json:"here,omitempty"`
	Extra Extra         `json:"-"`
}

// Folder is a folder with its ancestors and effective placement.
type Folder struct {
	WorkspaceID         string      `json:"workspaceId"`
	ID                  string      `json:"id"`
	ScopeID             string      `json:"scopeId"`
	ParentID            *string     `json:"parentId"`
	Name                string      `json:"name"`
	CreatedBy           string      `json:"createdBy"`
	PreferredRepository *string     `json:"preferredRepository"`
	PreferredPath       *string     `json:"preferredPath"`
	MetadataVersion     int         `json:"metadataVersion"`
	CanManage           bool        `json:"canManage"`
	CanDelete           bool        `json:"canDelete"`
	Placement           Placement   `json:"placement"`
	Ancestors           []FolderRef `json:"ancestors"`
	// Contents is "empty", "visible" or "hidden".
	Contents string `json:"contents"`
	Extra    Extra  `json:"-"`
}

// DocumentSummary is a document (Markdown file) without its content.
type DocumentSummary struct {
	ID                  string         `json:"id"`
	Name                string         `json:"name"`
	ScopeID             string         `json:"scopeId"`
	FolderID            *string        `json:"folderId"`
	HeadRevisionID      *string        `json:"headRevisionId"`
	PreferredRepository *string        `json:"preferredRepository"`
	PreferredPath       *string        `json:"preferredPath"`
	MetadataVersion     int            `json:"metadataVersion"`
	Role                FileRole       `json:"role"`
	Tags                []string       `json:"tags"`
	LabelKind           *FileKind      `json:"labelKind"`
	LabelLifecycle      *FileLifecycle `json:"labelLifecycle"`
	// LabelSource is "ai", "manual" or nil.
	LabelSource *string `json:"labelSource"`
	// LabelStatus is "ready", "pending", "failed" or "unclassified".
	LabelStatus string `json:"labelStatus"`
	Extra       Extra  `json:"-"`
}

// Document is a document with its saved Markdown content.
type Document struct {
	ID                  string         `json:"id"`
	Name                string         `json:"name"`
	ScopeID             string         `json:"scopeId"`
	FolderID            *string        `json:"folderId"`
	HeadRevisionID      *string        `json:"headRevisionId"`
	PreferredRepository *string        `json:"preferredRepository"`
	PreferredPath       *string        `json:"preferredPath"`
	MetadataVersion     int            `json:"metadataVersion"`
	Role                FileRole       `json:"role"`
	Tags                []string       `json:"tags"`
	LabelKind           *FileKind      `json:"labelKind"`
	LabelLifecycle      *FileLifecycle `json:"labelLifecycle"`
	LabelSource         *string        `json:"labelSource"`
	LabelStatus         string         `json:"labelStatus"`
	HeadAuthorMemberID  *string        `json:"headAuthorMemberId"`
	// Content is the saved Markdown (up to 128 KiB), or nil before the first save.
	Content      *string            `json:"content"`
	ContentHash  *string            `json:"contentHash"`
	Placement    Placement          `json:"placement"`
	LocationPath []LocationPathItem `json:"locationPath"`
	Extra        Extra              `json:"-"`
}

// SearchResult is a document matching a search.
type SearchResult struct {
	ID              string         `json:"id"`
	Name            string         `json:"name"`
	ScopeID         string         `json:"scopeId"`
	FolderID        *string        `json:"folderId"`
	HeadRevisionID  *string        `json:"headRevisionId"`
	MetadataVersion int            `json:"metadataVersion"`
	Role            FileRole       `json:"role"`
	Tags            []string       `json:"tags"`
	LabelKind       *FileKind      `json:"labelKind"`
	LabelLifecycle  *FileLifecycle `json:"labelLifecycle"`
	LabelSource     *string        `json:"labelSource"`
	LabelStatus     string         `json:"labelStatus"`
	// Excerpt is up to 240 characters around the match.
	Excerpt      string             `json:"excerpt"`
	LocationPath []LocationPathItem `json:"locationPath"`
	FolderPath   string             `json:"folderPath"`
	Extra        Extra              `json:"-"`
}

// TagCount is a tag and how many readable documents carry it.
type TagCount struct {
	Tag   string `json:"tag"`
	Count int    `json:"count"`
	Extra Extra  `json:"-"`
}

// LinkResolution is the result of MemoryService.ResolveLink. Status is
// "found" (with ID and Fragment), "unavailable" or "ambiguous".
type LinkResolution struct {
	Status   string `json:"status"`
	ID       string `json:"id,omitempty"`
	Fragment string `json:"fragment,omitempty"`
	Extra    Extra  `json:"-"`
}

// AssetObject is the stored file of an asset version.
type AssetObject struct {
	ID             string `json:"id"`
	Filename       string `json:"filename"`
	MediaType      string `json:"mediaType"`
	ByteSize       int64  `json:"byteSize"`
	Checksum       string `json:"checksum"`
	AuthorMemberID string `json:"authorMemberId"`
	CreatedAt      int64  `json:"createdAt"`
	Extra          Extra  `json:"-"`
}

// Asset is a Memory asset with its metadata.
type Asset struct {
	ID              string      `json:"id"`
	Name            string      `json:"name"`
	ScopeID         string      `json:"scopeId"`
	Kind            string      `json:"kind"`
	FolderID        *string     `json:"folderId"`
	FolderPath      []FolderRef `json:"folderPath"`
	HeadRevisionID  *string     `json:"headRevisionId"`
	RevisionID      *string     `json:"revisionId"`
	MetadataVersion int         `json:"metadataVersion"`
	Role            FileRole    `json:"role"`
	// Description is usage guidance written by people.
	Description string   `json:"description"`
	Tags        []string `json:"tags"`
	TagSource   string   `json:"tagSource"`
	Summary     *string  `json:"summary"`
	// InsightStatus is "ready", "pending", "failed", "unavailable" or a newer value.
	InsightStatus string `json:"insightStatus"`
	// Object is nil until a first version is uploaded.
	Object       *AssetObject       `json:"object"`
	LocationPath []LocationPathItem `json:"locationPath"`
	Extra        Extra              `json:"-"`
}

// AssetVersion is an immutable asset version.
type AssetVersion struct {
	ID             string `json:"id"`
	CreatedAt      int64  `json:"createdAt"`
	AuthorMemberID string `json:"authorMemberId"`
	Extra          Extra  `json:"-"`
}

// ---------------------------------------------------------------- Locale

// LocaleKeyStatus is a Locale key status used to filter exports.
type LocaleKeyStatus string

// Known Locale key statuses.
const (
	StatusDraft       LocaleKeyStatus = "draft"
	StatusNeedsReview LocaleKeyStatus = "needs_review"
	StatusApproved    LocaleKeyStatus = "approved"
)

// Known Locale export format IDs. Format IDs are plain strings; others are
// sent as given.
const (
	FormatJSON         = "json"
	FormatWorld        = "world"
	FormatWorldCLDR    = "world-cldr"
	FormatXCStrings    = "xcstrings"
	FormatAppleStrings = "apple-strings"
	FormatAndroidXML   = "android-xml"
)

// LocaleCapabilities describes what an export format can represent.
type LocaleCapabilities struct {
	// Layout is "single" (one file set per language) or "multi" (one file for every language).
	Layout        string `json:"layout"`
	Plurals       string `json:"plurals"`
	Variables     string `json:"variables"`
	Status        bool   `json:"status"`
	Description   bool   `json:"description"`
	VariableTypes bool   `json:"variableTypes"`
	Extra         Extra  `json:"-"`
}

// LocaleFormatFile is one file role of an export format.
type LocaleFormatFile struct {
	Role        string `json:"role"`
	Extension   string `json:"extension"`
	ContentType string `json:"contentType"`
	Required    bool   `json:"required"`
	Extra       Extra  `json:"-"`
}

// LocaleFormat is an export format with its capabilities.
type LocaleFormat struct {
	ID           string             `json:"id"`
	Label        string             `json:"label"`
	Capabilities LocaleCapabilities `json:"capabilities"`
	Files        []LocaleFormatFile `json:"files"`
	Extra        Extra              `json:"-"`
}

// LocaleFormatList lists the export formats.
type LocaleFormatList struct {
	Items []LocaleFormat `json:"items"`
	Extra Extra          `json:"-"`
}

// LocaleFile is one exported text file.
type LocaleFile struct {
	// Path is relative, such as "en.json" or "values-tr/strings.xml".
	Path        string `json:"path"`
	ContentType string `json:"contentType"`
	// Content is UTF-8 text.
	Content string `json:"content"`
	Extra   Extra  `json:"-"`
}

// LocaleExportNote reports something an export format could not represent.
type LocaleExportNote struct {
	Code     string  `json:"code"`
	Key      string  `json:"key"`
	Language *string `json:"language,omitempty"`
	Extra    Extra   `json:"-"`
}

// LocaleExport is an exported catalog. It is always JSON with text files,
// never an archive.
type LocaleExport struct {
	Format         string             `json:"format"`
	Files          []LocaleFile       `json:"files"`
	Notes          []LocaleExportNote `json:"notes"`
	ContentVersion int64              `json:"contentVersion"`
	Extra          Extra              `json:"-"`
}

// ---------------------------------------------------------------- Shared

// Page is one page of a list. Pass NextCursor back as After until it is nil.
type Page[T any] struct {
	Items      []T     `json:"items"`
	NextCursor *string `json:"nextCursor"`
	Extra      Extra   `json:"-"`
}

type pageFields[T any] struct {
	Items      []T     `json:"items"`
	NextCursor *string `json:"nextCursor"`
}

// UnmarshalJSON keeps unknown fields in Extra.
func (p *Page[T]) UnmarshalJSON(data []byte) error {
	var fields pageFields[T]
	if err := decodeObject(data, &fields, &p.Extra); err != nil {
		return err
	}
	p.Items, p.NextCursor = fields.Items, fields.NextCursor
	return nil
}

// MarshalJSON writes the known fields and Extra.
func (p Page[T]) MarshalJSON() ([]byte, error) {
	return encodeObject(pageFields[T]{Items: p.Items, NextCursor: p.NextCursor}, p.Extra)
}

// Download is a downloaded file.
type Download struct {
	// Bytes is the whole body.
	Bytes []byte
	// ContentType is the Content-Type header, or "". Memory downloads that are
	// not previews are application/octet-stream; see Asset.Object.MediaType.
	ContentType string
	// Filename comes from Content-Disposition, or "" (resized previews have none).
	Filename string
	// Size is len(Bytes).
	Size int
}
