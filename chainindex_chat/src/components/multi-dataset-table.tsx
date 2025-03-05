'use client';

import { useAppDispatch, useAppSelector } from '@/client/store/hooks';
import { selectSelectedResults } from '@/client/store/sliceChartStoryApi';

import { setSelectedContentPath } from '@/lib/store/queriesSlice';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@workspace/ui/components/table';

export function MultiDatasetTable() {
  const selectedResults = useAppSelector(selectSelectedResults);
  const dispatch = useAppDispatch();
  const handleSelect = (label: string, path: string) => (e) => {
    dispatch(setSelectedContentPath({ label, path }));
  };

  // Get all unique columns from all datasets
  const allColumns = new Set<string>();
  selectedResults
    .map((item) => ({
      ...item,
      data: (item as unknown as any)?.data?.map((d) => {
        const { sp_connection_name, sp_ctx, _ctx, ...rest } = d;
        return rest;
      }),
    }))
    .forEach((query) => {
      if (query && query.data && query.data.length > 0) {
        Object.keys(query.data[0]).forEach((key) => allColumns.add(key));
      }
    });

  // Merge datasets
  const mergedData = selectedResults.flatMap(
    (query) =>
      query?.data?.map((row) => ({
        ...row,
        _queryId: query.requestId,
        // _queryPrompt: query.prompt,
      })) ?? []
  );

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            {Array.from(allColumns).map((column) => (
              <TableHead key={column}>{column}</TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {mergedData.map((row, index) => (
            <TableRow
              key={`${row._queryId}-${index}`}
              className="cursor-pointer hover:bg-muted/50"
              onClick={handleSelect(
                'table row',
                `chartStoryApi.mutations.${row._queryId}.data[${index}]`
              )}
            >
              {Array.from(allColumns).map((column) => (
                <TableCell key={column}>{formatValue(row[column])}</TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function formatValue(value: any): string {
  if (value === null || value === undefined) return '-';
  if (typeof value === 'number') return value.toLocaleString();
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (value instanceof Date) return value.toLocaleString();
  return String(value);
}
