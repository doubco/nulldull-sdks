package nulldull

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

var bg = context.Background()

func emptyPage() responder {
	return jsonResponse(200, map[string]any{"items": []any{}, "nextCursor": nil})
}

func rawQuery(t *testing.T, r recorded) string {
	t.Helper()
	u, err := url.Parse(r.URL)
	if err != nil {
		t.Fatal(err)
	}
	return u.RawQuery
}

// ---------------------------------------------------------------- 1. construction

func TestConstructionRejectsMalformedKeys(t *testing.T) {
	for _, key := range []string{"", "nd_pub_123", "nd_xyz_" + strings.Repeat("a", 64), "nd_pub_" + strings.Repeat("A", 64), "ndm_" + strings.Repeat("a", 64), "nd_pub_" + strings.Repeat("a", 65)} {
		_, err := New(key)
		e := wantCode(t, err, CodeInvalidArgument)
		if e.Status != 0 {
			t.Errorf("status = %d, want 0", e.Status)
		}
	}
}

func TestConstructionRejectsBadOptions(t *testing.T) {
	key := loadManifest(t).Config.PublicKey
	cases := map[string]Option{
		"ftp scheme":        WithBaseURL("ftp://nulldull.com"),
		"no scheme":         WithBaseURL("nulldull.com"),
		"user info":         WithBaseURL("https://user:pass@nulldull.com"),
		"query":             WithBaseURL("https://nulldull.com/?x=1"),
		"empty query":       WithBaseURL("https://nulldull.com/?"),
		"fragment":          WithBaseURL("https://nulldull.com/#top"),
		"no host":           WithBaseURL("https:///path"),
		"workspace path":    WithWorkspaceID("../etc"),
		"workspace long":    WithWorkspaceID(strings.Repeat("a", 129)),
		"negative timeout":  WithTimeout(-time.Second),
		"negative retries":  WithMaxRetries(-1),
		"nil http client":   WithHTTPClient(nil),
		"nil sleep":         WithSleep(nil),
		"workspace unicode": WithWorkspaceID("çalışma"),
	}
	for name, opt := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := New(key, opt)
			wantCode(t, err, CodeInvalidArgument)
		})
	}
}

func TestConstructionNormalizesBaseURL(t *testing.T) {
	key := loadManifest(t).Config.PublicKey
	for _, tc := range []struct{ in, base, request string }{
		{"https://staging.nulldull.com/", "https://staging.nulldull.com", "https://staging.nulldull.com/api/grid/v1/pools/nulldull-blog/pages?locale=en"},
		{"http://localhost:8787/proxy/", "http://localhost:8787/proxy", "http://localhost:8787/proxy/api/grid/v1/pools/nulldull-blog/pages?locale=en"},
		{"HTTPS://NullDull.com:443", "https://nulldull.com", "https://nulldull.com/api/grid/v1/pools/nulldull-blog/pages?locale=en"},
	} {
		mock := &mockTransport{queue: []responder{fixtureResponse(t, 200, "grid/page-list-last.json")}}
		client, err := New(key, WithBaseURL(tc.in), WithHTTPClient(&http.Client{Transport: mock}))
		if err != nil {
			t.Fatal(err)
		}
		if client.BaseURL() != tc.base {
			t.Errorf("BaseURL() = %q, want %q", client.BaseURL(), tc.base)
		}
		if _, err := client.Grid.ListPages(bg, "nulldull-blog", nil); err != nil {
			t.Fatal(err)
		}
		if got := mock.get(0).URL; got != tc.request {
			t.Errorf("request URL = %q, want %q", got, tc.request)
		}
	}
}

func TestConstructionDefaults(t *testing.T) {
	m := loadManifest(t)
	client, err := New(m.Config.PrivateKey)
	if err != nil {
		t.Fatal(err)
	}
	if client.BaseURL() != DefaultBaseURL || client.KeyKind() != PrivateKey || client.WorkspaceID() != "" {
		t.Errorf("defaults: %q %q %q", client.BaseURL(), client.KeyKind(), client.WorkspaceID())
	}
	public, _ := New(m.Config.PublicKey, WithWorkspaceID(m.Config.WorkspaceID))
	if public.KeyKind() != PublicKey || public.WorkspaceID() != m.Config.WorkspaceID {
		t.Errorf("public client: %q %q", public.KeyKind(), public.WorkspaceID())
	}
}

// ---------------------------------------------------------------- 2. request headers

