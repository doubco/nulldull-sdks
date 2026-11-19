package nulldull

import (
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

// DefaultBaseURL is the NullDull API used when WithBaseURL is not given.
const DefaultBaseURL = "https://nulldull.com"

var (
	apiKeyPattern      = regexp.MustCompile(`^nd_(pub|sec)_[a-f0-9]{64}$`)
	workspaceIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,128}$`)
)

// KeyKind tells a public key from a private one.
type KeyKind string

// Key kinds.
const (
	// PublicKey (nd_pub_…) can read published Grid content. Safe in apps.
	PublicKey KeyKind = "public"
	// PrivateKey (nd_sec_…) can also read Memory and Locale. Servers only.
	PrivateKey KeyKind = "private"
)

// Client reads NullDull with a workspace API key. It holds only its
// configuration and is safe for concurrent use.
type Client struct {
	// Grid reads published Grid content.
	Grid *GridService
	// Memory reads Memory documents, folders, tags and assets.
	Memory *MemoryService
	// Locale exports Locale catalogs.
	Locale *LocaleService

	baseURL     string
	workspaceID string
	keyKind     KeyKind
}

type config struct {
	baseURL     string
	workspaceID string
	timeout     time.Duration
	maxRetries  int
	httpClient  *http.Client
	userAgent   string
	sleep       SleepFunc
	err         *Error
}

// Option configures a Client.
type Option func(*config)

// WithWorkspaceID sets the workspace ID that Memory and Locale calls need. A
// key cannot look up its own workspace; owners and admins see the ID in the app.
func WithWorkspaceID(id string) Option {
	return func(c *config) { c.workspaceID = id }
}

// WithBaseURL points the client at another NullDull environment. It must be
// an http or https URL without user info, query or fragment. Default
// https://nulldull.com.
func WithBaseURL(baseURL string) Option {
	return func(c *config) { c.baseURL = baseURL }
}

// WithHTTPClient sets the HTTP client, for example to add a proxy or mock
// the transport in tests. The SDK uses a shallow copy that never follows
// redirects and has no cookie jar.
func WithHTTPClient(client *http.Client) Option {
	return func(c *config) {
		if client == nil {
			c.err = invalidArgument("WithHTTPClient needs a non-nil *http.Client.")
		}
		c.httpClient = client
	}
}

// WithTimeout sets the timeout of each attempt (retries get their own).
// Default 30 seconds; 0 disables it.
func WithTimeout(timeout time.Duration) Option {
	return func(c *config) {
		if timeout < 0 {
			c.err = invalidArgument("timeout must be zero or positive.")
		}
		c.timeout = timeout
	}
}

// WithMaxRetries sets how many times a request is retried after the first
// attempt on 429, 502, 503, 504 and network errors. Default 2; 0 disables
// retries.
func WithMaxRetries(n int) Option {
	return func(c *config) {
		if n < 0 {
			c.err = invalidArgument("maxRetries must be zero or more.")
		}
		c.maxRetries = n
	}
}

// WithUserAgent appends a suffix to the User-Agent, which is sent as
// "nulldull-sdk-go/<Version> <suffix>".
func WithUserAgent(suffix string) Option {
	return func(c *config) { c.userAgent = suffix }
}

// WithSleep replaces the wait between retries. Tests use it to record the
// requested delays without waiting. The function must return early with
// ctx.Err() when ctx is done.
func WithSleep(sleep SleepFunc) Option {
	return func(c *config) {
		if sleep == nil {
			c.err = invalidArgument("WithSleep needs a non-nil function.")
		}
		c.sleep = sleep
	}
}

// New creates a client for a workspace API key: public (nd_pub_…) or
// private (nd_sec_…). Invalid options return an *Error with code
// INVALID_ARGUMENT.
func New(apiKey string, opts ...Option) (*Client, error) {
	cfg := config{baseURL: DefaultBaseURL, timeout: 30 * time.Second, maxRetries: 2, sleep: defaultSleep}
	for _, opt := range opts {
		opt(&cfg)
		if cfg.err != nil {
			return nil, cfg.err
		}
	}
	if !apiKeyPattern.MatchString(apiKey) {
		return nil, invalidArgument("apiKey must be a NullDull workspace API key (nd_pub_… or nd_sec_…).")
	}
	if cfg.workspaceID != "" && !workspaceIDPattern.MatchString(cfg.workspaceID) {
		return nil, invalidArgument("workspaceId must be 1–128 letters, numbers, hyphens or underscores.")
	}
	baseURL, origin, err := normalizeBaseURL(cfg.baseURL)
	if err != nil {
		return nil, err
	}

	httpClient := &http.Client{}
	if cfg.httpClient != nil {
		copied := *cfg.httpClient
		httpClient = &copied
	}
	// Never follow redirects: a 3xx is returned as an error so the key is
	// not sent to another origin. Never send cookies.
	httpClient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	httpClient.Jar = nil

	userAgent := "nulldull-sdk-go/" + Version
	if cfg.userAgent != "" {
		userAgent += " " + cfg.userAgent
	}
	t := &transport{
		apiKey:     apiKey,
		baseURL:    baseURL,
		timeout:    cfg.timeout,
		maxRetries: cfg.maxRetries,
		client:     httpClient,
		userAgent:  userAgent,
		sleep:      cfg.sleep,
		now:        time.Now,
	}
	kind := PrivateKey
	if strings.HasPrefix(apiKey, "nd_pub_") {
		kind = PublicKey
	}
	g := guard{workspaceID: cfg.workspaceID, public: kind == PublicKey}
	c := &Client{baseURL: baseURL, workspaceID: cfg.workspaceID, keyKind: kind}
	c.Grid = &GridService{t: t, origin: origin}
	if kind == PublicKey {
		c.Grid.publicKey = apiKey
	}
	c.Memory = &MemoryService{t: t, guard: g}
	c.Locale = &LocaleService{t: t, guard: g}
	return c, nil
}

// BaseURL returns the normalized base URL, without a trailing slash.
func (c *Client) BaseURL() string { return c.baseURL }

// WorkspaceID returns the configured workspace ID, or "".
func (c *Client) WorkspaceID() string { return c.workspaceID }

// KeyKind reports whether the client uses a public or a private key.
func (c *Client) KeyKind() KeyKind { return c.keyKind }

// normalizeBaseURL validates a base URL and returns it without one trailing
// slash, plus its origin (scheme://host[:port], default ports removed).
func normalizeBaseURL(value string) (string, *url.URL, error) {
	bad := invalidArgument("baseUrl must be an HTTP(S) URL without credentials, query or fragment.")
	u, err := url.Parse(value)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil ||
		u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || strings.ContainsAny(value, "?#") || u.Opaque != "" {
		return "", nil, bad
	}
	origin := originOf(u)
	path := u.EscapedPath()
	if path == "" {
		path = "/"
	}
	return strings.TrimSuffix(origin.String()+path, "/"), origin, nil
}

// originOf returns scheme://host[:port] with a lowercase host and without a
// default port, like the WHATWG URL origin.
func originOf(u *url.URL) *url.URL {
	scheme := strings.ToLower(u.Scheme)
	host := strings.ToLower(u.Hostname())
	port := u.Port()
	if (scheme == "https" && port == "443") || (scheme == "http" && port == "80") {
		port = ""
	}
	if strings.Contains(host, ":") {
		host = "[" + host + "]"
	}
	if port != "" {
		host += ":" + port
	}
	return &url.URL{Scheme: scheme, Host: host}
}

func sameOrigin(a, b *url.URL) bool {
	return a.Scheme == b.Scheme && a.Host == b.Host
}
