"use client"

import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@workspace/ui/components/accordion"

export interface Collection {
  id: string
  title: string
  items: {
    id: string
    label: string
  }[]
}

interface CollectionListProps {
  collections: Collection[]
  onItemClick?: (collectionId: string, itemId: string) => void
}

export function CollectionList({ collections, onItemClick }: CollectionListProps) {
  return (
    <Accordion type="multiple" className="w-full">
      {collections.map((collection) => (
        <AccordionItem value={collection.id} key={collection.id}>
          <AccordionTrigger className="text-sm font-medium hover:no-underline">{collection.title}</AccordionTrigger>
          <AccordionContent>
            <ul className="space-y-1">
              {collection.items.map((item) => (
                <li key={item.id}>
                  <button
                    onClick={() => onItemClick?.(collection.id, item.id)}
                    className="w-full text-sm px-2 py-1.5 text-left text-muted-foreground hover:text-foreground hover:bg-muted/50 rounded-sm transition-colors"
                  >
                    {item.label}
                  </button>
                </li>
              ))}
            </ul>
          </AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  )
}

