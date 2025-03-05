'use client';

import { useAppSelector } from '@/lib/hooks/useAppSelector';
import { selectSelectedQueries } from '@/lib/store/queriesSlice';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@workspace/ui/components/collapsible';
import { ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useState } from 'react';

export function MultiQueryPrompt() {
  const selectedQueries = useAppSelector(selectSelectedQueries);

  return (
    <div className="space-y-2">
      {selectedQueries.map((query) => (
        <QueryPrompt key={query.id} query={query} />
      ))}
    </div>
  );
}

function QueryPrompt({ query }: { query: any }) {
  const [isOpen, setIsOpen] = useState(true);

  return (
    <Collapsible open={isOpen} onOpenChange={setIsOpen}>
      <CollapsibleTrigger className="flex items-center gap-2 w-full text-left p-2 hover:bg-muted/50 rounded-md">
        <ChevronRight
          className={cn(
            'h-4 w-4 shrink-0 transition-transform duration-200',
            isOpen && 'rotate-90'
          )}
        />
        <span className="font-medium">{query.id}</span>
      </CollapsibleTrigger>
      <CollapsibleContent className="pl-6 pr-2 py-2">
        {query.prompt}
        {query.sqlQuery}
        {query.description}
      </CollapsibleContent>
    </Collapsible>
  );
}
