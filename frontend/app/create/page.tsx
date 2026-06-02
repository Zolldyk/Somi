'use client';

import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod/v3';
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
import { MarketTemplate } from '@/lib/templates';

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

async function onSubmit(_values: FormValues) {
  // Story 3.7 wires the createMarket transaction here
}

export default function CreatePage() {
  const form = useForm<FormValues>({
    resolver: zodResolver(createMarketSchema),
    defaultValues: {
      question: '',
      dataSource: '',
      jsonSelector: '',
      threshold: '',
      resolutionTime: Math.floor(Date.now() / 1000) + 86400,
      ambiguityBandBps: 100,
    },
    mode: 'onBlur',
  });

  const [selectedTemplateId, setSelectedTemplateId] = useState<MarketTemplate['id'] | null>(null);
  const watchedBandBps = form.watch('ambiguityBandBps');

  const [relativePreset, setRelativePreset] = useState<RelativePreset>('1d');
  const [customDatetime, setCustomDatetime] = useState('');

  const currentTs = computeTimestamp(relativePreset, customDatetime);
  const previewText = formatResolutionPreview(currentTs);
  const errorCount = Object.keys(form.formState.errors).length;
  const submitLabel =
    errorCount > 0 ? `Fix ${errorCount} error${errorCount !== 1 ? 's' : ''}` : 'Create Market';

  function handleTemplateSelect(template: MarketTemplate) {
    setSelectedTemplateId(template.id);
    const shouldValidate = form.formState.isSubmitted;
    form.setValue('dataSource', template.dataSource, { shouldValidate });
    form.setValue('jsonSelector', template.jsonSelector, { shouldValidate });
    form.setValue('ambiguityBandBps', template.recommendedBandBps, { shouldValidate });
  }

  useEffect(() => {
    const ts = computeTimestamp(relativePreset, customDatetime);
    if (ts > 0) {
      form.setValue('resolutionTime', ts, {
        shouldValidate: form.formState.isSubmitted,
      });
    }
  }, [relativePreset, customDatetime]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="max-w-2xl mx-auto px-4 lg:px-8 py-8 lg:py-12">
      <div className="flex flex-col gap-6">
        <div>
          <h1 className="text-2xl lg:text-3xl font-semibold tracking-tight">Create a Market</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Launch an autonomous prediction market. Resolution happens on-chain — no manual
            intervention.
          </p>
        </div>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="flex flex-col gap-6">
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
                    <Input placeholder="bitcoin.usd" className="font-mono" {...field} />
                  </FormControl>
                  <FormDescription>
                    Dot-notation path to the numeric value (e.g. bitcoin.usd).
                  </FormDescription>
                  <FormMessage />
                  {/* Test Selector — Story 3.4 */}
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

            {/* Ambiguity Band — Story 3.5 will replace this Input with Slider + readout */}
            <FormField
              control={form.control}
              name="ambiguityBandBps"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Ambiguity Band (bps)</FormLabel>
                  <FormControl>
                    <Input
                      type="number"
                      min={1}
                      max={1000}
                      className="font-mono tabular-nums"
                      {...field}
                      onChange={(e) => field.onChange(e.target.valueAsNumber)}
                    />
                  </FormControl>
                  <FormDescription>
                    1–1000 basis points (0.01%–10%). Values within this band trigger the AI
                    tiebreaker.
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
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

            <Button type="submit" size="lg" className="w-full min-h-[44px]">
              {submitLabel}
            </Button>
          </form>
        </Form>
      </div>
    </div>
  );
}
