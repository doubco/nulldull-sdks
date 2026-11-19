package nulldull

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// fixturesDir is the shared conformance data at the repository root.
var fixturesDir = filepath.Join("..", "fixtures")

type exchangeSpec struct {
	Request struct {
		Method string              `json:"method"`
		Path   string              `json:"path"`
		Query  map[string][]string `json:"query"`
	} `json:"request"`
	Response responseSpec `json:"response"`
}

type responseSpec struct {
	Status     int               `json:"status"`
	Headers    map[string]string `json:"headers"`
	BodyFile   *string           `json:"bodyFile"`
	Body       *string           `json:"body"`
	BodyBase64 *string           `json:"bodyBase64"`
}

type checkSpec struct {
	Path   string `json:"path"`
	Equals any    `json:"equals"`
}

type caseSpec struct {
	ID   string `json:"id"`
	Key  string `json:"key"`
	Call struct {
		Method string            `json:"method"`
		Args   []json.RawMessage `json:"args"`
	} `json:"call"`
	Exchanges []exchangeSpec `json:"exchanges"`
	Expect    struct {
		ResultFile *string     `json:"resultFile"`
		Except     []string    `json:"except"`
		Checks     []checkSpec `json:"checks"`
		ItemCount  *int        `json:"itemCount"`
		Download   *struct {
			ContentType *string `json:"contentType"`
			Filename    *string `json:"filename"`
			Size        int     `json:"size"`
			BytesBase64 string  `json:"bytesBase64"`
		} `json:"download"`
		Error    map[string]any `json:"error"`
		Attempts *int           `json:"attempts"`
		Sleeps   []int          `json:"sleeps"`
	} `json:"expect"`
}

type manifestSpec struct {
	Config struct {
		BaseURL     string `json:"baseUrl"`
		PublicKey   string `json:"publicKey"`
		PrivateKey  string `json:"privateKey"`
		WorkspaceID string `json:"workspaceId"`
	} `json:"config"`
	Cases []caseSpec `json:"cases"`
}

func readFixture(t testing.TB, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(fixturesDir, filepath.FromSlash(name)))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return data
}

func fixtureValue(t testing.TB, name string) any {
	t.Helper()
	var value any
	if err := json.Unmarshal(readFixture(t, name), &value); err != nil {
		t.Fatalf("decode fixture %s: %v", name, err)
	}
	return value
}

var (
	manifestOnce sync.Once
	manifestData manifestSpec
	manifestErr  error
)

func loadManifest(t testing.TB) manifestSpec {
	t.Helper()
	manifestOnce.Do(func() {
		data, err := os.ReadFile(filepath.Join(fixturesDir, "manifest.json"))
		if err != nil {
			manifestErr = err
			return
		}
		manifestErr = json.Unmarshal(data, &manifestData)
	})
	if manifestErr != nil {
		t.Fatalf("load manifest: %v", manifestErr)
	}
	return manifestData
}

// ---------------------------------------------------------------- mock transport

type recorded struct {
	Method string
	URL    string
	Header http.Header
	req    *http.Request
}

type responder func(*http.Request) (*http.Response, error)

// mockTransport answers queued responders in order and records every request.
type mockTransport struct {
	mu       sync.Mutex
	queue    []responder
	requests []recorded
}

func (m *mockTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	m.mu.Lock()
	m.requests = append(m.requests, recorded{Method: req.Method, URL: req.URL.String(), Header: req.Header.Clone(), req: req})
	if len(m.queue) == 0 {
		m.mu.Unlock()
		return nil, fmt.Errorf("unexpected request: %s %s", req.Method, req.URL.Path)
	}
	next := m.queue[0]
	m.queue = m.queue[1:]
	m.mu.Unlock()
	return next(req)
}

func (m *mockTransport) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.requests)
}

func (m *mockTransport) get(i int) recorded {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.requests[i]
}

func respond(status int, headers map[string]string, body []byte) responder {
	return func(req *http.Request) (*http.Response, error) {
		h := http.Header{}
		for k, v := range headers {
			h.Set(k, v)
		}
		return &http.Response{
			Status:        strconv.Itoa(status) + " " + http.StatusText(status),
			StatusCode:    status,
			Header:        h,
			Body:          io.NopCloser(bytes.NewReader(body)),
			ContentLength: int64(len(body)),
			Request:       req,
			Proto:         "HTTP/1.1",
			ProtoMajor:    1,
			ProtoMinor:    1,
		}, nil
	}
}

func jsonResponse(status int, body any, headers ...string) responder {
	data, err := json.Marshal(body)
	if err != nil {
		panic(err)
	}
	h := map[string]string{"content-type": "application/json"}
	for i := 0; i+1 < len(headers); i += 2 {
		h[headers[i]] = headers[i+1]
	}
	return respond(status, h, data)
}

