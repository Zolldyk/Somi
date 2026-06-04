'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';

export function AxeRunner() {
  const pathname = usePathname();

  useEffect(() => {
    if (process.env.NODE_ENV === 'production') return;

    let cancelled = false;
    const handle = window.setTimeout(async () => {
      const { default: axe } = await import('axe-core');
      if (cancelled) return;
      const results = await axe.run(document);
      if (cancelled) return;
      if (results.violations.length === 0) {
        // eslint-disable-next-line no-console
        console.info(`[axe] ${pathname} — 0 violations`);
      } else {
        // eslint-disable-next-line no-console
        console.group(`[axe] ${pathname} — ${results.violations.length} violation(s)`);
        results.violations.forEach((v) => {
          // eslint-disable-next-line no-console
          console.warn(`${v.id} (${v.impact}): ${v.help}`, v.nodes.map((n) => n.target));
        });
        // eslint-disable-next-line no-console
        console.groupEnd();
      }
    }, 1000);

    return () => {
      cancelled = true;
      window.clearTimeout(handle);
    };
  }, [pathname]);

  return null;
}