func TestRequestHeaders(t *testing.T) {
	m := loadManifest(t)
	c := newTestClient(t, "private", []responder{fixtureResponse(t, 200, "memory/scopes.json"), respond(200, nil, []byte("x"))}, WithUserAgent("my-app/2.0"))
	if _, err := c.Memory.ListScopes(bg, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Memory.DownloadAsset(bg, "asset_1", nil); err != nil {
		t.Fatal(err)
	}
	first, second := c.mock.get(0), c.mock.get(1)
	if first.Method != http.MethodGet || second.Method != http.MethodGet {
		t.Errorf("methods = %s, %s", first.Method, second.Method)
	}
	if first.Header.Get("Authorization") != "Bearer "+m.Config.PrivateKey || second.Header.Get("Authorization") != "Bearer "+m.Config.PrivateKey {
		t.Error("Authorization header missing or wrong")
	}
	if got := first.Header.Get("Accept"); got != "application/json" {
		t.Errorf("Accept = %q", got)
	}
	if got := second.Header.Get("Accept"); got != "*/*" {
		t.Errorf("download Accept = %q", got)
	}
	if got := first.Header.Get("User-Agent"); got != "nulldull-sdk-go/0.1.0 my-app/2.0" {
		t.Errorf("User-Agent = %q", got)
	}
	if strings.Contains(second.URL, "submissionId") {
		t.Error("download sent submissionId")
	}
}

func TestDefaultUserAgentAndVersion(t *testing.T) {
	if Version != "0.1.0" {
		t.Errorf("Version = %q", Version)
	}
	c := newTestClient(t, "public", []responder{fixtureResponse(t, 200, "grid/page-list-last.json")})
	if _, err := c.Grid.ListPages(bg, "nulldull-blog", nil); err != nil {
		t.Fatal(err)
	}
	if got := c.mock.get(0).Header.Get("User-Agent"); got != "nulldull-sdk-go/"+Version {
		t.Errorf("User-Agent = %q", got)
	}
}

func TestRedirectsAreErrorsAndNeverFollowed(t *testing.T) {
	var evilHits atomic.Int32
	evil := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		evilHits.Add(1)
	}))
	defer evil.Close()
	var sawCookie atomic.Bool
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") != "" {
			sawCookie.Store(true)
		}
		http.Redirect(w, r, evil.URL+"/steal", http.StatusFound)
	}))
	defer api.Close()

	// Even a caller's client that follows redirects and keeps cookies is overridden.
	jar, _ := cookiejar.New(nil)
	apiURL, _ := url.Parse(api.URL)
	jar.SetCookies(apiURL, []*http.Cookie{{Name: "session", Value: "secret"}})
	follower := &http.Client{Jar: jar, CheckRedirect: func(*http.Request, []*http.Request) error { return nil }}
	client, err := New(loadManifest(t).Config.PublicKey, WithBaseURL(api.URL), WithHTTPClient(follower))
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Grid.ListPages(bg, "nulldull-blog", nil)
	e := wantCode(t, err, CodeRequestFailed)
	if e.Status != http.StatusFound {
		t.Errorf("status = %d, want 302", e.Status)
	}
	if evilHits.Load() != 0 {
		t.Error("the redirect was followed")
	}
	if sawCookie.Load() {
		t.Error("cookies were sent")
	}
	if follower.CheckRedirect == nil || follower.Jar == nil {
		t.Error("the caller's http.Client was modified")
	}
}

// ---------------------------------------------------------------- 3. Memory and Locale preconditions

func TestMemoryAndLocaleNeedWorkspaceID(t *testing.T) {
	m := loadManifest(t)
	mock := &mockTransport{}
	client, err := New(m.Config.PrivateKey, WithHTTPClient(&http.Client{Transport: mock}))
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Memory.ListDocuments(bg, nil)
	wantCode(t, err, CodeWorkspaceRequired)
	_, err = client.Locale.Export(bg, m.Config.WorkspaceID, nil)
	wantCode(t, err, CodeWorkspaceRequired)
	_, err = client.Memory.DownloadAsset(bg, "asset", nil)
	wantCode(t, err, CodeWorkspaceRequired)
	_, err = collect(client.Memory.IterateDocuments(bg, nil))
	wantCode(t, err, CodeWorkspaceRequired)
	if mock.count() != 0 {
		t.Errorf("sent %d requests", mock.count())
	}
}

func TestMemoryAndLocaleNeedPrivateKey(t *testing.T) {
	c := newTestClient(t, "public", nil)
	_, err := c.Memory.GetDocument(bg, "doc")
	wantCode(t, err, CodePrivateKeyRequired)
	_, err = c.Locale.ListFormats(bg)
	wantCode(t, err, CodePrivateKeyRequired)
	_, err = collect(c.Memory.IterateTags(bg, nil))
	wantCode(t, err, CodePrivateKeyRequired)
	if c.mock.count() != 0 {
		t.Errorf("sent %d requests", c.mock.count())
	}
}

func TestPathSegmentsAreEncodedAndIDsRequired(t *testing.T) {
	m := loadManifest(t)
	c := newTestClient(t, "private", []responder{jsonResponse(200, map[string]any{})})
	if _, err := c.Memory.GetDocument(bg, "a/b c"); err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse(c.mock.get(0).URL)
	if want := "/api/platform/workspaces/" + m.Config.WorkspaceID + "/documents/a%2Fb%20c"; u.EscapedPath() != want {
		t.Errorf("path = %s, want %s", u.EscapedPath(), want)
	}
	for _, call := range []func() error{
		func() error { _, err := c.Memory.GetDocument(bg, ""); return err },
		func() error { _, err := c.Memory.GetFolder(bg, ""); return err },
		func() error { _, err := c.Memory.GetAsset(bg, "", nil); return err },
		func() error { _, err := c.Memory.ResolveLink(bg, "", "a.md"); return err },
		func() error { _, err := c.Memory.ListAssetVersions(bg, "", nil); return err },
		func() error { _, err := c.Memory.DownloadAsset(bg, "", nil); return err },
	} {
		wantCode(t, call(), CodeInvalidArgument)
	}
	if c.mock.count() != 1 {
		t.Errorf("sent %d requests, want 1", c.mock.count())
	}
}

