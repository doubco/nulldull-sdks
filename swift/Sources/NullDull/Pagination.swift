import Foundation

/// Follows `nextCursor` until it is `null` and yields the items of every page, lazily:
/// a page is requested only when the consumer asks for the next item past the buffer.
/// An empty page with a cursor is not the end. A repeated cursor ends with `INVALID_RESPONSE`.
func paginate<Item: Sendable>(
    start: String?,
    load: @escaping @Sendable (_ after: String?) async throws -> (items: [Item], nextCursor: String?)
) -> AsyncThrowingStream<Item, any Error> {
    let pager = Pager(cursor: start, load: load)
    return AsyncThrowingStream(unfolding: { try await pager.next() })
}

private actor Pager<Item: Sendable> {
    private var cursor: String?
    private var buffer: [Item] = []
    private var index = 0
    private var finished = false
    private var pendingError: NullDullError?
    private let load: @Sendable (String?) async throws -> (items: [Item], nextCursor: String?)

    init(cursor: String?, load: @escaping @Sendable (String?) async throws -> (items: [Item], nextCursor: String?)) {
        self.cursor = cursor
        self.load = load
    }

    func next() async throws -> Item? {
        while true {
            if index < buffer.count {
                defer { index += 1 }
                return buffer[index]
            }
            if let error = pendingError {
                pendingError = nil
                finished = true
                throw error
            }
            if finished { return nil }
            let sent = cursor
            let page: (items: [Item], nextCursor: String?)
            do {
                page = try await load(sent)
            } catch {
                finished = true
                throw error
            }
            buffer = page.items
            index = 0
            if let next = page.nextCursor {
                if next == sent {
                    pendingError = NullDullError.client(
                        .invalidResponse, "Pagination did not advance: the API returned the same cursor again.")
                } else {
                    cursor = next
                }
            } else {
                finished = true
            }
        }
    }
}
