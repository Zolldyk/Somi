'use client';

import { TEMPLATES, getTemplateById, MarketTemplate } from '@/lib/templates';
import { Card, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { cn } from '@/lib/utils';

interface TemplateSelectorCardsProps {
  selectedId: MarketTemplate['id'] | null;
  onSelect: (template: MarketTemplate) => void;
  currentBandBps: number;
}

export function TemplateSelectorCards({
  selectedId,
  onSelect,
  currentBandBps,
}: TemplateSelectorCardsProps) {
  const selectedTemplate = selectedId ? getTemplateById(selectedId) : null;
  const isManualBand = selectedTemplate
    ? currentBandBps !== selectedTemplate.recommendedBandBps
    : false;

  function formatPct(bps: number): string {
    const pct = bps / 100;
    return Number.isInteger(pct) ? `${pct}%` : `${pct.toFixed(2)}%`;
  }

  const subtitle = selectedTemplate
    ? isManualBand
      ? `Custom band: ${currentBandBps} bps (${formatPct(currentBandBps)})`
      : `Recommended band: ${currentBandBps} bps (${formatPct(currentBandBps)}) — adjustable below`
    : null;

  return (
    <div className="flex flex-col gap-2">
      <div
        role="group"
        aria-label="Market template"
        className="grid grid-cols-1 sm:grid-cols-3 gap-3"
      >
        {TEMPLATES.map((template) => {
          const isSelected = template.id === selectedId;
          return (
            <button
              key={template.id}
              type="button"
              aria-pressed={isSelected}
              onClick={() => onSelect(template)}
              className="block w-full text-left rounded-xl min-h-[44px] outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
            >
              <Card
                className={cn(
                  'h-full cursor-pointer',
                  isSelected && 'ring-2 ring-accent-llm',
                )}
              >
                <CardHeader>
                  <CardTitle>{template.label}</CardTitle>
                  <CardDescription>{template.description}</CardDescription>
                </CardHeader>
              </Card>
            </button>
          );
        })}
      </div>
      {subtitle && (
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      )}
    </div>
  );
}