// ---------------------------------------------------------------- 4. Grid validation

func TestGridValidatesBeforeAnyRequest(t *testing.T) {
	c := newTestClient(t, "public", nil)
	g := c.Grid
	for name, call := range map[string]func() error{
		"pool case":   func() error { _, err := g.ListPages(bg, "Bad_Pool", nil); return err },
		"pool empty":  func() error { _, err := g.ListPages(bg, "", nil); return err },
		"pool long":   func() error { _, err := g.ListPages(bg, strings.Repeat("x", 97), nil); return err },
		"locale case": func() error { _, err := g.ListPages(bg, "pool", &ListPagesParams{Locale: "EN"}); return err },
		"locale long": func() error {
			_, err := g.ListPages(bg, "pool", &ListPagesParams{Locale: "en-" + strings.Repeat("abcdefgh-", 4)})
			return err
		},
		"limit low":     func() error { _, err := g.ListPages(bg, "pool", &ListPagesParams{Limit: -1}); return err },
		"limit high":    func() error { _, err := g.ListPages(bg, "pool", &ListPagesParams{Limit: 51}); return err },
		"slug hyphens":  func() error { _, err := g.GetPage(bg, "pool", "a--b", nil); return err },
		"slug long":     func() error { _, err := g.GetPage(bg, "pool", strings.Repeat("x", 97), nil); return err },
		"page locale":   func() error { _, err := g.GetPage(bg, "pool", "slug", &GetPageParams{Locale: "pt_BR"}); return err },
		"iterate pool":  func() error { _, err := collect(g.IteratePages(bg, "Bad", nil)); return err },
		"download none": func() error { _, err := g.DownloadAsset(bg, ""); return err },
	} {
		if err := call(); err == nil || asError(t, err).Code != CodeInvalidArgument {
			t.Errorf("%s: err = %v, want INVALID_ARGUMENT", name, err)
		}
	}
	if c.mock.count() != 0 {
		t.Errorf("sent %d requests", c.mock.count())
	}
}

