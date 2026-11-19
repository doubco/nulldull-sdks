package nulldull

import "fmt"

// Client error codes. Errors with these codes have Status 0: they are raised
// by the SDK before a request is sent, or when no usable response arrived.
const (
	// CodeInvalidArgument: bad client options or method arguments.
	CodeInvalidArgument = "INVALID_ARGUMENT"
	// CodeWorkspaceRequired: a Memory or Locale call on a client without a workspace ID.
	CodeWorkspaceRequired = "WORKSPACE_REQUIRED"
	// CodePrivateKeyRequired: a Memory or Locale call with a public key.
	CodePrivateKeyRequired = "PRIVATE_KEY_REQUIRED"
	// CodeNetworkError: the transport failed (DNS, TLS, connection reset).
	CodeNetworkError = "NETWORK_ERROR"
	// CodeTimeout: one attempt took longer than the client timeout.
	CodeTimeout = "TIMEOUT"
	// CodeAborted: the caller's context was cancelled or reached its deadline.
	CodeAborted = "ABORTED"
	// CodeInvalidResponse: a 2xx body was not valid JSON, or a cursor did not advance.
	CodeInvalidResponse = "INVALID_RESPONSE"
	// CodeRequestFailed: an HTTP error whose body has no string "code" (for
	// example a plain-text 404, an HTML 502 or a redirect).
	CodeRequestFailed = "REQUEST_FAILED"
)

// Error is the one error type every SDK call returns. Use errors.As to
// inspect it:
//
//	var apiErr *nulldull.Error
//	if errors.As(err, &apiErr) && apiErr.Code == "NOT_FOUND" { … }
type Error struct {
	// Status is the HTTP status, or 0 for client-side errors.
	Status int
	// Code is the response body's "code", or one of the Code* constants.
	Code string
	// Message is the body's "message", a default
	// "NullDull request failed (<status> <code>).", or the client error's message.
	Message string
	// Detail is the body's "detail" (for example LOCALE_EXPORT_TOO_LARGE), or "".
	Detail string
	// RequestID is the X-Request-Id response header, or else CF-Ray, or "".
	RequestID string
	// RetryAfter is the Retry-After header in seconds, or nil when absent.
	RetryAfter *int
	// Body is the whole decoded JSON error body, or nil. Locale errors put
	// "key", "language" and "issues" here.
	Body map[string]any
	// Err is the underlying cause (a transport or context error), if any.
	Err error
}

// Error returns Message.
func (e *Error) Error() string { return e.Message }

// Unwrap returns the underlying cause, so errors.Is(err, context.Canceled)
// works for ABORTED errors.
func (e *Error) Unwrap() error { return e.Err }

func newError(status int, code, message string) *Error {
	if message == "" {
		message = fmt.Sprintf("NullDull request failed (%d %s).", status, code)
	}
	return &Error{Status: status, Code: code, Message: message}
}

func clientError(code, message string, cause error) *Error {
	return &Error{Code: code, Message: message, Err: cause}
}

func invalidArgument(message string) *Error {
	return clientError(CodeInvalidArgument, message, nil)
}
