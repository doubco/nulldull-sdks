package nulldull

import (
	"context"
	"iter"
	"strconv"
)

func itoa(n int) string { return strconv.Itoa(n) }

// guard checks the key kind and workspace ID before any Memory or Locale request.
type guard struct {
	workspaceID string
	public      bool
}

func (g guard) root() (string, error) {
	if g.public {
		return "", clientError(CodePrivateKeyRequired, "Memory and Locale need a private key (nd_sec_…) with the matching scope.", nil)
	}
	if g.workspaceID == "" {
		return "", clientError(CodeWorkspaceRequired, "Memory and Locale need a workspace ID (WithWorkspaceID): a key cannot look up its own workspace.", nil)
	}
	return "/api/platform/workspaces/" + escape(g.workspaceID), nil
}

// MemoryService reads Memory (scope memory:read). It needs a private key
// and a workspace ID.
type MemoryService struct {
	t     *transport
	guard guard
}

// CursorParams picks a page of a list.
type CursorParams struct {
	// After is a cursor from NextCursor.
	After string
}

// ListFoldersParams filters MemoryService.ListFolders and IterateFolders.
type ListFoldersParams struct {
	ScopeID string
	// ParentID lists the folders under this folder. Leave it and Root unset
	// for every readable folder.
	ParentID string
	// Root lists top-level folders (sends parentId=root).
	Root  bool
	After string
}

// ListDocumentsParams filters MemoryService.ListDocuments and IterateDocuments.
type ListDocumentsParams struct {
	ScopeID string
	// FolderID lists documents in this folder. Leave it and Root unset for
	// every folder.
	FolderID string
	// Root lists unfiled documents at the location root (sends folderId=root).
	Root bool
	// Tags must all be present on a document (sent as repeated tag=).
	Tags      []string
	Kind      FileKind
	Lifecycle FileLifecycle
	After     string
}

// SearchParams filters MemoryService.Search and IterateSearch.
type SearchParams struct {
	// ScopeID limits the search to this location and its descendants.
	ScopeID   string
	Tags      []string
	Kind      FileKind
	Lifecycle FileLifecycle
	After     string
}

// ListTagsParams filters MemoryService.ListTags and IterateTags.
type ListTagsParams struct {
	ScopeID string
	// Q is a substring of the tag, up to 48 characters.
	Q     string
	After string
}

// ListAssetsParams filters MemoryService.ListAssets and IterateAssets.
type ListAssetsParams struct {
	ScopeID string
	// FolderID lists assets in this folder. Leave it and Root unset for every folder.
	FolderID string
	// Root lists unfiled assets at the location root (sends folderId=root).
	Root bool
	// Q is a substring of name, description or tags, up to 160 characters.
	Q     string
	Tags  []string
	After string
}

// GetAssetParams configures MemoryService.GetAsset.
type GetAssetParams struct {
	// RevisionID picks an immutable version instead of the current one.
	RevisionID string
}

// DownloadAssetParams configures MemoryService.DownloadAsset.
type DownloadAssetParams struct {
	RevisionID string
	// Preview serves images inline (preview=true). Implied by Width.
	Preview bool
	// Width asks for a resized WebP preview of PNG, JPEG, WebP and AVIF
	// images, in pixels (the server snaps up to 64…2048). 0 means the original.
	Width int
}

func folderFilter(id string, root bool, name string) (string, error) {
	if root {
		if id != "" && id != "root" {
			return "", invalidArgument("Set either " + name + " or Root, not both.")
		}
		return "root", nil
	}
	return id, nil
}

func addTags(q *query, tags []string) {
	for _, tag := range tags {
		q.set("tag", tag)
	}
}

func requireID(value, name string) error {
	if value == "" {
		return invalidArgument(name + " must be a non-empty string.")
	}
	return nil
}

func (s *MemoryService) get(ctx context.Context, path string, q query, out any) error {
	root, err := s.guard.root()
	if err != nil {
		return err
	}
	return s.t.getJSON(ctx, root+path, q, out)
}

func getPage[T any](ctx context.Context, s *MemoryService, path string, q query) (*Page[T], error) {
	var page Page[T]
	if err := s.get(ctx, path, q, &page); err != nil {
		return nil, err
	}
	return &page, nil
}

func pageItems[T any](page *Page[T], err error) ([]T, *string, error) {
	if err != nil {
		return nil, nil, err
	}
	return page.Items, page.NextCursor, nil
}

func cursor(params *CursorParams) CursorParams {
	if params == nil {
		return CursorParams{}
	}
	return *params
}

// ListScopes returns one page of the locations the key's member can see
// (workspace root, customer products, projects).
func (s *MemoryService) ListScopes(ctx context.Context, params *CursorParams) (*Page[Scope], error) {
	p := cursor(params)
	var q query
	q.opt("after", p.After)
	return getPage[Scope](ctx, s, "/scopes", q)
}

