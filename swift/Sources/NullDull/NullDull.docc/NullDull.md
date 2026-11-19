# ``NullDull``

Read NullDull Grid, Memory and Locale with workspace API keys.

## Overview

Create one ``NullDullClient`` and share it. Public keys (`nd_pub_…`) read published Grid
content and are safe in app bundles. Private keys (`nd_sec_…`) also read Memory and export
Locale catalogs, need a workspace ID, and belong on servers and in build tools only.

```swift
let nulldull = try NullDullClient(apiKey: "nd_pub_…")
let page = try await nulldull.grid.getPage("my-blog", slug: "hello-world")
```

Every call is `async throws` and throws ``NullDullError``. Lists have a single-page method
(for example ``MemoryAPI/listDocuments(scopeID:folderID:tags:kind:lifecycle:after:)``) and a
lazy `AsyncThrowingStream` iterator (``MemoryAPI/iterateDocuments(scopeID:folderID:tags:kind:lifecycle:after:)``).

> Important: Early access. Version 0.1.0 may change before 1.0.

## Topics

### Client

- ``NullDullClient``
- ``NullDullError``
- ``NullDullTransport``
- ``URLSessionTransport``

### Grid

- ``GridAPI``
- ``GridPageList``
- ``GridPageSummary``
- ``GridPage``
- ``GridDocument``
- ``GridAssetRef``
- ``GridCover``

### Memory

- ``MemoryAPI``
- ``FolderFilter``
- ``Scope``
- ``FolderList``
- ``Folder``
- ``DocumentSummary``
- ``Document``
- ``SearchResult``
- ``TagCount``
- ``LinkResolution``
- ``Asset``
- ``AssetVersion``

### Locale

- ``LocaleAPI``
- ``LocaleFormatList``
- ``LocaleExport``
- ``LocaleFormatID``
- ``LocaleKeyStatus``

### Shared types

- ``Page``
- ``Download``
- ``JSONValue``
- ``NullDullModel``
- ``NullDullOpenEnum``
