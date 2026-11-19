package nulldull

import (
	"context"
	"strings"
)

// LocaleService exports Locale catalogs (scope locale:read). It needs a
// private key and a workspace ID.
type LocaleService struct {
	t     *transport
	guard guard
}

// ExportParams configures LocaleService.Export.
type ExportParams struct {
	// Format is an export format ID such as FormatJSON or FormatAndroidXML.
	// Default "json". Unknown IDs are sent as given.
	Format string
	// Languages to export (comma-joined on the wire). Default: every
	// configured language.
	Languages []string
	// Status keeps only keys with these statuses (comma-joined on the wire).
	// Default: every status.
	Status []LocaleKeyStatus
	// Basename is the base file name without extension, such as "Localizable".
	Basename string
}

func commaList(items []string, name string) (string, error) {
	for _, item := range items {
		if item == "" || strings.Contains(item, ",") {
			return "", invalidArgument(name + " must be a list of non-empty strings without commas.")
		}
	}
	return strings.Join(items, ","), nil
}

// ListFormats returns the export formats with their capabilities and file roles.
func (s *LocaleService) ListFormats(ctx context.Context) (*LocaleFormatList, error) {
	root, err := s.guard.root()
	if err != nil {
		return nil, err
	}
	var list LocaleFormatList
	if err := s.t.getJSON(ctx, root+"/locale/formats", nil, &list); err != nil {
		return nil, err
	}
	return &list, nil
}

// Export exports the Locale catalog of a location (scopeID; the workspace
// root location's ID equals the workspace ID) as text files: one file set
// per language for single-language formats ("en.json",
// "values-tr/strings.xml"), one file for xcstrings. It is never an archive.
func (s *LocaleService) Export(ctx context.Context, scopeID string, params *ExportParams) (*LocaleExport, error) {
	p := ExportParams{}
	if params != nil {
		p = *params
	}
	if scopeID == "" {
		return nil, invalidArgument("scopeId must be a non-empty string.")
	}
	languages, err := commaList(p.Languages, "languages")
	if err != nil {
		return nil, err
	}
	statuses := make([]string, len(p.Status))
	for i, status := range p.Status {
		statuses[i] = string(status)
	}
	status, err := commaList(statuses, "status")
	if err != nil {
		return nil, err
	}
	root, err := s.guard.root()
	if err != nil {
		return nil, err
	}
	format := p.Format
	if format == "" {
		format = FormatJSON
	}
	// Never send the legacy single "language" parameter: it changes the
	// response shape of json and world exports.
	var q query
	q.set("scopeId", scopeID)
	q.set("format", format)
	q.opt("languages", languages)
	q.opt("status", status)
	q.opt("basename", p.Basename)
	var export LocaleExport
	if err := s.t.getJSON(ctx, root+"/locale/export", q, &export); err != nil {
		return nil, err
	}
	return &export, nil
}
