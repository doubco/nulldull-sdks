import { describe, expect, it } from "vitest";
import { NullDullError, type Download } from "../src";
import { at, clientFor, fixture, invoke, manifest, mockFetch, multimap, responseFrom, without } from "./support";

describe("shared conformance fixtures (fixtures/manifest.json)", () => {
  for (const testCase of manifest.cases) {
    it(testCase.id, async () => {
      const { fetch, requests } = mockFetch(testCase.exchanges.map((exchange) => responseFrom(exchange.response)));
      const { client, sleeps } = clientFor(testCase.key, fetch);
      const expectation = testCase.expect;

      let result: unknown;
      let failure: unknown;
      try {
        result = await invoke(client, testCase.call.method, structuredClone(testCase.call.args));
      } catch (error) {
        failure = error;
      }

      // Requests: order, method, path and query multimap.
      const attempts = expectation.attempts ?? testCase.exchanges.length;
      expect(requests).toHaveLength(attempts);
      requests.forEach((request, index) => {
        const wanted = testCase.exchanges[index]!.request;
        expect(request.init.method).toBe(wanted.method);
        expect(request.url.origin).toBe(manifest.config.baseUrl);
        expect(request.url.pathname).toBe(wanted.path);
        expect(multimap(request.url)).toEqual(wanted.query);
        expect(request.headers.get("authorization")).toBe(`Bearer ${testCase.key === "public" ? manifest.config.publicKey : manifest.config.privateKey}`);
      });
      if (expectation.sleeps) expect(sleeps).toEqual(expectation.sleeps);

      if (expectation.error) {
        expect(failure, "expected the call to fail").toBeInstanceOf(NullDullError);
        const error = failure as NullDullError;
        for (const [field, value] of Object.entries(expectation.error)) {
          if (field === "body") expect(error.body).toMatchObject(value as object);
          else expect((error as any)[field]).toEqual(value);
        }
        return;
      }
      if (failure) throw failure;

      if (expectation.resultFile) expect(without(result, expectation.except)).toEqual(without(fixture(expectation.resultFile), expectation.except));
      if (expectation.itemCount !== undefined) expect(result).toHaveLength(expectation.itemCount);
      for (const check of expectation.checks ?? []) expect(at(result, check.path)).toEqual(check.equals);
      if (expectation.download) {
        const download = result as Download;
        expect(download.contentType).toBe(expectation.download.contentType);
        expect(download.filename).toBe(expectation.download.filename);
        expect(download.size).toBe(expectation.download.size);
        expect(download.bytes).toBeInstanceOf(Uint8Array);
        expect(Buffer.from(download.bytes).toString("base64")).toBe(expectation.download.bytesBase64);
      }
    });
  }
});
