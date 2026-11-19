package nulldull

// Optional live tests against a real NullDull API. Skipped unless the
// variables are set:
//
//	NULLDULL_PUBLIC_KEY + NULLDULL_GRID_POOL         Grid delivery
//	NULLDULL_PRIVATE_KEY + NULLDULL_WORKSPACE_ID     Memory and Locale
//	NULLDULL_LOCALE_SCOPE_ID (optional)              Locale export location (default: workspace root)
//	NULLDULL_BASE_URL (optional)                     Default https://nulldull.com
//
// Never print key values: asset URLs carry the public key, so these tests
// never log URLs either.

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

func liveOptions() []Option {
	opts := []Option{WithUserAgent("live-test")}
	if base := os.Getenv("NULLDULL_BASE_URL"); base != "" {
		opts = append(opts, WithBaseURL(base))
	}
	return opts
}

func liveGrid(t *testing.T) (*Client, string) {
	t.Helper()
	key, pool := os.Getenv("NULLDULL_PUBLIC_KEY"), os.Getenv("NULLDULL_GRID_POOL")
	if key == "" || pool == "" {
		t.Skip("set NULLDULL_PUBLIC_KEY and NULLDULL_GRID_POOL to run live Grid tests")
	}
	client, err := New(key, liveOptions()...)
	if err != nil {
		var e *Error
		errors.As(err, &e)
		t.Fatalf("New: %s", e.Code) // the message never contains the key, but stay terse
	}
	return client, pool
}

