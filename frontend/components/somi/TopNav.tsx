'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';
import { Menu, X } from 'lucide-react';
import { WalletConnectPill } from './WalletConnectPill';

const NAV_LINKS = [
  { label: 'Markets', href: '/' },
  { label: 'Create', href: '/create' },
  { label: 'My Bets', href: '/my-bets' },
  { label: 'About', href: '/about' },
];

export function TopNav() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  const linkClass = (href: string) =>
    pathname === href
      ? 'text-foreground text-sm font-medium'
      : 'text-muted-foreground text-sm font-medium hover:text-foreground transition-colors duration-150';

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="max-w-7xl mx-auto px-4 lg:px-12 h-14 flex items-center justify-between">
        <Link
          href="/"
          className="text-foreground font-mono font-semibold text-lg tracking-tight"
        >
          Somi
        </Link>

        <nav className="hidden lg:flex items-center gap-8" aria-label="Main navigation">
          {NAV_LINKS.map(({ label, href }) => (
            <Link key={href} href={href} className={linkClass(href)}>
              {label}
            </Link>
          ))}
        </nav>

        <div className="hidden lg:flex">
          <WalletConnectPill />
        </div>

        <button
          className="lg:hidden p-2 text-muted-foreground hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          onClick={() => setMobileOpen((o) => !o)}
          aria-label={mobileOpen ? 'Close menu' : 'Open menu'}
          aria-expanded={mobileOpen}
        >
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {mobileOpen && (
        <div className="lg:hidden border-t border-border bg-background px-4 pb-4 flex flex-col gap-4">
          <nav className="flex flex-col gap-2 pt-4" aria-label="Mobile navigation">
            {NAV_LINKS.map(({ label, href }) => (
              <Link
                key={href}
                href={href}
                className={linkClass(href) + ' py-2'}
                onClick={() => setMobileOpen(false)}
              >
                {label}
              </Link>
            ))}
          </nav>
          <WalletConnectPill />
        </div>
      )}
    </header>
  );
}
