'use client';

import { useState, useEffect } from 'react';
import { useForm, useWatch } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod/v3';
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEventLogs } from 'viem';
import { useRouter } from 'next/navigation';
import { toast } from 'sonner';
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
  FormDescription,
} from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { TemplateSelectorCards } from '@/components/somi/TemplateSelectorCards';
import { TestSelectorPreview } from '@/components/somi/TestSelectorPreview';
import { Slider } from '@/components/ui/slider';
import { AmbiguityBandViz } from '@/components/somi/AmbiguityBandViz';
import { MarketTemplate } from '@/lib/templates';
import { LiveMarketPreview } from '@/components/somi/LiveMarketPreview';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import { predictionMarketAbi } from '@/lib/abi';
import { translateContractError } from '@/lib/errors';
import { useReactivityBalance } from '@/hooks/useReactivityBalance';

const createMarketSchema = z.object({
  question: z
    .string()
    .min(1, 'Question is required.')
    .max(280, 'Question must be 280 characters or fewer.'),
  dataSource: z
    .string()
    .url('Must be a valid URL (e.g. https://api.example.com/data).'),
  jsonSelector: z
    .string()
    .min(1, 'JSONPath selector is required.')
    .max(200, 'Selector must be 200 characters or fewer.'),
  threshold: z
    .string()
    .min(1, 'Threshold is required.')
    .refine(
      (v) => {
        try {
          return BigInt(v) > 0n;
        } catch {
          return false;
        }
      },
      'Must be a positive whole number (e.g. 110000).'
    ),
  resolutionTime: z
    .number()
    .int('Resolution time must be a whole number.')
    .refine(
      (v) => v >= Math.floor(Date.now() / 1000) + 300,
      'Resolution time must be at least 5 minutes from now.'
    ),
  ambiguityBandBps: z
    .number()
    .int()
    .min(1, 'Ambiguity band must be between 1 and 1000 basis points (0.01%–10%).')
    .max(1000, 'Ambiguity band must be between 1 and 1000 basis points (0.01%–10%).'),
});

type FormValues = z.infer<typeof createMarketSchema>;

type RelativePreset = '1h' | '6h' | '1d' | '3d' | '1w' | 'custom';

const PRESET_OFFSETS: Record<Exclude<RelativePreset, 'custom'>, number> = {
  '1h': 3600,
  '6h': 21600,
  '1d': 86400,
  '3d': 259200,
  '1w': 604800,
};

function computeTimestamp(preset: RelativePreset, custom: string): number {
  if (preset !== 'custom') {
    return Math.floor(Date.now() / 1000) + PRESET_OFFSETS[preset];
  }
  if (!custom) return 0;
  return Math.floor(new Date(custom).getTime() / 1000);
}

function formatResolutionPreview(ts: number): string {
  if (ts <= 0) return '';
  const date = new Date(ts * 1000);
  const utcTime = date.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'UTC',
  });
  const localTime = date.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  });
  const nowSec = Date.now() / 1000;
  const diffSec = ts - nowSec;
  const days = Math.floor(diffSec / 86400);
  const hours = Math.floor((diffSec % 86400) / 3600);
  if (days >= 1) {
    return `In ${days} day${days !== 1 ? 's' : ''} at ${utcTime} UTC (${localTime} local)`;
  }
  if (hours >= 1) {
    return `In ${hours} hour${hours !== 1 ? 's' : ''} at ${utcTime} UTC (${localTime} local)`;
  }
  const mins = Math.floor(diffSec / 60);
  return `In ${mins} minute${mins !== 1 ? 's' : ''} at ${utcTime} UTC (${localTime} local)`;
}

function isUserRejection(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const msg =
    (error as { shortMessage?: string; message?: string }).shortMessage ??
    (error as { message?: string }).message ??
    '';
  return msg.toLowerCase().includes('rejected') || msg.toLowerCase().includes('denied');
}

