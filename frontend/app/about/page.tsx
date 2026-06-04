import type { Metadata } from 'next';
import Image from 'next/image';

export const metadata: Metadata = {
  title: 'About — Somi',
  description:
    'Somi resolves prediction markets autonomously using Somnia Reactivity, JSON API agents, and Streams. AI shows its work, recorded on-chain.',
};

export default function AboutPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 lg:px-8 py-12 space-y-12">
      <article>
        <h1 className="text-3xl font-bold tracking-tight mb-6">
          Somi — autonomous resolution, recorded on-chain
        </h1>

        <p className="text-base leading-relaxed text-muted-foreground">
          Somi is a prediction market where every market resolves without a
          human operator. Resolution logic is published before the market opens,
          executed on-chain by an AI agent, and permanently recorded — so
          anyone can verify the verdict after the fact.
        </p>

        <section aria-labelledby="primitives" className="mt-12 space-y-6">
          <h2
            id="primitives"
            className="text-2xl font-semibold"
          >
            The three primitives
          </h2>

          <div className="space-y-5">
            <div>
              <p className="text-xl font-medium mb-2">Reactivity</p>
              <p className="text-base leading-relaxed text-muted-foreground">
                Somnia&apos;s event subscription system lets contracts react to
                on-chain events without polling. Somi uses Reactivity to watch
                for <code className="font-mono text-sm">createMarket</code> and{' '}
                <code className="font-mono text-sm">placeBet</code> events and
                trigger the autonomous resolution loop the moment the market
                window closes.
              </p>
            </div>

            <div>
              <p className="text-xl font-medium mb-2">Agents</p>
              <p className="text-base leading-relaxed text-muted-foreground">
                An on-chain callback queries a JSON API (CoinGecko, ESPN, or
                any custom endpoint specified in the resolution plan) and
                compares the result against the market threshold and ambiguity
                band. When the numeric value falls inside the band, an LLM
                tiebreaker reads the data and returns a{' '}
                <code className="font-mono text-sm">YES</code>,{' '}
                <code className="font-mono text-sm">NO</code>, or{' '}
                <code className="font-mono text-sm">INVALID</code> verdict with
                full reasoning. The entire reasoning chain is stored in the
                Agents receipt and accessible on-chain.
              </p>
            </div>

            <div>
              <p className="text-xl font-medium mb-2">Streams</p>
              <p className="text-base leading-relaxed text-muted-foreground">
                Somnia&apos;s cross-contract event bus allows typed schemas to
                be published and consumed in the same block. On every
                settlement, Somi emits an{' '}
                <code className="font-mono text-sm">OutcomePublished</code>{' '}
                Streams event so downstream contracts — like{' '}
                <code className="font-mono text-sm">
                  MarketOutcomeSubscriber
                </code>{' '}
                — can compose with market outcomes without polling or
                off-chain coordination.
              </p>
            </div>
          </div>
        </section>

        <section aria-labelledby="matters" className="mt-12 space-y-4">
          <h2 id="matters" className="text-2xl font-semibold">
            Why this matters
          </h2>

          <p className="text-base leading-relaxed text-muted-foreground">
            Most on-chain prediction markets hand resolution to a multisig, a
            DAO vote, or a trusted oracle. Each of those paths introduces a
            human bottleneck: someone must show up, read the data, and push a
            transaction. Somi removes the bottleneck entirely. The resolution
            plan is locked at market creation; the agent executes it at the
            scheduled time whether or not anyone is watching.
          </p>

          <p className="text-base leading-relaxed text-muted-foreground">
            The AI agent does not just return a verdict — it records the full
            reasoning in an Agents receipt that lives on-chain. This is the
            &ldquo;AI shows its work&rdquo; property: any participant can
            reconstruct exactly what data the agent saw, what the threshold
            comparison produced, and why the LLM tiebreaker ruled the way it
            did, long after the market settles.
          </p>

          <p className="text-base leading-relaxed text-muted-foreground">
            <code className="font-mono text-sm">INVALID</code> is a first-class
            verdict, not an error state. When the data source is unreachable,
            the value is indeterminate, or the reasoning is genuinely
            ambiguous, the agent returns{' '}
            <code className="font-mono text-sm">INVALID</code> and all bets are
            refunded. Treating <code className="font-mono text-sm">INVALID</code>{' '}
            as a legitimate outcome — rather than a fallback — is part of the
            design: the market only settles when the evidence is clear.
          </p>
        </section>

        <section aria-labelledby="resolution" className="mt-12 space-y-4">
          <h2 id="resolution" className="text-2xl font-semibold">
            How a market resolves
          </h2>

          <ol className="list-decimal list-inside space-y-2 text-base leading-relaxed text-muted-foreground">
            <li>
              Market created — a Reactivity subscription is registered for the
              resolution timestamp.
            </li>
            <li>
              Resolution time passes — Reactivity triggers the{' '}
              <code className="font-mono text-sm">handleResponse</code>{' '}
              callback without any external prompt.
            </li>
            <li>
              JSON API queried — the numeric value (price, score, or custom
              field) is compared against the market threshold.
            </li>
            <li>
              If the value falls inside the ambiguity band, the LLM tiebreaker
              reads the raw data and returns a{' '}
              <code className="font-mono text-sm">YES</code>,{' '}
              <code className="font-mono text-sm">NO</code>, or{' '}
              <code className="font-mono text-sm">INVALID</code> verdict with
              written reasoning.
            </li>
            <li>
              Settlement minted — the verdict is written on-chain, payouts are
              unlocked, and an{' '}
              <code className="font-mono text-sm">OutcomePublished</code>{' '}
              Streams event is emitted.
            </li>
          </ol>

          <p className="text-base leading-relaxed text-muted-foreground">
            The receipt below is from a real resolution on Somnia testnet.
            It shows the JSON API response, the threshold comparison, and the
            LLM reasoning that produced the final verdict.
          </p>

          <div className="mt-6 rounded-xl overflow-hidden ring-1 ring-foreground/10">
            <Image
              src="/about/receipt-yes.png"
              alt="Agents receipt from a YES resolution on Somnia testnet — showing JSON API price data, threshold comparison, and on-chain verdict"
              width={900}
              height={600}
              className="w-full h-auto"
              priority
            />
          </div>
        </section>

        <section aria-labelledby="built" className="mt-12 space-y-4">
          <h2 id="built" className="text-2xl font-semibold">
            Built solo in two weeks
          </h2>

          <p className="text-base leading-relaxed text-muted-foreground">
            Somi was built solo over two weeks as a submission to the Somnia
            Agentathon — a hackathon exploring what on-chain AI agents can do
            when running on a high-throughput EVM chain. The stack covers a
            Solidity prediction market contract with resolution logic, a
            React/Next.js frontend with live pool tracking, and the Reactivity,
            Agents, and Streams integrations described above.
          </p>

          <p className="text-base leading-relaxed text-muted-foreground">
            The full source is on GitHub:{' '}
            <a
              href="https://github.com/Zolldyk/Somi"
              target="_blank"
              rel="noopener noreferrer"
              className="underline underline-offset-2 hover:opacity-80 transition-opacity"
            >
              github.com/Zolldyk/Somi
            </a>
            . Submitted to the Somnia Agentathon 2025.
          </p>
        </section>
      </article>
    </div>
  );
}
