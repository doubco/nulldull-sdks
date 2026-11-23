package nulldull

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// maxRetryAfterSeconds: longer Retry-After values are returned as errors
// instead of waited for (SPEC.md section 6).
const maxRetryAfterSeconds = 30

func retryable(status int) bool {
	return status == 429 || status == 502 || status == 503 || status == 504
}

// backoff is the delay before retry n (1-based): 500 ms, then 1000 ms, …
func backoff(retry int) time.Duration {
	return 500 * time.Millisecond << (retry - 1)
}

// SleepFunc waits for d, or returns ctx.Err() when ctx is done first.
type SleepFunc func(ctx context.Context, d time.Duration) error

func defaultSleep(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func aborted(cause error) *Error {
	return clientError(CodeAborted, "The request was cancelled.", cause)
}

// ---------------------------------------------------------------- query strings

type param struct{ name, value string }

// query is an ordered list of parameters. Lists repeat the key.
type query []param

// set adds a parameter that is always sent.
func (q *query) set(name, value string) { *q = append(*q, param{name, value}) }

// opt adds a parameter only when value is not empty.
func (q *query) opt(name, value string) {
	if value != "" {
		q.set(name, value)
	}
}

func (q query) encode() string {
	if len(q) == 0 {
		return ""
	}
	var b strings.Builder
	for i, p := range q {
		if i == 0 {
			b.WriteByte('?')
		} else {
			b.WriteByte('&')
		}
		b.WriteString(escape(p.name))
		b.WriteByte('=')
		b.WriteString(escape(p.value))
	}
	return b.String()
}

// escape percent-encodes like JavaScript's encodeURIComponent.
func escape(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9' || strings.IndexByte("-_.!~*'()", c) >= 0 {
			b.WriteByte(c)
		} else {
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&15])
		}
	}
	return b.String()
}

// ---------------------------------------------------------------- header parsing

func header(h http.Header, name string) string { return h.Get(name) }

func requestID(h http.Header) string {
	if id := header(h, "X-Request-Id"); id != "" {
		return id
	}
	return header(h, "CF-Ray")
}

// parseRetryAfter returns the seconds in a Retry-After header (delta-seconds
// or an HTTP date), or nil.
func parseRetryAfter(value string, now time.Time) *int {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	if strings.Trim(value, "0123456789") == "" {
		seconds, err := strconv.Atoi(value)
		if err != nil {
			seconds = int(^uint(0) >> 1) // absurdly large: never waited for
		}
		return &seconds
	}
	date, err := http.ParseTime(value)
	if err != nil {
		return nil
	}
	diff := date.Sub(now)
	seconds := int((diff + time.Second - 1) / time.Second)
	if diff <= 0 {
		seconds = 0
	}
	return &seconds
}

var (
	extendedFilename = regexp.MustCompile(`(?i)filename\*\s*=\s*([^']*)'[^']*'([^;]+)`)
	quotedFilename   = regexp.MustCompile(`(?i)(?:^|;)\s*filename\s*=\s*"((?:[^"\\]|\\.)*)"`)
	plainFilename    = regexp.MustCompile(`(?i)(?:^|;)\s*filename\s*=\s*([^;]+)`)
	backslashEscape  = regexp.MustCompile(`\\(.)`)
)

// parseFilename reads a file name from Content-Disposition: RFC 5987
// filename* first, then filename, else "".
func parseFilename(value string) string {
	if value == "" {
		return ""
	}
	if m := extendedFilename.FindStringSubmatch(value); m != nil && m[2] != "" {
		if decoded, err := url.PathUnescape(strings.TrimSpace(m[2])); err == nil && utf8.ValidString(decoded) {
			return decoded
		}
	}
	if m := quotedFilename.FindStringSubmatch(value); m != nil {
		return backslashEscape.ReplaceAllString(m[1], "$1")
	}
	if m := plainFilename.FindStringSubmatch(value); m != nil {
		return strings.TrimSpace(m[1])
	}
	return ""
}

// ---------------------------------------------------------------- transport

type rawResponse struct {
	status int
	header http.Header
	body   []byte
}

type transport struct {
	apiKey     string
	baseURL    string
	timeout    time.Duration
	maxRetries int
	client     *http.Client
	userAgent  string
	sleep      SleepFunc
	now        func() time.Time
}

