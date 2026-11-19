// @vitest-environment node
import type { GridPage } from "@nulldull/sdk";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { NullDullProvider, useGridPage, useGridPages, useMemoryDocuments } from "../src";
import { config, fixture, makeClient, mockFetch } from "./support";

describe("server rendering", () => {
  it("renders the loading state and never fetches", () => {
    const mock = mockFetch();
    function Page() {
      const page = useGridPage("nulldull-blog", "context-that-survives-the-chat");
      const list = useGridPages("nulldull-blog");
      return <p>{page.isLoading && list.isLoading ? "loading" : "ready"}</p>;
    }
    const html = renderToString(
      <NullDullProvider apiKey={config.publicKey} fetch={mock.fetch}>
        <Page />
      </NullDullProvider>,
    );
    expect(html).toContain("loading");
    expect(mock.requests).toHaveLength(0);
  });

  it("renders initialData", () => {
    const page = fixture<GridPage>("grid/page.json");
    const mock = mockFetch();
    function Page() {
      return <h1>{useGridPage("nulldull-blog", page.slug, { initialData: page }).data?.title}</h1>;
    }
    const html = renderToString(
      <NullDullProvider client={makeClient("public", mock.fetch)}>
        <Page />
      </NullDullProvider>,
    );
    expect(html).toContain(page.title);
    expect(mock.requests).toHaveLength(0);
  });

  it("allows a private key on the server (no window) without fetching", () => {
    const mock = mockFetch();
    function Docs() {
      return <p>{useMemoryDocuments().isLoading ? "loading" : "idle"}</p>;
    }
    const html = renderToString(
      <NullDullProvider apiKey={config.privateKey} workspaceId={config.workspaceId} fetch={mock.fetch}>
        <Docs />
      </NullDullProvider>,
    );
    expect(html).toContain("loading");
    expect(mock.requests).toHaveLength(0);
  });
});