func TestGridAlwaysSendsLocale(t *testing.T) {
	c := newTestClient(t, "public", []responder{
		fixtureResponse(t, 200, "grid/page-list-last.json"),
		fixtureResponse(t, 200, "grid/page.json"),
		fixtureResponse(t, 200, "grid/page-list-last.json"),
	})
	if _, err := c.Grid.ListPages(bg, "nulldull-blog", &ListPagesParams{Q: ""}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Grid.GetPage(bg, "nulldull-blog", "hello", &GetPageParams{Locale: "pt-br"}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Grid.ListPages(bg, "nulldull-blog", &ListPagesParams{Limit: 50, Q: "a b&c"}); err != nil {
		t.Fatal(err)
	}
	for i, want := range []string{"locale=en", "locale=pt-br", "locale=en&q=a%20b%26c&limit=50"} {
		if got := rawQuery(t, c.mock.get(i)); got != want {
			t.Errorf("request %d query = %q, want %q", i, got, want)
		}
	}
}

// ---------------------------------------------------------------- 5. grid.AssetURL

func TestAssetURL(t *testing.T) {
	m := loadManifest(t)
	pub := newTestClient(t, "public", nil).Grid
	sec := newTestClient(t, "private", nil).Grid
	key := m.Config.PublicKey

	mustURL := func(g *GridService, in string) string {
		t.Helper()
		out, err := g.AssetURL(in)
		if err != nil {
			t.Fatalf("AssetURL(%q): %v", in, err)
		}
		return out
	}
	for in, want := range map[string]string{
		"/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3": "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3&key=" + key,
		"https://NULLDULL.com:443/x":                                "https://nulldull.com/x?key=" + key,
		"https://nulldull.com":                                      "https://nulldull.com/?key=" + key,
		"/x?key=nd_pub_existing":                                    "https://nulldull.com/x?key=nd_pub_existing",
	} {
		if got := mustURL(pub, in); got != want {
			t.Errorf("AssetURL(%q) = %q, want %q", in, got, want)
		}
	}
	for _, in := range []string{
		"https://cdn.example.com/a.png",
		"//evil.example/a.png",
		"https://nulldull.com.evil.example/a.png",
		"http://nulldull.com/a.png",
		"https://nulldull.com:8443/a.png",
		"https://evil.example/?next=https://nulldull.com/",
	} {
		if got := mustURL(pub, in); strings.Contains(got, "key=") {
			t.Errorf("AssetURL(%q) added a key", in)
		}
	}
	if got := mustURL(pub, "//evil.example/a.png"); got != "https://evil.example/a.png" {
		t.Errorf("protocol-relative URL resolved to %q", got)
	}
	if got := mustURL(sec, "/api/grid/v1/pools/p/pages/s/assets/a?version=1"); got != "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?version=1" {
		t.Errorf("private key AssetURL = %q", got)
	}
	if _, err := pub.AssetURL("http://[::1"); err == nil {
		t.Error("invalid URL accepted")
	}
}

// ---------------------------------------------------------------- 6. grid.DownloadAsset

func TestGridDownloadSendsAuthorizationOnlyToTheAPIOrigin(t *testing.T) {
	m := loadManifest(t)
	bytesResponse := respond(200, map[string]string{"content-type": "image/png", "content-disposition": "inline; filename*=UTF-8''cover.png"}, []byte{1, 2, 3})
	c := newTestClient(t, "private", []responder{bytesResponse, bytesResponse})
	var page GridPage
	if err := json.Unmarshal(readFixture(t, "grid/page.json"), &page); err != nil {
		t.Fatal(err)
	}
	own, err := c.Grid.DownloadAsset(bg, page.Assets[0].URL)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.Grid.DownloadAsset(bg, "https://cdn.example.com/cover.png"); err != nil {
		t.Fatal(err)
	}
	if own.ContentType != "image/png" || own.Filename != "cover.png" || own.Size != 3 {
		t.Errorf("download = %+v", own)
	}
	first, second := c.mock.get(0), c.mock.get(1)
	if !strings.HasPrefix(first.URL, "https://nulldull.com/") || first.Header.Get("Authorization") != "Bearer "+m.Config.PrivateKey {
		t.Error("first download should go to the API origin with Authorization")
	}
	if strings.Contains(first.URL, m.Config.PrivateKey) {
		t.Error("a private key was added to a URL")
	}
	if _, has := second.Header["Authorization"]; has {
		t.Error("Authorization was sent to another origin")
	}
}

// ---------------------------------------------------------------- 7. URL normalization

func TestGridNormalizesCoverAndAssetURLs(t *testing.T) {
	c := newTestClient(t, "public", []responder{fixtureResponse(t, 200, "grid/page-list.json"), fixtureResponse(t, 200, "grid/page.json")})
	list, err := c.Grid.ListPages(bg, "nulldull-blog", nil)
	if err != nil {
		t.Fatal(err)
	}
	page, err := c.Grid.GetPage(bg, "nulldull-blog", "context-that-survives-the-chat", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(list.Items[0].Cover.URL, "https://nulldull.com/api/grid/v1/") {
		t.Error("list cover URL not absolute")
	}
	if list.Items[1].Cover != nil {
		t.Error("null cover should stay nil")
	}
	if !strings.HasPrefix(page.Cover.URL, "https://nulldull.com/") {
		t.Error("page cover URL not absolute")
	}
	for _, asset := range page.Assets {
		if !strings.HasPrefix(asset.URL, "https://nulldull.com/") {
			t.Error("asset URL not absolute")
		}
	}
	var original struct {
		Document json.RawMessage `json:"document"`
	}
	_ = json.Unmarshal(readFixture(t, "grid/page.json"), &original)
	if !jsonEqual(toGeneric(t, page.Document), toGeneric(t, original.Document)) {
		t.Error("document was changed")
	}
	if list.Pool.Key != "nulldull-blog" || list.Pool.Name != "The Void" {
		t.Errorf("pool = %+v", list.Pool)
	}
}

func TestUnknownFieldsAndEnumsRoundTrip(t *testing.T) {
	body := map[string]any{
		"items": []any{map[string]any{
			"id": "s1", "name": "Root", "kind": "galaxy", "parentId": nil, "brandNew": map[string]any{"x": 1.0},
		}},
		"nextCursor": nil,
		"total":      7.0,
	}
	c := newTestClient(t, "private", []responder{jsonResponse(200, body)})
	page, err := c.Memory.ListScopes(bg, nil)
	if err != nil {
		t.Fatal(err)
	}
	if page.Items[0].Kind != "galaxy" {
		t.Errorf("kind = %q", page.Items[0].Kind)
	}
	if string(page.Extra["total"]) != "7" || page.Items[0].Extra["brandNew"] == nil {
		t.Errorf("extra fields lost: %v / %v", page.Extra, page.Items[0].Extra)
	}
	if !jsonEqual(toGeneric(t, page), body) {
		t.Errorf("round trip = %s", mustJSON(toGeneric(t, page)))
	}
}

// ---------------------------------------------------------------- 8. pagination

func TestIterationStartsFromAfterAndStopsAtNullCursor(t *testing.T) {
	c := newTestClient(t, "private", []responder{fixtureResponse(t, 200, "memory/documents-page-2.json")})
	items, err := collect(c.Memory.IterateDocuments(bg, &ListDocumentsParams{After: "cursor-1", ScopeID: "s"}))
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 {
		t.Errorf("items = %d, want 1", len(items))
	}
	if got := rawQuery(t, c.mock.get(0)); got != "scopeId=s&after=cursor-1" {
		t.Errorf("query = %q", got)
	}
}

func TestIterationContinuesThroughEmptyPages(t *testing.T) {
	c := newTestClient(t, "private", []responder{
		jsonResponse(200, map[string]any{"items": []any{}, "nextCursor": "c1"}),
		jsonResponse(200, map[string]any{"items": []any{}, "nextCursor": "c2"}),
		jsonResponse(200, map[string]any{"items": []any{map[string]any{"tag": "a", "count": 1}}, "nextCursor": nil}),
	})
	items, err := collect(c.Memory.IterateTags(bg, nil))
	if err != nil || len(items) != 1 || items[0].Tag != "a" {
		t.Fatalf("items = %+v, err = %v", items, err)
	}
	if c.mock.count() != 3 {
		t.Errorf("requests = %d", c.mock.count())
	}
}

func TestIterationRejectsARepeatedCursor(t *testing.T) {
	page := map[string]any{"items": []any{map[string]any{"id": "a"}}, "nextCursor": "same"}
	c := newTestClient(t, "private", []responder{jsonResponse(200, page), jsonResponse(200, page)})
	var seen int
	var err error
	for _, e := range c.Memory.IterateScopes(bg, nil) {
		if e != nil {
			err = e
			break
		}
		seen++
	}
	wantCode(t, err, CodeInvalidResponse)
	if seen != 2 {
		t.Errorf("seen = %d, want 2", seen)
	}
}

func TestIterationIsLazyAndStopsOnBreak(t *testing.T) {
	c := newTestClient(t, "private", []responder{fixtureResponse(t, 200, "memory/tags-page-1.json")})
	seq := c.Memory.IterateTags(bg, nil)
	if c.mock.count() != 0 {
		t.Fatal("requested before iterating")
	}
	for tag, err := range seq {
		if err != nil {
			t.Fatal(err)
		}
		if tag.Tag != "maintained" {
			t.Errorf("first tag = %q", tag.Tag)
		}
		break
	}
	if c.mock.count() != 1 {
		t.Errorf("requests = %d, want 1", c.mock.count())
	}
}

// ---------------------------------------------------------------- 9. errors

func TestErrorFieldsComeFromBodyAndHeaders(t *testing.T) {
	m := loadManifest(t)
	c := newTestClient(t, "private", []responder{
		respond(400, map[string]string{"content-type": "application/json", "cf-ray": "abc-AMS"}, readFixture(t, "errors/locale-format-unrepresentable.json")),
	})
	_, err := c.Locale.Export(bg, m.Config.WorkspaceID, &ExportParams{Format: FormatWorld})
	e := asError(t, err)
	if e.Status != 400 || e.Code != "INVALID_INPUT" || e.Detail != "LOCALE_FORMAT_UNREPRESENTABLE" ||
		e.Message != "Plural values cannot be written to this format." || e.RequestID != "abc-AMS" || e.RetryAfter != nil {
		t.Errorf("error = %+v", e)
	}
	if e.Body["key"] != "cart.items" || e.Body["language"] != "tr" {
		t.Errorf("body = %v", e.Body)
	}
	if err.Error() != e.Message {
		t.Errorf("Error() = %q", err.Error())
	}
}

func TestErrorPrefersXRequestIDAndBuildsADefaultMessage(t *testing.T) {
	c := newTestClient(t, "private", []responder{jsonResponse(403, map[string]any{"code": "FORBIDDEN"}, "x-request-id", "req_1", "cf-ray", "ray")})
	_, err := c.Memory.ListScopes(bg, nil)
	e := asError(t, err)
	if e.RequestID != "req_1" || e.Message != "NullDull request failed (403 FORBIDDEN)." || e.Detail != "" {
		t.Errorf("error = %+v", e)
	}
}

func TestNonJSONErrorAndInvalidSuccessJSON(t *testing.T) {
	c := newTestClient(t, "private", []responder{
		respond(404, map[string]string{"content-type": "text/plain"}, []byte("404 Not Found")),
		respond(200, nil, []byte("<html>")),
		jsonResponse(500, map[string]any{"code": 42}),
	})
	_, err := c.Memory.ListScopes(bg, nil)
	if e := wantCode(t, err, CodeRequestFailed); e.Status != 404 || e.Body != nil || e.Message != "NullDull request failed (404 REQUEST_FAILED)." {
		t.Errorf("error = %+v", e)
	}
	_, err = c.Memory.ListScopes(bg, nil)
	if e := wantCode(t, err, CodeInvalidResponse); e.Status != 200 || e.Err == nil {
		t.Errorf("error = %+v", e)
	}
	_, err = c.Memory.ListScopes(bg, nil)
	if e := wantCode(t, err, CodeRequestFailed); e.Status != 500 || e.Body == nil {
		t.Errorf("non-string code: %+v", e)
	}
}

func TestErrorsAsThroughWrapping(t *testing.T) {
	_, err := New("bad")
	wrapped := errors.Join(errors.New("context"), err)
	var e *Error
	if !errors.As(wrapped, &e) || e.Code != CodeInvalidArgument || e.Status != 0 {
		t.Errorf("errors.As failed: %v", wrapped)
	}
}

// ---------------------------------------------------------------- 10. retries

func TestParseRetryAfter(t *testing.T) {
	now := time.Date(2026, 11, 20, 10, 0, 0, 0, time.UTC)
	for in, want := range map[string]int{"Fri, 20 Nov 2026 10:00:05 GMT": 5, "7": 7, " 30 ": 30, "Fri, 20 Nov 2026 09:00:00 GMT": 0} {
		got := parseRetryAfter(in, now)
		if got == nil || *got != want {
			t.Errorf("parseRetryAfter(%q) = %v, want %d", in, got, want)
		}
	}
	for _, in := range []string{"", "soon", "-1", "1.5"} {
		if got := parseRetryAfter(in, now); got != nil {
			t.Errorf("parseRetryAfter(%q) = %d, want nil", in, *got)
		}
	}
}

func TestRetriesBackOffWithoutRetryAfter(t *testing.T) {
	c := newTestClient(t, "private", []responder{
		jsonResponse(504, map[string]any{"code": "X"}),
		jsonResponse(429, map[string]any{"code": "RATE_LIMITED"}),
		fixtureResponse(t, 200, "memory/scopes.json"),
	})
	if _, err := c.Memory.ListScopes(bg, nil); err != nil {
		t.Fatal(err)
	}
	if got := c.slept(); !reflect.DeepEqual(got, []time.Duration{500 * time.Millisecond, time.Second}) {
		t.Errorf("sleeps = %v", got)
	}
}

func TestRetryAfterOfExactly30SecondsIsWaited(t *testing.T) {
	c := newTestClient(t, "private", []responder{
		jsonResponse(429, map[string]any{"code": "RATE_LIMITED"}, "retry-after", "30"),
		fixtureResponse(t, 200, "memory/scopes.json"),
	})
	if _, err := c.Memory.ListScopes(bg, nil); err != nil {
		t.Fatal(err)
	}
	if got := c.slept(); !reflect.DeepEqual(got, []time.Duration{30 * time.Second}) {
		t.Errorf("sleeps = %v", got)
	}
}

func TestRetryAfterOver30SecondsIsReturned(t *testing.T) {
	c := newTestClient(t, "private", []responder{jsonResponse(429, map[string]any{"code": "RATE_LIMITED"}, "retry-after", "31")})
	_, err := c.Memory.ListScopes(bg, nil)
	e := wantCode(t, err, "RATE_LIMITED")
	if e.RetryAfter == nil || *e.RetryAfter != 31 || c.mock.count() != 1 || len(c.slept()) != 0 {
		t.Errorf("error = %+v, requests = %d", e, c.mock.count())
	}
}

func TestMaxRetriesZeroDisablesRetries(t *testing.T) {
	c := newTestClient(t, "private", []responder{jsonResponse(503, map[string]any{"code": "SERVICE_UNAVAILABLE"})}, WithMaxRetries(0))
	_, err := c.Memory.ListScopes(bg, nil)
	wantCode(t, err, "SERVICE_UNAVAILABLE")
	if c.mock.count() != 1 {
		t.Errorf("requests = %d", c.mock.count())
	}
}

func TestMaxRetriesIsTheBudget(t *testing.T) {
	responders := []responder{}
	for i := 0; i < 5; i++ {
		responders = append(responders, jsonResponse(502, map[string]any{"code": "BAD_GATEWAY"}))
	}
	c := newTestClient(t, "private", responders, WithMaxRetries(4))
	_, err := c.Memory.ListScopes(bg, nil)
	wantCode(t, err, "BAD_GATEWAY")
	want := []time.Duration{500 * time.Millisecond, time.Second, 2 * time.Second, 4 * time.Second}
	if c.mock.count() != 5 || !reflect.DeepEqual(c.slept(), want) {
		t.Errorf("requests = %d, sleeps = %v", c.mock.count(), c.slept())
	}
}

func TestClientErrorsAreNeverRetried(t *testing.T) {
	for _, status := range []int{400, 401, 403, 404, 409, 500} {
		c := newTestClient(t, "private", []responder{jsonResponse(status, map[string]any{"code": "X"})})
		_, err := c.Memory.ListScopes(bg, nil)
		if e := asError(t, err); e.Status != status {
			t.Errorf("status = %d, want %d", e.Status, status)
		}
		if c.mock.count() != 1 {
			t.Errorf("%d was retried", status)
		}
	}
}

func TestNetworkErrorsAreRetried(t *testing.T) {
	cause := errors.New("connection reset by peer")
	c := newTestClient(t, "private", []responder{failWith(cause), failWith(cause), failWith(cause)})
	_, err := c.Memory.ListScopes(bg, nil)
	e := wantCode(t, err, CodeNetworkError)
	if e.Status != 0 || !errors.Is(err, cause) {
		t.Errorf("error = %+v", e)
	}
	if c.mock.count() != 3 || !reflect.DeepEqual(c.slept(), []time.Duration{500 * time.Millisecond, time.Second}) {
		t.Errorf("requests = %d, sleeps = %v", c.mock.count(), c.slept())
	}

	c = newTestClient(t, "private", []responder{failWith(cause), fixtureResponse(t, 200, "memory/scopes.json")})
	page, err := c.Memory.ListScopes(bg, nil)
	if err != nil || len(page.Items) != 3 {
		t.Fatalf("recovery failed: %v", err)
	}
}

func TestRealNetworkErrorIsRetried(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close() // nothing listens: connection refused
	var sleeps atomic.Int32
	client, err := New(loadManifest(t).Config.PublicKey, WithBaseURL("http://"+addr),
		WithSleep(func(ctx context.Context, d time.Duration) error { sleeps.Add(1); return nil }))
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Grid.ListPages(bg, "nulldull-blog", nil)
	wantCode(t, err, CodeNetworkError)
	if sleeps.Load() != 2 {
		t.Errorf("retries = %d, want 2", sleeps.Load())
	}
}

// ---------------------------------------------------------------- 11. timeouts and cancellation

func hangingServer(t *testing.T, hits *atomic.Int32, flushHeaders bool) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		if flushHeaders {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(200)
			_, _ = w.Write([]byte(`{"items":`))
			w.(http.Flusher).Flush()
		}
		select {
		case <-r.Context().Done():
		case <-time.After(5 * time.Second):
		}
	}))
	t.Cleanup(server.Close)
	return server
}

