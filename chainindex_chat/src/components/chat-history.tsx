import { useAppDispatch, useAppSelector } from '@/client/store/hooks';
import {
  selectAllQueries,
  selectSelectedQueryIds,
  toggleQuerySelection,
} from '@/lib/store/queriesSlice';
import type { Message } from 'ai';
import { format } from 'date-fns';
import { Check, Eye } from 'lucide-react';

interface ChatHistoryProps {
  messages?: Message[];
}

export function ChatHistory({}: ChatHistoryProps) {
  const queries = useAppSelector(selectAllQueries);
  const selectedIds = useAppSelector(selectSelectedQueryIds);
  const dispatch = useAppDispatch();

  return (
    <div className="space-y-4">
      {selectedIds.length > 1 && (
        <div className="px-2 py-1.5 text-sm text-muted-foreground bg-muted/50 rounded-md">
          {selectedIds.length} queries selected
        </div>
      )}

      <div className="space-y-2">
        {queries.map((query, index) => (
          <div
            key={index}
            className="rounded-lg border bg-card p-3 text-card-foreground hover:bg-muted/50 transition-colors"
          >
            <p className="text-sm line-clamp-3">
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
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