func liveContext(t *testing.T) context.Context {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func TestLiveGridListIterateAndGetPage(t *testing.T) {
	client, pool := liveGrid(t)
	ctx := liveContext(t)

	list, err := client.Grid.ListPages(ctx, pool, &ListPagesParams{Limit: 2})
	if err != nil {
		t.Fatalf("ListPages: %v", err)
	}
	if list.Pool.Key != pool {
		t.Errorf("pool key = %q, want %q", list.Pool.Key, pool)
	}
	if len(list.Items) > 2 {
		t.Errorf("limit 2 returned %d items", len(list.Items))
	}

	count := 0
	var withCover *GridPageSummary
	for summary, err := range client.Grid.IteratePages(ctx, pool, &ListPagesParams{Limit: 2}) {
		if err != nil {
			t.Fatalf("IteratePages: %v", err)
		}
		if summary.Slug == "" || summary.Pool != pool {
			t.Errorf("bad summary: slug %q pool %q", summary.Slug, summary.Pool)
		}
		if summary.Cover != nil && withCover == nil {
			withCover = &summary
		}
		if count++; count >= 10 {
			break
		}
	}
	t.Logf("iterated %d published pages", count)

	if len(list.Items) == 0 {
		t.Log("pool has no published pages; skipping GetPage")
		return
	}
	// Prefer a page with a cover so asset URLs and downloads are exercised.
	first := list.Items[0]
	if withCover != nil {
		first = *withCover
	}
	page, err := client.Grid.GetPage(ctx, pool, first.Slug, &GetPageParams{Locale: first.Locale})
	if err != nil {
		t.Fatalf("GetPage: %v", err)
	}
	if page.ID != first.ID {
		t.Errorf("page ID = %q, want %q", page.ID, first.ID)
	}
	var document struct {
		Nodes []json.RawMessage `json:"nodes"`
	}
	if err := json.Unmarshal(page.Document, &document); err != nil || document.Nodes == nil {
		t.Errorf("document has no nodes array (err %v)", err)
	}

	origin, _ := url.Parse(client.BaseURL())
	urls := []string{}
	if page.Cover != nil {
		urls = append(urls, page.Cover.URL)
	}
	for _, asset := range page.Assets {
		urls = append(urls, asset.URL)
	}
	for i, raw := range urls {
		u, err := url.Parse(raw)
		if err != nil || !strings.HasPrefix(u.Scheme, "http") {
			t.Errorf("asset URL %d is not absolute", i)
			continue
		}
		if u.Host == origin.Host && u.Query().Get("key") != os.Getenv("NULLDULL_PUBLIC_KEY") {
			t.Errorf("same-origin asset URL %d lacks the public key", i)
		}
	}
	t.Logf("page %q: %d assets, cover %v", page.Slug, len(page.Assets), page.Cover != nil)

	// AssetURL is idempotent on already normalized URLs.
	for i, raw := range urls {
		again, err := client.Grid.AssetURL(raw)
		if err != nil || again != raw {
			t.Errorf("AssetURL changed normalized URL %d", i)
		}
	}

	// Download the cover (or first asset) and check its checksum size.
	var target string
	var size int64
	if page.Cover != nil {
		target, size = page.Cover.URL, page.Cover.ByteSize
	} else if len(page.Assets) > 0 {
		target, size = page.Assets[0].URL, page.Assets[0].ByteSize
	}
	if target != "" && size > 0 && size < 20<<20 {
		download, err := client.Grid.DownloadAsset(ctx, target)
		if err != nil {
			t.Fatalf("DownloadAsset: %v", err)
		}
		if int64(download.Size) != size {
			t.Errorf("downloaded %d bytes, manifest says %d", download.Size, size)
		}
		t.Logf("downloaded %d bytes (%s)", download.Size, download.ContentType)
	}
}

func TestLiveGridNotFound(t *testing.T) {
	client, pool := liveGrid(t)
	_, err := client.Grid.GetPage(liveContext(t), pool, "nulldull-sdk-live-test-missing-page", nil)
	e := asError(t, err)
	if e.Status != 404 || e.Code != "NOT_FOUND" {
		t.Errorf("error = %d %s, want 404 NOT_FOUND", e.Status, e.Code)
	}
	if e.RequestID == "" {
		t.Log("no request ID on the 404 response")
	}
}

func TestLiveGridPublicKeyCannotUsePlatform(t *testing.T) {
	key := os.Getenv("NULLDULL_PUBLIC_KEY")
	if key == "" || os.Getenv("NULLDULL_GRID_POOL") == "" {
		t.Skip("set NULLDULL_PUBLIC_KEY and NULLDULL_GRID_POOL to run live Grid tests")
	}
	client, err := New(key, append(liveOptions(), WithWorkspaceID("w"))...)
	if err != nil {
		t.Fatal("New failed")
	}
	_, err = client.Memory.ListScopes(liveContext(t), nil)
	wantCode(t, err, CodePrivateKeyRequired)
}

func livePlatform(t *testing.T) (*Client, string) {
	t.Helper()
	key, workspace := os.Getenv("NULLDULL_PRIVATE_KEY"), os.Getenv("NULLDULL_WORKSPACE_ID")
	if key == "" || workspace == "" {
		t.Skip("set NULLDULL_PRIVATE_KEY and NULLDULL_WORKSPACE_ID to run live Memory and Locale tests")
	}
	client, err := New(key, append(liveOptions(), WithWorkspaceID(workspace))...)
	if err != nil {
		t.Fatal("New failed")
	}
	return client, workspace
}

// forbidden reports a 403: a key without memory:read or locale:read is a
// configuration problem, not an SDK failure.
func forbidden(t *testing.T, err error) bool {
	var e *Error
	if errors.As(err, &e) && e.Code == "FORBIDDEN" {
		t.Skip("the key lacks the scope for this call (403 FORBIDDEN)")
		return true
	}
	return false
}

func TestLiveMemory(t *testing.T) {
	client, workspace := livePlatform(t)
	ctx := liveContext(t)
	scopes, err := client.Memory.ListScopes(ctx, nil)
	if err != nil {
		forbidden(t, err)
		t.Fatalf("ListScopes: %v", err)
	}
	found := false
	for _, scope := range scopes.Items {
		found = found || scope.ID == workspace
	}
	if !found {
		t.Error("the workspace root location is not among the scopes")
	}
	documents, err := client.Memory.ListDocuments(ctx, nil)
	if err != nil {
		t.Fatalf("ListDocuments: %v", err)
	}
	if len(documents.Items) > 0 {
		document, err := client.Memory.GetDocument(ctx, documents.Items[0].ID)
		if err != nil {
			t.Fatalf("GetDocument: %v", err)
		}
		if document.ID != documents.Items[0].ID {
			t.Error("GetDocument returned another document")
		}
	}
	if _, err := client.Memory.ListTags(ctx, nil); err != nil {
		t.Fatalf("ListTags: %v", err)
	}
	if _, err := client.Memory.Search(ctx, "the", nil); err != nil {
		t.Fatalf("Search: %v", err)
	}
}

func TestLiveLocale(t *testing.T) {
	client, workspace := livePlatform(t)
	ctx := liveContext(t)
	formats, err := client.Locale.ListFormats(ctx)
	if err != nil {
		forbidden(t, err)
		t.Fatalf("ListFormats: %v", err)
	}
	hasJSON := false
	for _, format := range formats.Items {
		hasJSON = hasJSON || format.ID == FormatJSON
	}
	if !hasJSON {
		t.Error("formats do not include json")
	}
	scope := os.Getenv("NULLDULL_LOCALE_SCOPE_ID")
	if scope == "" {
		scope = workspace
	}
	exported, err := client.Locale.Export(ctx, scope, nil)
	if err != nil {
		forbidden(t, err)
		var e *Error
		if errors.As(err, &e) && e.Status == 404 {
			t.Skip("no Locale library at this location")
		}
		t.Fatalf("Export: %v", err)
	}
	if exported.Format != FormatJSON {
		t.Errorf("format = %q", exported.Format)
	}
}