func TestTimeoutIsReturnedAndNotRetried(t *testing.T) {
	m := loadManifest(t)
	var hits atomic.Int32
	server := hangingServer(t, &hits, false)
	client, _ := New(m.Config.PrivateKey, WithBaseURL(server.URL), WithWorkspaceID(m.Config.WorkspaceID), WithTimeout(30*time.Millisecond))
	_, err := client.Memory.ListScopes(bg, nil)
	if e := wantCode(t, err, CodeTimeout); e.Status != 0 {
		t.Errorf("status = %d", e.Status)
	}
	if hits.Load() != 1 {
		t.Errorf("hits = %d, want 1", hits.Load())
	}
}

func TestTimeoutCoversReadingTheBody(t *testing.T) {
	m := loadManifest(t)
	var hits atomic.Int32
	server := hangingServer(t, &hits, true)
	client, _ := New(m.Config.PrivateKey, WithBaseURL(server.URL), WithWorkspaceID(m.Config.WorkspaceID), WithTimeout(50*time.Millisecond))
	_, err := client.Memory.ListScopes(bg, nil)
	wantCode(t, err, CodeTimeout)
	if hits.Load() != 1 {
		t.Errorf("hits = %d, want 1", hits.Load())
	}
}

func TestCallerCancellationIsAborted(t *testing.T) {
	m := loadManifest(t)
	var hits atomic.Int32
	server := hangingServer(t, &hits, false)
	client, _ := New(m.Config.PrivateKey, WithBaseURL(server.URL), WithWorkspaceID(m.Config.WorkspaceID))

	ctx, cancel := context.WithCancel(bg)
	time.AfterFunc(20*time.Millisecond, cancel)
	_, err := client.Memory.ListScopes(ctx, nil)
	wantCode(t, err, CodeAborted)
	if !errors.Is(err, context.Canceled) {
		t.Error("errors.Is(err, context.Canceled) = false")
	}

	deadline, cancelDeadline := context.WithTimeout(bg, 20*time.Millisecond)
	defer cancelDeadline()
	_, err = client.Memory.ListScopes(deadline, nil)
	wantCode(t, err, CodeAborted)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Error("errors.Is(err, context.DeadlineExceeded) = false")
	}
}

