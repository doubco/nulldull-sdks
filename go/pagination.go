package nulldull

import "iter"

// paginate yields the items of every page, starting at start and following
// nextCursor until it is nil (SPEC.md section 7). An empty page with a cursor
// is not the end. A repeated cursor stops with INVALID_RESPONSE. After an
// error is yielded the sequence ends.
func paginate[T any](start string, load func(after string) ([]T, *string, error)) iter.Seq2[T, error] {
	return func(yield func(T, error) bool) {
		var zero T
		after := start
		for {
			items, next, err := load(after)
			if err != nil {
				yield(zero, err)
				return
			}
			for _, item := range items {
				if !yield(item, nil) {
					return
				}
			}
			if next == nil {
				return
			}
			if *next == after {
				yield(zero, clientError(CodeInvalidResponse, "Pagination did not advance: the API returned the same cursor again.", nil))
				return
			}
			after = *next
		}
	}
}
