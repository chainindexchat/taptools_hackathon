'use client';

import { useState } from 'react';
import { useAppSelector } from '@/lib/hooks/useAppSelector';
import { selectContentByPath } from '@/lib/store/queriesSlice';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';
import { ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';

export function JsonInspector() {
  const selectedContent = useAppSelector(selectContentByPath);

  if (!selectedContent) {
    return (
      <div className="text-muted-foreground text-sm">
        Select content to inspect
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="text-sm font-medium text-muted-foreground uppercase tracking-wider">
        {selectedContent.label}
      </div>
      <JsonNode data={selectedContent.value} level={0} />
    </div>
  );
}

interface JsonNodeProps {
  data: any;
  level: number;
  isLast?: boolean;
}

function JsonNode({ data, level, isLast = true }: JsonNodeProps) {
  const [isOpen, setIsOpen] = useState(true);
  const indent = level * 16;

  if (data === null) return <span className="text-muted-foreground">null</span>;
  if (data === undefined)
    return <span className="text-muted-foreground">undefined</span>;
  if (typeof data === 'string')
    return <span className="text-green-600 dark:text-green-400">"{data}"</span>;
  if (typeof data === 'number')
    return <span className="text-blue-600 dark:text-blue-400">{data}</span>;
  if (typeof data === 'boolean')
    return (
      <span className="text-purple-600 dark:text-purple-400">
        {data.toString()}
      </span>
    );

  if (Array.isArray(data)) {
    if (data.length === 0) return <span>[]</span>;

    return (
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <div className="flex items-start">
          <CollapsibleTrigger className="group">
            <ChevronRight
              className={cn(
                'h-4 w-4 shrink-0 transition-transform duration-200',
                isOpen && 'rotate-90'
              )}
            />
          </CollapsibleTrigger>
          <span>[</span>
        </div>
        <CollapsibleContent>
          {data.map((item, index) => (
            <div key={index} style={{ paddingLeft: indent + 16 }}>
              <JsonNode
                data={item}
                level={level + 1}
                isLast={index === data.length - 1}
              />
              {index < data.length - 1 && <span>,</span>}
            </div>
          ))}
        </CollapsibleContent>
        <div style={{ paddingLeft: indent }}>]</div>
      </Collapsible>
    );
  }

  if (typeof data === 'object') {
    const entries = Object.entries(data);
    if (entries.length === 0) return <span>{'{}'}</span>;

    return (
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <div className="flex items-start">
          <CollapsibleTrigger className="group">
            <ChevronRight
              className={cn(
                'h-4 w-4 shrink-0 transition-transform duration-200',
                isOpen && 'rotate-90'
              )}
            />
          </CollapsibleTrigger>
          <span>{'{'}</span>
        </div>
        <CollapsibleContent>
          {entries.map(([key, value], index) => (
            <div key={key} style={{ paddingLeft: indent + 16 }}>
              <span className="text-muted-foreground">"{key}"</span>
              <span className="text-muted-foreground">: </span>
              <JsonNode
                data={value}
                level={level + 1}
                isLast={index === entries.length - 1}
              />
              {index < entries.length - 1 && <span>,</span>}
            </div>
          ))}
        </CollapsibleContent>
        <div style={{ paddingLeft: indent }}>{'}'}</div>
      </Collapsible>
    );
  }

  return null;
}
