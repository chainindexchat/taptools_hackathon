'use client';

import { useState } from 'react';
import { ChevronRight, Eye } from 'lucide-react';
import { useAppDispatch, useAppSelector } from '@/lib/hooks/useAppSelector';

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';
import { cn } from '@/lib/utils';
import {
  setSelectedContentPath,
  selectSelectedContent,
  selectSelectedQueries,
  QueryState,
} from '@/lib/store/queriesSlice';

export function SummarySection() {
  const queries = useAppSelector(selectSelectedQueries);

  return (
    <div className="space-y-2">
      {queries.map((query) => (
        <QuerySummary key={query.id} query={query} />
      ))}
    </div>
  );
}

function QuerySummary({ query }: { query: QueryState }) {
  const [isOpen, setIsOpen] = useState(true);
  const dispatch = useAppDispatch();
  const selectedContent = useAppSelector(selectSelectedContent);

  const handleSelect = (label: string, path: string) => {
    dispatch(setSelectedContentPath({ label, path }));
  };

  return (
    <Collapsible open={isOpen} onOpenChange={setIsOpen}>
      <CollapsibleTrigger className="flex items-center gap-2 w-full text-left p-2 hover:bg-muted/50 rounded-md">
        <ChevronRight
          className={cn(
            'h-4 w-4 shrink-0 transition-transform duration-200',
            isOpen && 'rotate-90'
          )}
        />
        <span className="font-bold text-sm">{query.id}</span>
      </CollapsibleTrigger>
      <CollapsibleContent className="pl-6 pr-2 py-2 space-y-4">
        <TextSection
          label="prompt"
          value={query.prompt}
          onSelect={() =>
            handleSelect('Prompt', `queries.queries.${query.id}.prompt`)
          }
          isSelected={
            selectedContent?.path === `queries.queries.${query.id}.prompt`
          }
        />
        <TextSection
          label="sqlQuery"
          value={query.sqlQuery}
          onSelect={() =>
            handleSelect('SQL Query', `queries.queries.${query.id}.sqlQuery`)
          }
          isSelected={
            selectedContent?.path === `queries.queries.${query.id}.sqlQuery`
          }
        />
        <TextSection
          label="description"
          value={query.description ?? ''}
          onSelect={() =>
            handleSelect(
              'Description',
              `queries.queries.${query.id}.description`
            )
          }
          isSelected={
            selectedContent?.path === `queries.queries.${query.id}.description`
          }
        />
      </CollapsibleContent>
    </Collapsible>
  );
}

function TextSection({
  label,
  value,
  onSelect,
  isSelected,
}: {
  label: string;
  value: string;
  onSelect: () => void;
  isSelected: boolean;
}) {
  return (
    <div
      className={cn(
        'group cursor-pointer rounded-md border transition-colors',
        isSelected ? 'border-primary bg-primary/5' : 'border-transparent',
        'hover:border-primary/50 hover:bg-primary/5'
      )}
      onClick={onSelect}
    >
      <div className="text-xs font-medium text-muted-foreground px-3 pt-2 uppercase tracking-wider">
        {label}
      </div>
      <div className="p-3 flex items-start gap-2">
        <p className="text-sm flex-1 line-clamp-3">{value}</p>
        <Eye
          className={cn(
            'h-4 w-4 shrink-0 mt-0.5 transition-colors',
            isSelected ? 'text-primary' : 'text-primary/0',
            'group-hover:text-primary/50'
          )}
        />
      </div>
    </div>
  );
}
