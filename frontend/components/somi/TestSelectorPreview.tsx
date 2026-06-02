'use client';

import { useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

interface TestSelectorPreviewProps {
  dataSource: string;
  jsonSelector: string;
}

type PreviewState =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'success'; value: string }
  | { kind: 'error'; message: string }
  | { kind: 'cors-blocked' };

function extractValue(obj: unknown, selector: string): unknown {
  const parts = selector.split('.');
  let cur: unknown = obj;
  for (const part of parts) {
    if (cur === null || cur === undefined) return undefined;
    if (Array.isArray(cur)) {
      const idx = parseInt(part, 10);
      if (isNaN(idx)) return undefined;
      cur = cur[idx];
    } else if (typeof cur === 'object') {
      cur = (cur as Record<string, unknown>)[part];
    } else {
      return undefined;
    }
  }
  return cur;
}

function suggestFix(selector: string): string | null {
  const tokenMap: Record<string, string> = {
    btc: 'bitcoin',
    eth: 'ethereum',
    sol: 'solana',
    bnb: 'binancecoin',
    ada: 'cardano',
    dot: 'polkadot',
    link: 'chainlink',
    avax: 'avalanche-2',
    matic: 'matic-network',
    ltc: 'litecoin',
  };

  const parts = selector.split('.');
  if (parts.length >= 1 && tokenMap[parts[0]]) {
    const fixed = [tokenMap[parts[0]], ...parts.slice(1)].join('.');
    return fixed;
  }
  if (parts.length === 1) {
    return `${parts[0]}.usd`;
  }
  if (parts.length === 2 && parts[1] !== 'usd' && parts[1] !== 'usdt') {
    return `${parts[0]}.usd`;
  }
  return null;
}

function isCorsError(err: unknown): boolean {
  if (!(err instanceof TypeError)) return false;
  const msg = (err as TypeError).message.toLowerCase();
  return (
    msg === '' ||
    msg.includes('failed to fetch') ||
    msg.includes('networkerror') ||
    msg.includes('load failed') ||
    msg.includes('cors')
  );
}

export function TestSelectorPreview({ dataSource, jsonSelector }: TestSelectorPreviewProps) {
  const [state, setState] = useState<PreviewState>({ kind: 'idle' });
  const abortRef = useRef<AbortController | null>(null);

  async function handleTest() {
    if (!dataSource || !jsonSelector) return;

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    setState({ kind: 'loading' });

    try {
      const res = await fetch(dataSource, { signal: controller.signal });

      if (!res.ok) {
        const hostname = new URL(dataSource).hostname;
        setState({ kind: 'error', message: `HTTP ${res.status} from ${hostname}` });
        return;
      }

      const json: unknown = await res.json();
      const value = extractValue(json, jsonSelector);

      if (value === undefined || value === null) {
        const suggestion = suggestFix(jsonSelector);
        const message = suggestion
          ? `selector returned null. Did you mean ${suggestion}?`
          : 'selector returned null — check the path against the API response.';
        setState({ kind: 'error', message });
        return;
      }

      setState({ kind: 'success', value: String(value) });
    } catch (err) {
      if ((err as Error)?.name === 'AbortError') return;
      if (isCorsError(err)) {
        setState({ kind: 'cors-blocked' });
      } else {
        setState({
          kind: 'error',
          message: err instanceof Error ? err.message : 'Unexpected error.',
        });
      }
    }
  }

  const isLoading = state.kind === 'loading';
  const canTest = Boolean(dataSource && jsonSelector);

  return (
    <div className="flex flex-col gap-1.5 mt-1.5">
      <Button
        type="button"
        variant="secondary"
        size="sm"
        disabled={isLoading || !canTest}
        aria-busy={isLoading}
        onClick={handleTest}
        className="w-fit"
      >
        {isLoading ? 'Testing…' : 'Test Selector'}
      </Button>

      {state.kind !== 'idle' && (
        <p
          id="test-selector-result"
          aria-live="polite"
          className={cn(
            'font-mono text-sm',
            state.kind === 'loading' && 'text-muted-foreground',
            state.kind === 'success' && 'text-foreground',
            state.kind === 'error' && 'text-accent-no',
            state.kind === 'cors-blocked' && 'text-muted-foreground',
          )}
        >
          {state.kind === 'loading' && 'Testing…'}
          {state.kind === 'success' && `→ ${state.value}`}
          {state.kind === 'error' && `→ Error: ${state.message}`}
          {state.kind === 'cors-blocked' &&
            "→ Couldn't test from browser (CORS). Selector syntax looks valid; validators fetch server-side so resolution will still work."}
        </p>
      )}
    </div>
  );
}