export default function CreatePage() {
  const router = useRouter();
  const [defaultResolutionTime] = useState(() => Math.floor(Date.now() / 1000) + 86400);
  const { writeContract, isPending: isSigning, data: txHash } = useWriteContract();
  const {
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isReceiptError,
    data: receipt,
  } = useWaitForTransactionReceipt({ hash: txHash });
  const { balance: reactivityBalance } = useReactivityBalance();

  const form = useForm<FormValues>({
    resolver: zodResolver(createMarketSchema),
    defaultValues: {
      question: '',
      dataSource: '',
      jsonSelector: '',
      threshold: '',
      resolutionTime: defaultResolutionTime,
      ambiguityBandBps: 100,
    },
    mode: 'onBlur',
  });

  const [selectedTemplateId, setSelectedTemplateId] = useState<MarketTemplate['id'] | null>(null);
  const watchedBandBps = useWatch({ control: form.control, name: 'ambiguityBandBps' });
  const watchedDataSource = useWatch({ control: form.control, name: 'dataSource' });
  const watchedJsonSelector = useWatch({ control: form.control, name: 'jsonSelector' });
  const watchedThreshold = useWatch({ control: form.control, name: 'threshold' });
  const watchedQuestion = useWatch({ control: form.control, name: 'question' });
  const watchedResolutionTime = useWatch({ control: form.control, name: 'resolutionTime' });

  const [relativePreset, setRelativePreset] = useState<RelativePreset>('1d');
  const [customDatetime, setCustomDatetime] = useState('');

  const currentTs = computeTimestamp(relativePreset, customDatetime);
  const previewText = formatResolutionPreview(currentTs);
  const errorCount = Object.keys(form.formState.errors).length;
  const isSubmitting = isSigning || isConfirming;
  const submitLabel = isSigning
    ? 'Signing…'
    : isConfirming
    ? 'Confirming in block…'
    : errorCount > 0
    ? `Fix ${errorCount} error${errorCount !== 1 ? 's' : ''}`
    : 'Create Market';
  const showLowFundsBadge =
    reactivityBalance !== undefined && reactivityBalance < 35n * 10n ** 18n;

  function handleTemplateSelect(template: MarketTemplate) {
    setSelectedTemplateId(template.id);
    const shouldValidate = form.formState.isSubmitted;
    form.setValue('dataSource', template.dataSource, { shouldValidate });
    form.setValue('jsonSelector', template.jsonSelector, { shouldValidate });
    form.setValue('ambiguityBandBps', template.recommendedBandBps, { shouldValidate });
  }

  function handleCreateMarket(values: FormValues) {
    if (!CONTRACT_ADDRESS) return;
    writeContract(
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'createMarket',
        args: [
          values.question,
          values.dataSource,
          values.jsonSelector,
          BigInt(values.threshold),
          BigInt(values.resolutionTime),
          BigInt(values.ambiguityBandBps),
        ],
      },
      {
        onError(err) {
          if (isUserRejection(err)) {
            toast('Market not created.');
          } else {
            const translated = translateContractError(err);
            toast(translated ?? 'Market creation failed. Please try again.');
          }
        },
      }
    );
  }

  useEffect(() => {
    const ts = computeTimestamp(relativePreset, customDatetime);
    if (ts > 0) {
      form.setValue('resolutionTime', ts, {
        shouldValidate: form.formState.isSubmitted,
      });
    }
  }, [relativePreset, customDatetime]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!isConfirmed || !receipt) return;
    const logs = parseEventLogs({
      abi: predictionMarketAbi,
      eventName: 'MarketCreated',
      logs: receipt.logs,
    });
    const args = logs[0]?.args as { marketId?: bigint } | undefined;
    const marketId = args?.marketId;
    if (marketId !== undefined) {
      router.push('/markets/' + marketId.toString());
    }
  }, [isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (isReceiptError) toast('Market creation failed. Please try again.');
  }, [isReceiptError]);

  return (
    <div className="max-w-7xl mx-auto px-4 lg:px-12 py-8 lg:py-12">
      <div className="grid lg:grid-cols-[1fr_400px] gap-8">
        {/* Left: form column */}
        <div className="flex flex-col gap-6">
          <div>
            <h1 className="text-2xl lg:text-3xl font-semibold tracking-tight">Create a Market</h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Launch an autonomous prediction market. Resolution happens on-chain — no manual
              intervention.
            </p>
          </div>

          {showLowFundsBadge && CONTRACT_ADDRESS && (
            <div className="text-xs text-muted-foreground font-mono border border-border rounded-sm px-3 py-2">
              Contract reactivity funds running low — anyone can top up by sending STT to{' '}
              <button
                type="button"
                className="underline cursor-pointer"
                onClick={() => navigator.clipboard.writeText(CONTRACT_ADDRESS!)}
              >
                {CONTRACT_ADDRESS}
              </button>
            </div>
          )}

          <Form {...form}>
            <form onSubmit={form.handleSubmit(handleCreateMarket)}>
              <fieldset disabled={isSubmitting} className="flex flex-col gap-6 border-0 p-0 m-0 min-w-0">
                <TemplateSelectorCards
                  selectedId={selectedTemplateId}
                  onSelect={handleTemplateSelect}
                  currentBandBps={watchedBandBps}
                />

                <FormField
                  control={form.control}
                  name="question"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Question</FormLabel>
                      <FormControl>
                        <Textarea
                          placeholder="Will BTC/USD exceed $110,000 at resolution time?"
                          rows={3}
                          className="resize-none"
                          {...field}
                        />
                      </FormControl>
                      <FormDescription>1–280 characters. Phrase as a yes/no question.</FormDescription>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="dataSource"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Data Source URL</FormLabel>
                      <FormControl>
                        <Input
                          type="url"
                          placeholder="https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd"
                          {...field}
                        />
                      </FormControl>
                      <FormDescription>
                        Public JSON endpoint the validator will fetch at resolution time.
                      </FormDescription>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="jsonSelector"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>JSONPath Selector</FormLabel>
                      <FormControl>
                        <Input
                          placeholder="bitcoin.usd"
                          className="font-mono"
                          aria-describedby="test-selector-result"
                          {...field}
                        />
                      </FormControl>
                      <FormDescription>
                        Dot-notation path to the numeric value (e.g. bitcoin.usd).
                      </FormDescription>
                      <FormMessage />
                      <TestSelectorPreview
                        dataSource={watchedDataSource}
                        jsonSelector={watchedJsonSelector}
                      />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="threshold"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Threshold</FormLabel>
                      <FormControl>
                        <Input
                          inputMode="decimal"
                          placeholder="110000"
                          className="font-mono tabular-nums"
                          {...field}
                        />
                      </FormControl>
                      <FormDescription>
                        Positive whole number. YES resolves if the fetched value exceeds this.
                      </FormDescription>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="ambiguityBandBps"
                  render={({ field }) => {
                    let thresholdBigInt = 0n;
                    try { thresholdBigInt = BigInt(watchedThreshold || '0'); } catch { /* invalid */ }
                    const bandBigInt = BigInt(field.value);
                    const bandHalf = thresholdBigInt > 0n ? (thresholdBigInt * bandBigInt) / 10_000n : 0n;
                    const low = thresholdBigInt - bandHalf;
                    const high = thresholdBigInt + bandHalf;
                    const pct = (field.value / 100).toFixed(2);
                    const readout =
                      thresholdBigInt > 0n
                        ? `±${pct}% (${Number(low).toLocaleString()}–${Number(high).toLocaleString()})`
                        : `±${pct}% (–)`;

                    return (
                      <FormItem>
                        <FormLabel>Ambiguity Band</FormLabel>
                        <FormControl>
                          <div className="flex flex-col gap-2">
                            <Slider
                              min={1}
                              max={1000}
                              step={10}
                              value={[field.value]}
                              onValueChange={([v]) => field.onChange(v)}
                              aria-label="Ambiguity Band"
                            />
                            <p className="font-mono text-sm tabular-nums text-muted-foreground">{readout}</p>
                          </div>
                        </FormControl>
                        <AmbiguityBandViz
                          variant="md"
                          threshold={thresholdBigInt}
                          bandBps={bandBigInt}
                        />
                        <FormDescription>
                          1–1000 basis points (0.01%–10%). Values within this band trigger the AI
                          tiebreaker.
                        </FormDescription>
                        <FormMessage />
                      </FormItem>
                    );
                  }}
                />

                <FormField
                  control={form.control}
                  name="resolutionTime"
                  render={() => (
                    <FormItem>
                      <FormLabel>Resolution Time</FormLabel>
                      <div className="flex flex-col gap-2">
                        <select
                          value={relativePreset}
                          onChange={(e) => setRelativePreset(e.target.value as RelativePreset)}
                          className="h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm focus-visible:border-ring focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
                        >
                          <option value="1h">In 1 hour</option>
                          <option value="6h">In 6 hours</option>
                          <option value="1d">In 1 day</option>
                          <option value="3d">In 3 days</option>
                          <option value="1w">In 1 week</option>
                          <option value="custom">Custom…</option>
                        </select>
                        {relativePreset === 'custom' && (
                          <input
                            type="datetime-local"
                            value={customDatetime}
                            onChange={(e) => setCustomDatetime(e.target.value)}
                            className="h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm font-mono focus-visible:border-ring focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
                          />
                        )}
                        {previewText && (
                          <p className="font-mono text-sm text-muted-foreground">{previewText}</p>
                        )}
                      </div>
                      <FormDescription>Must be at least 5 minutes from now.</FormDescription>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <Button
                  type="submit"
                  size="lg"
                  className="w-full min-h-[44px]"
                  disabled={isSubmitting || errorCount > 0}
                >
                  {submitLabel}
                </Button>
              </fieldset>
            </form>
          </Form>
        </div>

        {/* Right: preview column — hidden on mobile */}
        <div className="hidden lg:block">
          <div className="sticky top-8">
            <LiveMarketPreview
              question={watchedQuestion}
              dataSource={watchedDataSource}
              jsonSelector={watchedJsonSelector}
              threshold={watchedThreshold}
              ambiguityBandBps={watchedBandBps}
              resolutionTime={watchedResolutionTime}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
