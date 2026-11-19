package nulldull

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"iter"
	"net/url"
	"reflect"
	"testing"
	"time"
)

// args gives typed access to a case's canonical JSON arguments.
type args []json.RawMessage

func (a args) str(i int) string {
	if i >= len(a) {
		return ""
	}
	var s string
	_ = json.Unmarshal(a[i], &s)
	return s
}

func (a args) obj(i int) opts {
	out := opts{}
	if i < len(a) {
		_ = json.Unmarshal(a[i], &out)
	}
	return out
}

type opts map[string]any

func (o opts) str(name string) string {
	s, _ := o[name].(string)
	return s
}

func (o opts) num(name string) int {
	f, _ := o[name].(float64)
	return int(f)
}

func (o opts) boolean(name string) bool {
	b, _ := o[name].(bool)
	return b
}

func (o opts) strs(name string) []string {
	list, _ := o[name].([]any)
	out := make([]string, 0, len(list))
	for _, item := range list {
		s, _ := item.(string)
		out = append(out, s)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// folder maps a canonical folder filter: null means root, absent means none.
func (o opts) folder(name string) (string, bool) {
	value, present := o[name]
	if !present {
		return "", false
	}
	if value == nil {
		return "", true
	}
	s, _ := value.(string)
	return s, false
}

func collect[T any](seq iter.Seq2[T, error]) ([]T, error) {
	items := []T{}
	for item, err := range seq {
		if err != nil {
			return items, err
		}
		items = append(items, item)
	}
	return items, nil
}

func listDocumentsParams(o opts) *ListDocumentsParams {
	folder, root := o.folder("folderId")
	return &ListDocumentsParams{
		ScopeID: o.str("scopeId"), FolderID: folder, Root: root, Tags: o.strs("tags"),
		Kind: FileKind(o.str("kind")), Lifecycle: FileLifecycle(o.str("lifecycle")), After: o.str("after"),
	}
}

func searchParams(o opts) *SearchParams {
	return &SearchParams{ScopeID: o.str("scopeId"), Tags: o.strs("tags"), Kind: FileKind(o.str("kind")),
		Lifecycle: FileLifecycle(o.str("lifecycle")), After: o.str("after")}
}

func listAssetsParams(o opts) *ListAssetsParams {
	folder, root := o.folder("folderId")
	return &ListAssetsParams{ScopeID: o.str("scopeId"), FolderID: folder, Root: root, Q: o.str("q"), Tags: o.strs("tags"), After: o.str("after")}
}

func listPagesParams(o opts) *ListPagesParams {
	return &ListPagesParams{Locale: o.str("locale"), Q: o.str("q"), FolderID: o.str("folderId"), Limit: o.num("limit"), After: o.str("after")}
}

// invoke maps a canonical method name and JSON arguments to the Go API.
func invoke(ctx context.Context, c *Client, method string, a args) (any, error) {
	switch method {
	case "grid.listPages":
		return c.Grid.ListPages(ctx, a.str(0), listPagesParams(a.obj(1)))
	case "grid.iteratePages":
		return collect(c.Grid.IteratePages(ctx, a.str(0), listPagesParams(a.obj(1))))
	case "grid.getPage":
		return c.Grid.GetPage(ctx, a.str(0), a.str(1), &GetPageParams{Locale: a.obj(2).str("locale")})
	case "grid.downloadAsset":
		return c.Grid.DownloadAsset(ctx, a.str(0))
	case "memory.listScopes":
		return c.Memory.ListScopes(ctx, &CursorParams{After: a.obj(0).str("after")})
	case "memory.iterateScopes":
		return collect(c.Memory.IterateScopes(ctx, &CursorParams{After: a.obj(0).str("after")}))
	case "memory.listFolders", "memory.iterateFolders":
		o := a.obj(0)
		parent, root := o.folder("parentId")
		p := &ListFoldersParams{ScopeID: o.str("scopeId"), ParentID: parent, Root: root, After: o.str("after")}
		if method == "memory.listFolders" {
			return c.Memory.ListFolders(ctx, p)
		}
		return collect(c.Memory.IterateFolders(ctx, p))
	case "memory.getFolder":
		return c.Memory.GetFolder(ctx, a.str(0))
	case "memory.listDocuments":
		return c.Memory.ListDocuments(ctx, listDocumentsParams(a.obj(0)))
	case "memory.iterateDocuments":
		return collect(c.Memory.IterateDocuments(ctx, listDocumentsParams(a.obj(0))))
	case "memory.getDocument":
		return c.Memory.GetDocument(ctx, a.str(0))
	case "memory.resolveLink":
		return c.Memory.ResolveLink(ctx, a.str(0), a.str(1))
	case "memory.search":
		return c.Memory.Search(ctx, a.str(0), searchParams(a.obj(1)))
	case "memory.iterateSearch":
		return collect(c.Memory.IterateSearch(ctx, a.str(0), searchParams(a.obj(1))))
	case "memory.listTags", "memory.iterateTags":
		o := a.obj(0)
		p := &ListTagsParams{ScopeID: o.str("scopeId"), Q: o.str("q"), After: o.str("after")}
		if method == "memory.listTags" {
			return c.Memory.ListTags(ctx, p)
		}
		return collect(c.Memory.IterateTags(ctx, p))
	case "memory.listAssets":
		return c.Memory.ListAssets(ctx, listAssetsParams(a.obj(0)))
	case "memory.iterateAssets":
		return collect(c.Memory.IterateAssets(ctx, listAssetsParams(a.obj(0))))
	case "memory.getAsset":
		return c.Memory.GetAsset(ctx, a.str(0), &GetAssetParams{RevisionID: a.obj(1).str("revisionId")})
	case "memory.listAssetVersions":
		return c.Memory.ListAssetVersions(ctx, a.str(0), &CursorParams{After: a.obj(1).str("after")})
	case "memory.iterateAssetVersions":
		return collect(c.Memory.IterateAssetVersions(ctx, a.str(0), &CursorParams{After: a.obj(1).str("after")}))
	case "memory.downloadAsset":
		o := a.obj(1)
		return c.Memory.DownloadAsset(ctx, a.str(0), &DownloadAssetParams{RevisionID: o.str("revisionId"), Preview: o.boolean("preview"), Width: o.num("width")})
	case "locale.listFormats":
		return c.Locale.ListFormats(ctx)
	case "locale.export":
		o := a.obj(1)
		var statuses []LocaleKeyStatus
		for _, s := range o.strs("status") {
			statuses = append(statuses, LocaleKeyStatus(s))
		}
		return c.Locale.Export(ctx, a.str(0), &ExportParams{Format: o.str("format"), Languages: o.strs("languages"), Status: statuses, Basename: o.str("basename")})
	}
	return nil, fmt.Errorf("conformance: unmapped method %s", method)
}

func TestConformance(t *testing.T) {
	m := loadManifest(t)
	if len(m.Cases) == 0 {
		t.Fatal("manifest has no cases")
	}
	for _, tc := range m.Cases {
		t.Run(tc.ID, func(t *testing.T) {
			responders := make([]responder, len(tc.Exchanges))
			for i, exchange := range tc.Exchanges {
				responders[i] = specResponse(t, exchange.Response)
			}
			client := newTestClient(t, tc.Key, responders)
			result, err := invoke(context.Background(), client.Client, tc.Call.Method, tc.Call.Args)
			expect := tc.Expect

			// Requests: order, method, origin, path, query multimap and Authorization.
			attempts := len(tc.Exchanges)
			if expect.Attempts != nil {
				attempts = *expect.Attempts
			}
			if got := client.mock.count(); got != attempts {
				t.Fatalf("sent %d requests, want %d (err: %v)", got, attempts, err)
			}
			key := m.Config.PrivateKey
			if tc.Key == "public" {
				key = m.Config.PublicKey
			}
			for i := 0; i < attempts; i++ {
				got, want := client.mock.get(i), tc.Exchanges[i].Request
				u, _ := url.Parse(got.URL)
				if got.Method != want.Method {
					t.Errorf("request %d method = %s, want %s", i, got.Method, want.Method)
				}
				if origin := u.Scheme + "://" + u.Host; origin != m.Config.BaseURL {
					t.Errorf("request %d origin = %s, want %s", i, origin, m.Config.BaseURL)
				}
				if u.Path != want.Path {
					t.Errorf("request %d path = %s, want %s", i, u.Path, want.Path)
				}
				gotQuery := map[string][]string(u.Query())
				if len(gotQuery) != 0 || len(want.Query) != 0 {
					if !reflect.DeepEqual(gotQuery, want.Query) {
						t.Errorf("request %d query = %v, want %v", i, gotQuery, want.Query)
					}
				}
				if auth := got.Header.Get("Authorization"); auth != "Bearer "+key {
					t.Errorf("request %d has the wrong Authorization header", i)
				}
			}
			if expect.Sleeps != nil {
				want := make([]time.Duration, len(expect.Sleeps))
				for i, ms := range expect.Sleeps {
					want[i] = time.Duration(ms) * time.Millisecond
				}
				if got := client.slept(); !(len(got) == 0 && len(want) == 0) && !reflect.DeepEqual(got, want) {
					t.Errorf("sleeps = %v, want %v", got, want)
				}
			}

			if expect.Error != nil {
				checkError(t, err, expect.Error)
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			generic := toGeneric(t, result)
			if expect.ResultFile != nil {
				got := without(toGeneric(t, result), expect.Except)
				want := without(fixtureValue(t, *expect.ResultFile), expect.Except)
				if !jsonEqual(got, want) {
					t.Errorf("result differs from %s\n got: %s\nwant: %s", *expect.ResultFile, mustJSON(got), mustJSON(want))
				}
			}
			if expect.ItemCount != nil {
				items, _ := generic.([]any)
				if len(items) != *expect.ItemCount {
					t.Errorf("iterated %d items, want %d", len(items), *expect.ItemCount)
				}
			}
			for _, check := range expect.Checks {
				if got := at(generic, check.Path); !jsonEqual(got, check.Equals) {
					t.Errorf("%s = %v, want %v", check.Path, got, check.Equals)
				}
			}
			if want := expect.Download; want != nil {
				d, ok := result.(*Download)
				if !ok {
					t.Fatalf("result is %T, want *Download", result)
				}
				if d.ContentType != deref(want.ContentType) {
					t.Errorf("contentType = %q, want %q", d.ContentType, deref(want.ContentType))
				}
				if d.Filename != deref(want.Filename) {
					t.Errorf("filename = %q, want %q", d.Filename, deref(want.Filename))
				}
				if d.Size != want.Size || len(d.Bytes) != want.Size {
					t.Errorf("size = %d (%d bytes), want %d", d.Size, len(d.Bytes), want.Size)
				}
				if got := base64.StdEncoding.EncodeToString(d.Bytes); got != want.BytesBase64 {
					t.Errorf("bytes = %s, want %s", got, want.BytesBase64)
				}
			}
		})
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// checkError compares the listed Error fields. JSON null means "" for
// strings and nil for RetryAfter and Body.
func checkError(t *testing.T, err error, want map[string]any) {
	t.Helper()
	e := asError(t, err)
	for field, value := range want {
		switch field {
		case "status":
			if float64(e.Status) != value.(float64) {
				t.Errorf("status = %d, want %v", e.Status, value)
			}
		case "code", "message", "detail", "requestId":
			got := map[string]string{"code": e.Code, "message": e.Message, "detail": e.Detail, "requestId": e.RequestID}[field]
			wantString, _ := value.(string)
			if got != wantString {
				t.Errorf("%s = %q, want %q", field, got, wantString)
			}
		case "retryAfter":
			if value == nil {
				if e.RetryAfter != nil {
					t.Errorf("retryAfter = %d, want nil", *e.RetryAfter)
				}
			} else if e.RetryAfter == nil || float64(*e.RetryAfter) != value.(float64) {
				t.Errorf("retryAfter = %v, want %v", e.RetryAfter, value)
			}
		case "body":
			if value == nil {
				if e.Body != nil {
					t.Errorf("body = %v, want nil", e.Body)
				}
				continue
			}
			for k, v := range value.(map[string]any) {
				if !jsonEqual(e.Body[k], v) {
					t.Errorf("body.%s = %v, want %v", k, e.Body[k], v)
				}
			}
		default:
			t.Errorf("unknown error field %q in manifest", field)
		}
	}
}
