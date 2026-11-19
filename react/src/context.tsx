import { NullDullClient, NullDullError, type NullDullClientOptions } from "@nulldull/sdk";
import { createContext, useContext, useMemo, type ReactNode } from "react";

const NullDullContext = createContext<NullDullClient | null>(null);

export type NullDullProviderProps = { children?: ReactNode } & (
  | { /** A client you built yourself. Other options are ignored. */ client: NullDullClient }
  | (NullDullClientOptions & { client?: undefined })
);

/**
 * Makes a NullDull client available to the hooks below it. Pass a `client`, or the client
 * options (`apiKey`, `workspaceId`, `baseUrl`, …) and the provider builds and memoises one.
 *
 * In a browser bundle, pass only a public key (`nd_pub_…`).
 */
export function NullDullProvider(props: NullDullProviderProps) {
  const { children, client } = props;
  const options = client ? undefined : (props as NullDullClientOptions);
  const value = useMemo(
    () => client ?? new NullDullClient(options as NullDullClientOptions),
    // Rebuild only when a configuration value changes, not on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      client,
      options?.apiKey,
      options?.baseUrl,
      options?.workspaceId,
      options?.timeout,
      options?.maxRetries,
      options?.fetch,
      options?.userAgent,
      options?.dangerouslyAllowPrivateKeyInBrowser,
      options?.sleep,
    ],
  );
  return <NullDullContext.Provider value={value}>{children}</NullDullContext.Provider>;
}

/** The client from the nearest `<NullDullProvider>`. Throws `INVALID_ARGUMENT` outside one. */
export function useNullDull(): NullDullClient {
  const client = useContext(NullDullContext);
  if (!client)
    throw new NullDullError({ status: 0, code: "INVALID_ARGUMENT", message: "useNullDull() needs a <NullDullProvider> above it." });
  return client;
}