func TestAlreadyCancelledContextSendsNothing(t *testing.T) {
	c := newTestClient(t, "public", nil)
	ctx, cancel := context.WithCancel(bg)
	cancel()
	_, err := c.Grid.GetPage(ctx, "p", "s", nil)
	wantCode(t, err, CodeAborted)
	if c.mock.count() != 0 {
		t.Errorf("requests = %d", c.mock.count())
	}
}

func TestCancellationWhileWaitingToRetry(t *testing.T) {
	m := loadManifest(t)
	mock := &mockTransport{queue: []responder{jsonResponse(503, map[string]any{"code": "SERVICE_UNAVAILABLE"})}}
	client, _ := New(m.Config.PrivateKey, WithWorkspaceID(m.Config.WorkspaceID), WithHTTPClient(&http.Client{Transport: mock}))
	ctx, cancel := context.WithCancel(bg)
	time.AfterFunc(20*time.Millisecond, cancel)
	start := time.Now()
	_, err := client.Memory.ListScopes(ctx, nil) // the real sleep would wait 500 ms
	wantCode(t, err, CodeAborted)
	if elapsed := time.Since(start); elapsed > 400*time.Millisecond {
		t.Errorf("returned after %v, want immediately on cancel", elapsed)
	}
	if mock.count() != 1 {
		t.Errorf("requests = %d", mock.count())
	}
}