// IterateScopes yields every visible location across all pages.
func (s *MemoryService) IterateScopes(ctx context.Context, params *CursorParams) iter.Seq2[Scope, error] {
	p := cursor(params)
	return paginate(p.After, func(after string) ([]Scope, *string, error) {
		return pageItems(s.ListScopes(ctx, &CursorParams{After: after}))
	})
}

// ListFolders returns one page of readable folders, optionally in one
// location or under one parent.
func (s *MemoryService) ListFolders(ctx context.Context, params *ListFoldersParams) (*FolderList, error) {
	p := ListFoldersParams{}
	if params != nil {
		p = *params
	}
	parent, err := folderFilter(p.ParentID, p.Root, "ParentID")
	if err != nil {
		return nil, err
	}
	var q query
	q.opt("scopeId", p.ScopeID)
	q.opt("parentId", parent)
	q.opt("after", p.After)
	var list FolderList
	if err := s.get(ctx, "/folders", q, &list); err != nil {
		return nil, err
	}
	return &list, nil
}

// IterateFolders yields every matching folder across all pages.
func (s *MemoryService) IterateFolders(ctx context.Context, params *ListFoldersParams) iter.Seq2[FolderSummary, error] {
	p := ListFoldersParams{}
	if params != nil {
		p = *params
	}
	return paginate(p.After, func(after string) ([]FolderSummary, *string, error) {
		p.After = after
		list, err := s.ListFolders(ctx, &p)
		if err != nil {
			return nil, nil, err
		}
		return list.Items, list.NextCursor, nil
	})
}

// GetFolder returns a folder with its ancestors and effective placement. A
// missing or unreadable folder answers 403 FORBIDDEN.
func (s *MemoryService) GetFolder(ctx context.Context, folderID string) (*Folder, error) {
	if err := requireID(folderID, "folderId"); err != nil {
		return nil, err
	}
	var folder Folder
	if err := s.get(ctx, "/folders/"+escape(folderID), nil, &folder); err != nil {
		return nil, err
	}
	return &folder, nil
}

func documentsQuery(p ListDocumentsParams) (query, error) {
	folder, err := folderFilter(p.FolderID, p.Root, "FolderID")
	if err != nil {
		return nil, err
	}
	var q query
	q.opt("scopeId", p.ScopeID)
	q.opt("folderId", folder)
	addTags(&q, p.Tags)
	q.opt("kind", string(p.Kind))
	q.opt("lifecycle", string(p.Lifecycle))
	q.opt("after", p.After)
	return q, nil
}

// ListDocuments returns one page of readable documents, without content.
func (s *MemoryService) ListDocuments(ctx context.Context, params *ListDocumentsParams) (*Page[DocumentSummary], error) {
	p := ListDocumentsParams{}
	if params != nil {
		p = *params
	}
	q, err := documentsQuery(p)
	if err != nil {
		return nil, err
	}
	return getPage[DocumentSummary](ctx, s, "/documents", q)
}

// IterateDocuments yields every matching document across all pages.
func (s *MemoryService) IterateDocuments(ctx context.Context, params *ListDocumentsParams) iter.Seq2[DocumentSummary, error] {
	p := ListDocumentsParams{}
	if params != nil {
		p = *params
	}
	return paginate(p.After, func(after string) ([]DocumentSummary, *string, error) {
		p.After = after
		return pageItems(s.ListDocuments(ctx, &p))
	})
}

// GetDocument returns a document with its saved Markdown Content. A missing
// or unreadable document answers 403 FORBIDDEN.
func (s *MemoryService) GetDocument(ctx context.Context, documentID string) (*Document, error) {
	if err := requireID(documentID, "documentId"); err != nil {
		return nil, err
	}
	var document Document
	if err := s.get(ctx, "/documents/"+escape(documentID), nil, &document); err != nil {
		return nil, err
	}
	return &document, nil
}

// ResolveLink resolves a relative Markdown link inside a document to another
// readable document.
func (s *MemoryService) ResolveLink(ctx context.Context, documentID, href string) (*LinkResolution, error) {
	if err := requireID(documentID, "documentId"); err != nil {
		return nil, err
	}
	var q query
	q.set("href", href)
	var resolution LinkResolution
	if err := s.get(ctx, "/documents/"+escape(documentID)+"/resolve-link", q, &resolution); err != nil {
		return nil, err
	}
	return &resolution, nil
}

func searchQuery(q string, p SearchParams) query {
	var out query
	out.set("q", q)
	out.opt("scopeId", p.ScopeID)
	addTags(&out, p.Tags)
	out.opt("kind", string(p.Kind))
	out.opt("lifecycle", string(p.Lifecycle))
	out.opt("after", p.After)
	return out
}

// Search returns one page of documents whose name, content or tags contain
// q (2–160 characters, case-insensitive). Shorter queries get 400 INVALID_INPUT.
func (s *MemoryService) Search(ctx context.Context, q string, params *SearchParams) (*Page[SearchResult], error) {
	p := SearchParams{}
	if params != nil {
		p = *params
	}
	return getPage[SearchResult](ctx, s, "/search", searchQuery(q, p))
}

