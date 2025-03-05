'use client';

import { useAppSelector } from '@/lib/hooks/useAppSelector';
import { useAppDispatch } from '@/lib/hooks/useAppDispatch';
import {
  selectAllQueries,
  selectSelectedQueryIds,
  toggleQuerySelection,
} from '@/lib/store/queriesSlice';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@workspace/ui/components/accordion';
import { Check, Eye } from 'lucide-react';
import { format } from 'date-fns';
import React from 'react';

export function QueryHistory() {
  const queries = useAppSelector(selectAllQueries);
  const selectedIds = useAppSelector(selectSelectedQueryIds);
  const dispatch = useAppDispatch();

  // // Group queries by date
  // const groupedQueries = queries.reduce(
  //   (acc, query) => {
  //     const date = new Date(query.timestamp).toDateString()
  //     if (!acc[date]) {
  //       acc[date] = []
  //     }
  //     acc[date].push(query)
  //     return acc
  //   },
  //   {} as Record<string, typeof queries>,
  // )

  return (
    <div className="space-y-4">
      {selectedIds.length > 1 && (
        <div className="px-2 py-1.5 text-sm text-muted-foreground bg-muted/50 rounded-md">
          {selectedIds.length} queries selected
        </div>
      )}

      <Accordion type="multiple" className="w-full">
        <AccordionItem value={'Queries'}>
          <AccordionTrigger className="text-sm font-medium hover:no-underline">
            {'Queries'}
          </AccordionTrigger>
          <AccordionContent>
            <ul className="space-y-1">
              {queries.map((query) => (
                <li key={query.id}>
                  <button
                    onClick={() => dispatch(toggleQuerySelection(query.id))}
                    className="w-full text-sm px-2 py-1.5 text-left text-muted-foreground hover:text-foreground hover:bg-muted/50 rounded-sm transition-colors flex items-center gap-2"
                  >
                    <div className="flex-1 truncate">{query.prompt}</div>
                    <div className="flex items-center gap-1 shrink-0">
                      {query.isComplete && (
                        <Check className="h-4 w-4 text-green-500" />
                      )}
                      {selectedIds.includes(query.id) && (
                        <Eye className="h-4 w-4 text-blue-500" />
                      )}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </div>
  );
}