// ---------------------------------------------------------------- 12. Memory filters

func TestMemoryFolderFilters(t *testing.T) {
	c := newTestClient(t, "private", []responder{emptyPage(), emptyPage(), emptyPage(), emptyPage(), emptyPage(), emptyPage()})
	calls := []func() error{
		func() error { _, err := c.Memory.ListAssets(bg, &ListAssetsParams{Root: true}); return err },
		func() error { _, err := c.Memory.ListFolders(bg, &ListFoldersParams{ParentID: "root"}); return err },
		func() error { _, err := c.Memory.ListFolders(bg, &ListFoldersParams{Root: true}); return err },
		func() error { _, err := c.Memory.ListDocuments(bg, &ListDocumentsParams{}); return err },
		func() error { _, err := c.Memory.ListDocuments(bg, &ListDocumentsParams{Tags: []string{}}); return err },
		func() error {
			_, err := c.Memory.ListDocuments(bg, &ListDocumentsParams{FolderID: "f1", Tags: []string{"a", "b"}, Kind: KindRules})
			return err
		},
	}
	for _, call := range calls {
		if err := call(); err != nil {
			t.Fatal(err)
		}
	}
	for i, want := range []string{"folderId=root", "parentId=root", "parentId=root", "", "", "folderId=f1&tag=a&tag=b&kind=rules"} {
		if got := rawQuery(t, c.mock.get(i)); got != want {
			t.Errorf("request %d query = %q, want %q", i, got, want)
		}
	}
	_, err := c.Memory.ListDocuments(bg, &ListDocumentsParams{FolderID: "f1", Root: true})
	wantCode(t, err, CodeInvalidArgument)
}

