'use client';
import React, { useState, useEffect, useMemo } from 'react';
import { BarChart, Bar, LineChart, Line, XAxis, YAxis } from 'recharts';
import * as d3 from 'd3-hierarchy';
import { useAppDispatch, useAppSelector } from '@/client/store/hooks';
import {
  selectSelectedResults,
  usePostToolRouterMutation,
} from '@/client/store/sliceChartStoryApi';

interface ChartProps {
  width: number;
  height: number;
  dataKeys: { [key: string]: string };
  children?: { type: string; [key: string]: any }[];
  tile?: string;
}

interface ChartRendererProps {
  //   datum: Record<string, any>;
  //   dataset: Record<string, any>[];
}

const ChartRenderer: React.FC<ChartRendererProps> = () => {
  const selectedResults = useAppSelector(selectSelectedResults);
  const dispatch = useAppDispatch();
  const dataset = useMemo(() => {
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
    const datasets = selectedResults.flatMap(
      (query) =>
        query?.data?.map((row) => ({
          ...row,
          _queryId: query.requestId,
          // _queryPrompt: query.prompt,
        })) ?? []
    );
    return datasets;
  }, [selectedResults]);
  //   const [chartPropsList, setChartPropsList] = useState<ChartProps[] | null>(
  //     null
  //   );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [postToolRouter, { data, isLoading, isSuccess }] =
    usePostToolRouterMutation();

  const chartPropsList = useMemo(() => {
    return data?.toolResults.map((toolResult) => toolResult.result);
  }, [data]);

  useEffect(() => {
    const fetchChartProps = async () => {
      try {
        setLoading(true);
        const [datum] = dataset;
        if (datum && !chartPropsList && !isLoading && !data) {
          postToolRouter({ datum });
        }
        // console.log('response', response);
        // if (!response.ok) throw new Error('Failed to fetch chart props');
        // const text = await response.text();
        // const toolCalls = text
        //   .split('\n')
        //   .filter(Boolean)
        //   .map((call) => {
        //     const parsed = JSON.parse(call);
        //     const tool = tools[parsed.name];
        //     if (!tool) throw new Error(`Unknown tool: ${parsed.name}`);
        //     return tool.execute(parsed.parameters);
        //   });
        // const propsList = await Promise.all(toolCalls);
        // setChartPropsList(propsList);
      } catch (e) {
        setError(e instanceof Error ? e.message : 'An error occurred');
      } finally {
        setLoading(false);
      }
    };
    fetchChartProps();
  }, [dataset]);

  const applyDataKeys = (
    data: Record<string, any>[],
    dataKeys: { [key: string]: string }
  ) => {
    return data.map((item) => {
      const mapped = { ...item };
      Object.entries(dataKeys).forEach(([propKey, dataKey]) => {
        if (item[dataKey] !== undefined) mapped[propKey] = item[dataKey];
      });
      return mapped;
    });
  };

  if (loading) return <div>Loading charts...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div>
      {chartPropsList?.map((props, index) => {
        const mappedData = applyDataKeys(dataset, props.dataKeys);

        if (props.children?.some((child) => child.type === 'Bar')) {
          const isStacked = props.children.some(
            (child) =>
              child.stackId &&
              props.children.filter((c) => c.stackId === child.stackId).length >
                1
          );
          return (
            <div key={index} style={{ marginBottom: '20px' }}>
              <h3>
                {isStacked ? 'Stacked Bar Chart' : 'Candlestick/Bar Chart'}
              </h3>
              <BarChart
                width={props.width}
                height={props.height}
                data={mappedData}
              >
                {props.children.map((child, i) =>
                  child.type === 'Bar' ? (
                    <Bar
                      key={i}
                      dataKey={child.dataKey}
                      stackId={child.stackId}
                      fill={child.fill}
                    />
                  ) : child.type === 'XAxis' ? (
                    <XAxis key={i} dataKey={child.dataKey} />
                  ) : child.type === 'YAxis' ? (
                    <YAxis key={i} />
                  ) : null
                )}
              </BarChart>
            </div>
          );
        }

        if (props.children?.some((child) => child.type === 'Line')) {
          return (
            <div key={index} style={{ marginBottom: '20px' }}>
              <h3>Line Chart</h3>
              <LineChart
                width={props.width}
                height={props.height}
                data={mappedData}
              >
                {props.children.map((child, i) =>
                  child.type === 'Line' ? (
                    <Line
                      key={i}
                      dataKey={child.dataKey}
                      stroke={child.stroke}
                      strokeWidth={child.strokeWidth}
                    />
                  ) : child.type === 'XAxis' ? (
                    <XAxis key={i} dataKey={child.dataKey} />
                  ) : child.type === 'YAxis' ? (
                    <YAxis key={i} />
                  ) : null
                )}
              </LineChart>
            </div>
          );
        }

        if (props.tile) {
          const root = d3
            .hierarchy({
              name: 'root',
              children: mappedData.map((d) => ({
                name: d[props.dataKeys.name] || 'Unknown',
                value: d[props.dataKeys.value],
              })),
            })
            .sum((d) => d.value || 0);
          d3.treemap().size([props.width, props.height]).tile(d3[props.tile])(
            root
          );
          return (
            <div key={index} style={{ marginBottom: '20px' }}>
              <h3>Treemap</h3>
              <svg width={props.width} height={props.height}>
                {root.leaves().map((leaf, i) => (
                  <rect
                    key={i}
                    x={leaf.x0}
                    y={leaf.y0}
                    width={leaf.x1 - leaf.x0}
                    height={leaf.y1 - leaf.y0}
                    fill="#69b3a2"
                  >
                    <title>
                      {leaf.data.name}: {leaf.value}
                    </title>
                  </rect>
                ))}
              </svg>
            </div>
          );
        }

        return null;
      })}
    </div>
  );
};
export default ChartRenderer;
