// JSON methods for the response types in types.go. Each keeps unknown
// fields in Extra so values round-trip without loss.

package nulldull

// UnmarshalJSON keeps unknown fields in Extra.
func (v *GridAssetRef) UnmarshalJSON(data []byte) error {
	type plain GridAssetRef
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v GridAssetRef) MarshalJSON() ([]byte, error) {
	type plain GridAssetRef
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *GridCover) UnmarshalJSON(data []byte) error {
	type plain GridCover
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v GridCover) MarshalJSON() ([]byte, error) {
	type plain GridCover
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *GridPageSummary) UnmarshalJSON(data []byte) error {
	type plain GridPageSummary
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v GridPageSummary) MarshalJSON() ([]byte, error) {
	type plain GridPageSummary
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *GridPage) UnmarshalJSON(data []byte) error {
	type plain GridPage
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v GridPage) MarshalJSON() ([]byte, error) {
	type plain GridPage
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *GridPool) UnmarshalJSON(data []byte) error {
	type plain GridPool
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v GridPool) MarshalJSON() ([]byte, error) {
	type plain GridPool
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *GridPageList) UnmarshalJSON(data []byte) error {
	type plain GridPageList
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v GridPageList) MarshalJSON() ([]byte, error) {
	type plain GridPageList
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *Scope) UnmarshalJSON(data []byte) error {
	type plain Scope
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v Scope) MarshalJSON() ([]byte, error) {
	type plain Scope
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *Placement) UnmarshalJSON(data []byte) error {
	type plain Placement
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v Placement) MarshalJSON() ([]byte, error) {
	type plain Placement
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *FolderRef) UnmarshalJSON(data []byte) error {
	type plain FolderRef
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v FolderRef) MarshalJSON() ([]byte, error) {
	type plain FolderRef
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *FolderSummary) UnmarshalJSON(data []byte) error {
	type plain FolderSummary
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v FolderSummary) MarshalJSON() ([]byte, error) {
	type plain FolderSummary
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *FolderCounts) UnmarshalJSON(data []byte) error {
	type plain FolderCounts
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v FolderCounts) MarshalJSON() ([]byte, error) {
	type plain FolderCounts
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *FolderList) UnmarshalJSON(data []byte) error {
	type plain FolderList
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v FolderList) MarshalJSON() ([]byte, error) {
	type plain FolderList
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *Folder) UnmarshalJSON(data []byte) error {
	type plain Folder
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v Folder) MarshalJSON() ([]byte, error) {
	type plain Folder
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *DocumentSummary) UnmarshalJSON(data []byte) error {
	type plain DocumentSummary
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v DocumentSummary) MarshalJSON() ([]byte, error) {
	type plain DocumentSummary
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *Document) UnmarshalJSON(data []byte) error {
	type plain Document
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v Document) MarshalJSON() ([]byte, error) {
	type plain Document
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *SearchResult) UnmarshalJSON(data []byte) error {
	type plain SearchResult
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v SearchResult) MarshalJSON() ([]byte, error) {
	type plain SearchResult
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *TagCount) UnmarshalJSON(data []byte) error {
	type plain TagCount
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v TagCount) MarshalJSON() ([]byte, error) {
	type plain TagCount
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LinkResolution) UnmarshalJSON(data []byte) error {
	type plain LinkResolution
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LinkResolution) MarshalJSON() ([]byte, error) {
	type plain LinkResolution
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *AssetObject) UnmarshalJSON(data []byte) error {
	type plain AssetObject
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v AssetObject) MarshalJSON() ([]byte, error) {
	type plain AssetObject
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *Asset) UnmarshalJSON(data []byte) error {
	type plain Asset
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v Asset) MarshalJSON() ([]byte, error) {
	type plain Asset
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *AssetVersion) UnmarshalJSON(data []byte) error {
	type plain AssetVersion
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v AssetVersion) MarshalJSON() ([]byte, error) {
	type plain AssetVersion
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleCapabilities) UnmarshalJSON(data []byte) error {
	type plain LocaleCapabilities
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleCapabilities) MarshalJSON() ([]byte, error) {
	type plain LocaleCapabilities
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleFormatFile) UnmarshalJSON(data []byte) error {
	type plain LocaleFormatFile
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleFormatFile) MarshalJSON() ([]byte, error) {
	type plain LocaleFormatFile
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleFormat) UnmarshalJSON(data []byte) error {
	type plain LocaleFormat
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleFormat) MarshalJSON() ([]byte, error) {
	type plain LocaleFormat
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleFormatList) UnmarshalJSON(data []byte) error {
	type plain LocaleFormatList
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleFormatList) MarshalJSON() ([]byte, error) {
	type plain LocaleFormatList
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleFile) UnmarshalJSON(data []byte) error {
	type plain LocaleFile
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleFile) MarshalJSON() ([]byte, error) {
	type plain LocaleFile
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleExportNote) UnmarshalJSON(data []byte) error {
	type plain LocaleExportNote
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleExportNote) MarshalJSON() ([]byte, error) {
	type plain LocaleExportNote
	return encodeObject(plain(v), v.Extra)
}

// UnmarshalJSON keeps unknown fields in Extra.
func (v *LocaleExport) UnmarshalJSON(data []byte) error {
	type plain LocaleExport
	return decodeObject(data, (*plain)(v), &v.Extra)
}

// MarshalJSON writes the known fields and Extra.
func (v LocaleExport) MarshalJSON() ([]byte, error) {
	type plain LocaleExport
	return encodeObject(plain(v), v.Extra)
}