func TestMemoryDownloadPreviewParameters(t *testing.T) {
	c := newTestClient(t, "private", []responder{respond(200, nil, []byte("a")), respond(200, nil, []byte("b")), respond(200, nil, []byte("c"))})
	if _, err := c.Memory.DownloadAsset(bg, "a1", &DownloadAssetParams{Width: 256}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Memory.DownloadAsset(bg, "a1", &DownloadAssetParams{Preview: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Memory.DownloadAsset(bg, "a1", &DownloadAssetParams{RevisionID: "r1"}); err != nil {
		t.Fatal(err)
	}
	for i, want := range []string{"preview=true&w=256", "preview=true", "revisionId=r1"} {
		if got := rawQuery(t, c.mock.get(i)); got != want {
			t.Errorf("request %d query = %q, want %q", i, got, want)
		}
	}
	_, err := c.Memory.DownloadAsset(bg, "a1", &DownloadAssetParams{Width: -1})
	wantCode(t, err, CodeInvalidArgument)
}

// ---------------------------------------------------------------- 13. Locale export

func TestLocaleExportQuery(t *testing.T) {
	c := newTestClient(t, "private", []responder{fixtureResponse(t, 200, "locale/export-json.json"), fixtureResponse(t, 200, "locale/export-json.json")})
	if _, err := c.Locale.Export(bg, "scope_1", &ExportParams{Languages: []string{"tr"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Locale.Export(bg, "scope_1", &ExportParams{Languages: []string{"en", "pt-br"}, Status: []LocaleKeyStatus{StatusApproved}}); err != nil {
		t.Fatal(err)
	}
	for i, want := range []string{"scopeId=scope_1&format=json&languages=tr", "scopeId=scope_1&format=json&languages=en%2Cpt-br&status=approved"} {
		got := rawQuery(t, c.mock.get(i))
		if got != want {
			t.Errorf("request %d query = %q, want %q", i, got, want)
		}
		if values, _ := url.ParseQuery(got); values.Has("language") {
			t.Error("sent the legacy language parameter")
		}
	}
}

func TestLocaleExportValidation(t *testing.T) {
	c := newTestClient(t, "private", nil)
	_, err := c.Locale.Export(bg, "", nil)
	wantCode(t, err, CodeInvalidArgument)
	_, err = c.Locale.Export(bg, "s", &ExportParams{Languages: []string{"en,tr"}})
	wantCode(t, err, CodeInvalidArgument)
	_, err = c.Locale.Export(bg, "s", &ExportParams{Status: []LocaleKeyStatus{""}})
	wantCode(t, err, CodeInvalidArgument)
	if c.mock.count() != 0 {
		t.Errorf("requests = %d", c.mock.count())
	}
}

// ---------------------------------------------------------------- 14. Content-Disposition

func TestParseFilename(t *testing.T) {
	for in, want := range map[string]string{
		"attachment; filename*=UTF-8''%C3%B6deme%20plan.pdf":             "ödeme plan.pdf",
		`attachment; filename="report \"q3\".csv"`:                       `report "q3".csv`,
		"inline; filename=logo.png":                                      "logo.png",
		`attachment; filename="fallback.txt"; filename*=UTF-8''real.txt`: "real.txt",
		`attachment; filename*=UTF-8''%FF%FE; filename="safe.txt"`:       "safe.txt",
		"attachment": "",
		"":           "",
	} {
		if got := parseFilename(in); got != want {
			t.Errorf("parseFilename(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestQueryEscapingMatchesEncodeURIComponent(t *testing.T) {
	for in, want := range map[string]string{
		"a b":           "a%20b",
		"a+b&c=d/e?f#g": "a%2Bb%26c%3Dd%2Fe%3Ff%23g",
		"-_.!~*'()":     "-_.!~*'()",
		"ç":             "%C3%A7",
		"en,tr":         "en%2Ctr",
		"5:rules":       "5%3Arules",
		"abcXYZ0129":    "abcXYZ0129",
		"eyJrZXkiOi0=":  "eyJrZXkiOi0%3D",
		"– dash.md":     "%E2%80%93%20dash.md",
	} {
		if got := escape(in); got != want {
			t.Errorf("escape(%q) = %q, want %q", in, got, want)
		}
	}
}