func fixtureResponse(t testing.TB, status int, name string) responder {
	return respond(status, map[string]string{"content-type": "application/json"}, readFixture(t, name))
}

func failWith(err error) responder {
	return func(*http.Request) (*http.Response, error) { return nil, err }
}

func specResponse(t testing.TB, spec responseSpec) responder {
	var body []byte
	switch {
	case spec.BodyFile != nil:
		body = readFixture(t, *spec.BodyFile)
	case spec.BodyBase64 != nil:
		decoded, err := base64.StdEncoding.DecodeString(*spec.BodyBase64)
		if err != nil {
			t.Fatalf("bodyBase64: %v", err)
		}
		body = decoded
	case spec.Body != nil:
		body = []byte(*spec.Body)
	}
	return respond(spec.Status, spec.Headers, body)
}

type testClient struct {
	*Client
	mock   *mockTransport
	mu     sync.Mutex
	sleeps []time.Duration
}

func (c *testClient) slept() []time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]time.Duration(nil), c.sleeps...)
}

// newTestClient builds a client from the manifest config ("public" or
// "private" key) over a mock transport. Sleeps are recorded, not waited.
func newTestClient(t testing.TB, kind string, responders []responder, opts ...Option) *testClient {
	t.Helper()
	m := loadManifest(t)
	key := m.Config.PrivateKey
	if kind == "public" {
		key = m.Config.PublicKey
	}
	tc := &testClient{mock: &mockTransport{queue: responders}}
	base := []Option{
		WithBaseURL(m.Config.BaseURL),
		WithWorkspaceID(m.Config.WorkspaceID),
		WithHTTPClient(&http.Client{Transport: tc.mock}),
		WithSleep(func(ctx context.Context, d time.Duration) error {
			tc.mu.Lock()
			tc.sleeps = append(tc.sleeps, d)
			tc.mu.Unlock()
			return ctx.Err()
		}),
	}
	client, err := New(key, append(base, opts...)...)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	tc.Client = client
	return tc
}

// ---------------------------------------------------------------- assertions

func asError(t testing.TB, err error) *Error {
	t.Helper()
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("expected *nulldull.Error, got %T: %v", err, err)
	}
	return e
}

func wantCode(t testing.TB, err error, code string) *Error {
	t.Helper()
	e := asError(t, err)
	if e.Code != code {
		t.Fatalf("code = %q, want %q (message %q)", e.Code, code, e.Message)
	}
	return e
}

// toGeneric re-encodes a value as plain JSON values (maps, slices, float64).
func toGeneric(t testing.TB, value any) any {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out any
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return out
}

func segmentIndex(part string) (int, bool) {
	n, err := strconv.Atoi(part)
	return n, err == nil
}

func at(value any, path string) any {
	current := value
	for _, part := range strings.Split(path, ".") {
		switch node := current.(type) {
		case map[string]any:
			current = node[part]
		case []any:
			i, ok := segmentIndex(part)
			if !ok || i < 0 || i >= len(node) {
				return nil
			}
			current = node[i]
		default:
			return nil
		}
	}
	return current
}

func without(value any, paths []string) any {
	for _, path := range paths {
		parts := strings.Split(path, ".")
		parent := value
		if len(parts) > 1 {
			parent = at(value, strings.Join(parts[:len(parts)-1], "."))
		}
		last := parts[len(parts)-1]
		switch node := parent.(type) {
		case map[string]any:
			delete(node, last)
		case []any:
			if i, ok := segmentIndex(last); ok && i >= 0 && i < len(node) {
				node[i] = nil
			}
		}
	}
	return value
}

// jsonEqual compares JSON values, treating a missing object field as null:
// Go's omitempty pointers drop null optional fields.
func jsonEqual(a, b any) bool {
	switch x := a.(type) {
	case map[string]any:
		y, ok := b.(map[string]any)
		if !ok {
			return false
		}
		for k, v := range x {
			if !jsonEqual(v, y[k]) {
				return false
			}
		}
		for k, v := range y {
			if _, seen := x[k]; !seen && v != nil {
				return false
			}
		}
		return true
	case []any:
		y, ok := b.([]any)
		if !ok || len(x) != len(y) {
			return false
		}
		for i := range x {
			if !jsonEqual(x[i], y[i]) {
				return false
			}
		}
		return true
	default:
		return reflect.DeepEqual(a, b)
	}
}

func mustJSON(value any) string {
	data, _ := json.MarshalIndent(value, "", "  ")
	return string(data)
}
