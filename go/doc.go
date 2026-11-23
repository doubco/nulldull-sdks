// Package nulldull is the official Go SDK for NullDull. It reads NullDull
// with workspace API keys:
//
//   - Grid: published pages, covers and assets for your website or app.
//   - Memory: read-only documents, folders, search, tags and assets.
//   - Locale: export translation catalogs at build time.
//
// Early access: version 0.1.0 may change before 1.0. The SDK only reads data.
// It uses the standard library only.
//
// # Keys
//
// Owners and admins create keys in the NullDull app under Workspace settings
// → API keys. A public key (nd_pub_…, scope grid:published) is safe to ship
// in apps. A private key (nd_sec_…, scopes grid:published, memory:read,
// locale:read) belongs on servers and in CI only. Memory and Locale also need
// the workspace ID, because a key cannot look up its own workspace.
//
// # Client
//
//	client, err := nulldull.New(os.Getenv("NULLDULL_PRIVATE_KEY"),
//		nulldull.WithWorkspaceID(os.Getenv("NULLDULL_WORKSPACE_ID")))
//
// A Client holds only configuration and is safe for concurrent use. Every
// method takes a context.Context; cancelling it returns an ABORTED error.
// Each attempt also has its own timeout (WithTimeout, default 30 seconds).
//
// # Pagination
//
// ListX methods return one page; pass NextCursor back as After until it is
// nil. IterateX methods return an iter.Seq2 over the items of every page,
// fetched lazily:
//
//	for doc, err := range client.Memory.IterateDocuments(ctx, nil) {
//		if err != nil {
//			return err
//		}
//		fmt.Println(doc.Name)
//	}
//
// # Errors
//
// Every failure is an *Error with Status (0 for client-side errors), Code,
// Message, Detail, RequestID, RetryAfter, Reason, RenewsAt and Body. Use
// errors.As to read it. IsPublicRequestsPaused reports the 429 that Grid
// delivery returns while a Free workspace has used its monthly public requests.
//
// # Retries
//
// Requests are retried up to 2 times (WithMaxRetries) on 429, 502, 503, 504
// and network errors: after Retry-After when it is 30 seconds or less,
// otherwise after 500 ms and then 1 s. A longer Retry-After is returned at
// once with RetryAfter set. Timeouts are never retried. Redirects are never
// followed, so the key is never sent to another origin.
//
// The full contract shared by every NullDull SDK is SPEC.md at
// https://github.com/doubco/nulldull-sdks.
package nulldull
