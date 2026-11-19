package nulldull_test

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"

	nulldull "github.com/doubco/nulldull-sdks/go"
)

// A fake public key for examples. Real keys come from the NullDull app.
const examplePublicKey = "nd_pub_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func Example() {
	client, err := nulldull.New(os.Getenv("NULLDULL_PRIVATE_KEY"),
		nulldull.WithWorkspaceID(os.Getenv("NULLDULL_WORKSPACE_ID")))
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()

	page, err := client.Grid.GetPage(ctx, "my-blog", "hello-world", nil)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(page.Title)
}

func ExampleNew() {
	_, err := nulldull.New("not-a-key")
	var apiErr *nulldull.Error
	if errors.As(err, &apiErr) {
		fmt.Println(apiErr.Status, apiErr.Code)
	}
	// Output: 0 INVALID_ARGUMENT
}

func ExampleGridService_ListPages() {
	client, err := nulldull.New(os.Getenv("NULLDULL_PUBLIC_KEY"))
	if err != nil {
		log.Fatal(err)
	}
	list, err := client.Grid.ListPages(context.Background(), "my-blog", &nulldull.ListPagesParams{Locale: "en", Limit: 20})
	if err != nil {
		log.Fatal(err)
	}
	for _, summary := range list.Items {
		fmt.Println(summary.Title)
	}
	// Pass *list.NextCursor as After for the next page; nil means this was the last.
	fmt.Println("more pages:", list.NextCursor != nil)
}

func ExampleGridService_IteratePages() {
	client, err := nulldull.New(os.Getenv("NULLDULL_PUBLIC_KEY"))
	if err != nil {
		log.Fatal(err)
	}
	for summary, err := range client.Grid.IteratePages(context.Background(), "my-blog", &nulldull.ListPagesParams{Q: "launch"}) {
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(summary.Slug)
	}
}

func ExampleGridService_AssetURL() {
	client, err := nulldull.New(examplePublicKey)
	if err != nil {
		log.Fatal(err)
	}
	own, _ := client.Grid.AssetURL("/api/grid/v1/pools/my-blog/pages/hello/assets/cover?version=3")
	other, _ := client.Grid.AssetURL("https://cdn.example.com/cover.png")
	fmt.Println(strings.Replace(own, examplePublicKey, "nd_pub_…", 1))
	fmt.Println(other)
	// Output:
	// https://nulldull.com/api/grid/v1/pools/my-blog/pages/hello/assets/cover?version=3&key=nd_pub_…
	// https://cdn.example.com/cover.png
}

func ExampleMemoryService_IterateDocuments() {
	client, err := nulldull.New(os.Getenv("NULLDULL_PRIVATE_KEY"),
		nulldull.WithWorkspaceID(os.Getenv("NULLDULL_WORKSPACE_ID")))
	if err != nil {
		log.Fatal(err)
	}
	params := &nulldull.ListDocumentsParams{Tags: []string{"rules"}, Root: true} // Root: unfiled documents only
	for doc, err := range client.Memory.IterateDocuments(context.Background(), params) {
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(doc.Name)
	}
}

func ExampleLocaleService_Export() {
	client, err := nulldull.New(os.Getenv("NULLDULL_PRIVATE_KEY"),
		nulldull.WithWorkspaceID(os.Getenv("NULLDULL_WORKSPACE_ID")))
	if err != nil {
		log.Fatal(err)
	}
	exported, err := client.Locale.Export(context.Background(), client.WorkspaceID(), &nulldull.ExportParams{
		Format:    nulldull.FormatAndroidXML,
		Languages: []string{"en", "tr"},
		Status:    []nulldull.LocaleKeyStatus{nulldull.StatusApproved},
	})
	if err != nil {
		log.Fatal(err)
	}
	for _, file := range exported.Files {
		fmt.Println(file.Path) // values/strings.xml, values-tr/strings.xml
	}
}

func ExampleError() {
	// A stand-in API that answers like a missing Grid page.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("CF-Ray", "8f1e2d3c4b5a6978-AMS")
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, `{"code":"NOT_FOUND","message":"Resource not found."}`)
	}))
	defer server.Close()

	client, err := nulldull.New(examplePublicKey, nulldull.WithBaseURL(server.URL))
	if err != nil {
		log.Fatal(err)
	}
	_, err = client.Grid.GetPage(context.Background(), "my-blog", "missing", nil)

	var apiErr *nulldull.Error
	if errors.As(err, &apiErr) {
		fmt.Println(apiErr.Status, apiErr.Code, apiErr.Message, apiErr.RequestID)
	}
	// Output: 404 NOT_FOUND Resource not found. 8f1e2d3c4b5a6978-AMS
}