func (t *transport) errorFrom(r *rawResponse) *Error {
	var body map[string]any
	if err := json.Unmarshal(r.body, &body); err != nil {
		body = nil // not JSON: a router page, a gateway error or an empty body
	}
	code, isString := body["code"].(string)
	if !isString {
		code = CodeRequestFailed
	}
	message, _ := body["message"].(string)
	e := newError(r.status, code, message)
	e.Detail, _ = body["detail"].(string)
	e.Reason, _ = body["reason"].(string)
	e.RenewsAt, _ = body["renewsAt"].(string)
	e.RequestID = requestID(r.header)
	e.RetryAfter = parseRetryAfter(r.header.Get("Retry-After"), t.now())
	e.Body = body
	return e
}

// getJSON GETs a JSON resource under the base URL and decodes it into out.
func (t *transport) getJSON(ctx context.Context, path string, q query, out any) error {
	r, err := t.send(ctx, t.baseURL+path+q.encode(), "application/json", true)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(r.body, out); err != nil {
		e := newError(r.status, CodeInvalidResponse, "NullDull returned a response that is not valid JSON.")
		e.RequestID = requestID(r.header)
		e.Err = err
		return e
	}
	return nil
}

// download GETs bytes from rawURL.
func (t *transport) download(ctx context.Context, rawURL string, authorize bool) (*Download, error) {
	r, err := t.send(ctx, rawURL, "*/*", authorize)
	if err != nil {
		return nil, err
	}
	return &Download{
		Bytes:       r.body,
		ContentType: r.header.Get("Content-Type"),
		Filename:    parseFilename(r.header.Get("Content-Disposition")),
		Size:        len(r.body),
	}, nil
}

func (t *transport) send(ctx context.Context, rawURL, accept string, authorize bool) (*rawResponse, error) {
	for retry := 0; ; retry++ {
		r, err := t.attempt(ctx, rawURL, accept, authorize)
		if err != nil {
			var e *Error
			if errors.As(err, &e) && e.Code == CodeNetworkError && retry < t.maxRetries {
				if err := t.wait(ctx, backoff(retry+1)); err != nil {
					return nil, err
				}
				continue
			}
			return nil, err
		}
		if r.status >= 200 && r.status < 300 {
			return r, nil
		}
		e := t.errorFrom(r)
		// A paused allowance lasts until the month renews or an upgrade: never retried.
		if !retryable(r.status) || retry >= t.maxRetries || e.PublicRequestsPaused() {
			return nil, e
		}
		delay := backoff(retry + 1)
		if e.RetryAfter != nil {
			if *e.RetryAfter > maxRetryAfterSeconds {
				return nil, e
			}
			delay = time.Duration(*e.RetryAfter) * time.Second
		}
		if err := t.wait(ctx, delay); err != nil {
			return nil, err
		}
	}
}

func (t *transport) wait(ctx context.Context, d time.Duration) error {
	if err := ctx.Err(); err != nil {
		return aborted(err)
	}
	if err := t.sleep(ctx, d); err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return aborted(ctxErr)
		}
		return aborted(err)
	}
	return nil
}

// attempt sends one request and reads the whole body within the timeout.
func (t *transport) attempt(ctx context.Context, rawURL, accept string, authorize bool) (*rawResponse, error) {
	if err := ctx.Err(); err != nil {
		return nil, aborted(err)
	}
	attemptCtx, cancel := ctx, context.CancelFunc(func() {})
	if t.timeout > 0 {
		attemptCtx, cancel = context.WithTimeout(ctx, t.timeout)
	}
	defer cancel()
	req, err := http.NewRequestWithContext(attemptCtx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, clientError(CodeInvalidArgument, "The request URL is not valid.", err)
	}
	req.Header.Set("Accept", accept)
	if authorize {
		req.Header.Set("Authorization", "Bearer "+t.apiKey)
	}
	req.Header.Set("User-Agent", t.userAgent)
	resp, err := t.client.Do(req)
	if err != nil {
		return nil, t.transportError(ctx, attemptCtx, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, t.transportError(ctx, attemptCtx, err)
	}
	return &rawResponse{status: resp.StatusCode, header: resp.Header, body: body}, nil
}

func (t *transport) transportError(ctx, attemptCtx context.Context, err error) *Error {
	if ctxErr := ctx.Err(); ctxErr != nil {
		return aborted(errors.Join(ctxErr, err))
	}
	var urlErr *url.Error
	if errors.Is(attemptCtx.Err(), context.DeadlineExceeded) || (errors.As(err, &urlErr) && urlErr.Timeout()) {
		message := "The request timed out."
		if t.timeout > 0 {
			message = "The request timed out after " + t.timeout.String() + "."
		}
		return clientError(CodeTimeout, message, err)
	}
	return clientError(CodeNetworkError, "The request could not reach NullDull.", err)
}