// IterateSearch yields every search result across all pages.
func (s *MemoryService) IterateSearch(ctx context.Context, q string, params *SearchParams) iter.Seq2[SearchResult, error] {
	p := SearchParams{}
	if params != nil {
		p = *params
	}
	return paginate(p.After, func(after string) ([]SearchResult, *string, error) {
		p.After = after
		return pageItems(s.Search(ctx, q, &p))
	})
}

// ListTags returns one page of tags on readable documents with their
// counts, most used first.
func (s *MemoryService) ListTags(ctx context.Context, params *ListTagsParams) (*Page[TagCount], error) {
	p := ListTagsParams{}
	if params != nil {
		p = *params
	}
	var q query
	q.opt("scopeId", p.ScopeID)
	q.opt("q", p.Q)
	q.opt("after", p.After)
	return getPage[TagCount](ctx, s, "/tags", q)
}

// IterateTags yields every tag across all pages.
func (s *MemoryService) IterateTags(ctx context.Context, params *ListTagsParams) iter.Seq2[TagCount, error] {
	p := ListTagsParams{}
	if params != nil {
		p = *params
	}
	return paginate(p.After, func(after string) ([]TagCount, *string, error) {
		p.After = after
		return pageItems(s.ListTags(ctx, &p))
	})
}

// ListAssets returns one page of readable Memory assets with metadata.
func (s *MemoryService) ListAssets(ctx context.Context, params *ListAssetsParams) (*Page[Asset], error) {
	p := ListAssetsParams{}
	if params != nil {
		p = *params
	}
	folder, err := folderFilter(p.FolderID, p.Root, "FolderID")
	if err != nil {
		return nil, err
	}
	var q query
	q.opt("scopeId", p.ScopeID)
	q.opt("folderId", folder)
	q.opt("q", p.Q)
	addTags(&q, p.Tags)
	q.opt("after", p.After)
	return getPage[Asset](ctx, s, "/assets", q)
}

// IterateAssets yields every matching asset across all pages.
func (s *MemoryService) IterateAssets(ctx context.Context, params *ListAssetsParams) iter.Seq2[Asset, error] {
	p := ListAssetsParams{}
	if params != nil {
		p = *params
	}
	return paginate(p.After, func(after string) ([]Asset, *string, error) {
		p.After = after
		return pageItems(s.ListAssets(ctx, &p))
	})
}

// GetAsset returns an asset's metadata and current object (filename, media
// type, SHA-256), or a specific version with RevisionID.
func (s *MemoryService) GetAsset(ctx context.Context, assetID string, params *GetAssetParams) (*Asset, error) {
	if err := requireID(assetID, "assetId"); err != nil {
		return nil, err
	}
	var q query
	if params != nil {
		q.opt("revisionId", params.RevisionID)
	}
	var asset Asset
	if err := s.get(ctx, "/assets/"+escape(assetID), q, &asset); err != nil {
		return nil, err
	}
	return &asset, nil
}

// ListAssetVersions returns one page of an asset's immutable versions,
// newest first.
func (s *MemoryService) ListAssetVersions(ctx context.Context, assetID string, params *CursorParams) (*Page[AssetVersion], error) {
	if err := requireID(assetID, "assetId"); err != nil {
		return nil, err
	}
	var q query
	q.opt("after", cursor(params).After)
	return getPage[AssetVersion](ctx, s, "/assets/"+escape(assetID)+"/versions", q)
}

// IterateAssetVersions yields every version of an asset, newest first.
func (s *MemoryService) IterateAssetVersions(ctx context.Context, assetID string, params *CursorParams) iter.Seq2[AssetVersion, error] {
	return paginate(cursor(params).After, func(after string) ([]AssetVersion, *string, error) {
		return pageItems(s.ListAssetVersions(ctx, assetID, &CursorParams{After: after}))
	})
}

// DownloadAsset downloads an asset's bytes, or a resized WebP preview with
// Width. Originals are served as application/octet-stream; the real media
// type is in Asset.Object.MediaType.
func (s *MemoryService) DownloadAsset(ctx context.Context, assetID string, params *DownloadAssetParams) (*Download, error) {
	p := DownloadAssetParams{}
	if params != nil {
		p = *params
	}
	if p.Width < 0 {
		return nil, invalidArgument("width must be a positive whole number of pixels.")
	}
	if err := requireID(assetID, "assetId"); err != nil {
		return nil, err
	}
	root, err := s.guard.root()
	if err != nil {
		return nil, err
	}
	// Never send submissionId: keys are refused when it is present.
	var q query
	q.opt("revisionId", p.RevisionID)
	if p.Preview || p.Width > 0 {
		q.set("preview", "true")
	}
	if p.Width > 0 {
		q.set("w", itoa(p.Width))
	}
	return s.t.download(ctx, s.t.baseURL+root+"/assets/"+escape(assetID)+"/download"+q.encode(), true)
}
