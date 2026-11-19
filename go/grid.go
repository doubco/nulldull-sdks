package nulldull

import (
	"context"
	"iter"
	"net/url"
	"regexp"
)

var (
	gridKeyPattern    = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)
	gridLocalePattern = regexp.MustCompile(`^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$`)
)

// GridService reads published Grid content (scope grid:published). It works
// with public and private keys and needs no workspace ID.
type GridService struct {
	t         *transport
	origin    *url.URL
	publicKey string
}

// ListPagesParams filters GridService.ListPages and IteratePages.
type ListPagesParams struct {
	// Locale is the content language, lowercase ("en", "pt-br"). Default "en".
	Locale string
	// Q is a literal search over titles and summaries, up to 160 characters.
	Q string
	// FolderID keeps pages whose direct parent folder at publication was this folder.
	FolderID string
	// Limit is the page size, 1–50. 0 uses the server default (20).
	Limit int
	// After is a cursor from NextCursor.
	After string
}

// GetPageParams configures GridService.GetPage.
type GetPageParams struct {
	// Locale is the content language. Default "en".
	Locale string
}

func gridKey(value, name string) error {
	if len(value) > 96 || !gridKeyPattern.MatchString(value) {
		return invalidArgument(name + " must be 1–96 lowercase letters, numbers and single hyphens.")
	}
	return nil
}

func gridLocale(value string) (string, error) {
	if value == "" {
		value = "en"
	}
	if len(value) > 35 || !gridLocalePattern.MatchString(value) {
		return "", invalidArgument("locale must be a lowercase language tag, such as en or pt-br.")
	}
	return value, nil
}

// ListPages returns one page of a pool's published pages, newest first.
// Cover URLs are made absolute with AssetURL.
func (s *GridService) ListPages(ctx context.Context, pool string, params *ListPagesParams) (*GridPageList, error) {
	if params == nil {
		params = &ListPagesParams{}
	}
	if err := gridKey(pool, "pool"); err != nil {
		return nil, err
	}
	if params.Limit < 0 || params.Limit > 50 {
		return nil, invalidArgument("limit must be a whole number from 1 to 50.")
	}
	locale, err := gridLocale(params.Locale)
	if err != nil {
		return nil, err
	}
	var q query
	q.set("locale", locale)
	q.opt("q", params.Q)
	q.opt("folderId", params.FolderID)
	if params.Limit > 0 {
		q.set("limit", itoa(params.Limit))
	}
	q.opt("after", params.After)
	var list GridPageList
	if err := s.t.getJSON(ctx, "/api/grid/v1/pools/"+escape(pool)+"/pages", q, &list); err != nil {
		return nil, err
	}
	for i := range list.Items {
		if err := s.normalizeCover(list.Items[i].Cover); err != nil {
			return nil, err
		}
	}
	return &list, nil
}

// IteratePages yields every published page across all result pages,
// starting at params.After. Requests are made lazily while ranging; stop
// early with break. An error is yielded once and ends the sequence.
func (s *GridService) IteratePages(ctx context.Context, pool string, params *ListPagesParams) iter.Seq2[GridPageSummary, error] {
	p := ListPagesParams{}
	if params != nil {
		p = *params
	}
	return paginate(p.After, func(after string) ([]GridPageSummary, *string, error) {
		p.After = after
		list, err := s.ListPages(ctx, pool, &p)
		if err != nil {
			return nil, nil, err
		}
		return list.Items, list.NextCursor, nil
	})
}

// GetPage returns a published page with its document and version-pinned
// asset manifest. Cover and asset URLs are made absolute with AssetURL.
func (s *GridService) GetPage(ctx context.Context, pool, slug string, params *GetPageParams) (*GridPage, error) {
	if params == nil {
		params = &GetPageParams{}
	}
	if err := gridKey(pool, "pool"); err != nil {
		return nil, err
	}
	if err := gridKey(slug, "slug"); err != nil {
		return nil, err
	}
	locale, err := gridLocale(params.Locale)
	if err != nil {
		return nil, err
	}
	var q query
	q.set("locale", locale)
	var page GridPage
	if err := s.t.getJSON(ctx, "/api/grid/v1/pools/"+escape(pool)+"/pages/"+escape(slug), q, &page); err != nil {
		return nil, err
	}
	if err := s.normalizeCover(page.Cover); err != nil {
		return nil, err
	}
	if page.Assets == nil {
		page.Assets = []GridAssetRef{}
	}
	for i := range page.Assets {
		resolved, err := s.AssetURL(page.Assets[i].URL)
		if err != nil {
			return nil, err
		}
		page.Assets[i].URL = resolved
	}
	return &page, nil
}

func (s *GridService) normalizeCover(cover *GridCover) error {
	if cover == nil {
		return nil
	}
	resolved, err := s.AssetURL(cover.URL)
	if err != nil {
		return err
	}
	cover.URL = resolved
	return nil
}

// AssetURL resolves an asset or cover URL against the origin of the base
// URL. For a public key and a URL on that same origin without a key
// parameter, it adds key=<public key>, so images, fonts and media can load
// without headers. It never adds a private key, and never adds a key to
// another origin.
func (s *GridService) AssetURL(rawURL string) (string, error) {
	resolved, err := s.resolve(rawURL)
	if err != nil {
		return "", err
	}
	if s.publicKey != "" && sameOrigin(originOf(resolved), s.origin) && !resolved.Query().Has("key") {
		if resolved.RawQuery != "" {
			resolved.RawQuery += "&"
		}
		resolved.RawQuery += "key=" + escape(s.publicKey)
	}
	return resolved.String(), nil
}

func (s *GridService) resolve(rawURL string) (*url.URL, error) {
	ref, err := url.Parse(rawURL)
	if err != nil {
		return nil, invalidArgument("Provide a valid asset URL.")
	}
	resolved := s.origin.ResolveReference(ref)
	if resolved.Scheme == "http" || resolved.Scheme == "https" {
		origin := originOf(resolved)
		resolved.Scheme, resolved.Host = origin.Scheme, origin.Host
		if resolved.Path == "" && resolved.RawPath == "" {
			resolved.Path = "/"
		}
	}
	return resolved, nil
}

// DownloadAsset downloads an asset or cover by URL (for example
// GridAssetRef.URL or GridCover.URL). The URL is resolved with AssetURL.
// Authorization is sent only when the URL is on the base URL's origin.
func (s *GridService) DownloadAsset(ctx context.Context, assetURL string) (*Download, error) {
	if assetURL == "" {
		return nil, invalidArgument("Provide an asset URL.")
	}
	resolved, err := s.AssetURL(assetURL)
	if err != nil {
		return nil, err
	}
	u, err := url.Parse(resolved)
	if err != nil {
		return nil, invalidArgument("Provide a valid asset URL.")
	}
	return s.t.download(ctx, resolved, sameOrigin(originOf(u), s.origin))
}
