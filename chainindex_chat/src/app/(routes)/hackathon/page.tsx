'use client';
import { LayoutDashboard, LineChart, Send, Table } from 'lucide-react'; 
import { Button } from '@/components/ui/button'; 
import { Textarea } from '@/components/ui/textarea'; 
import { v4 as uuidv4 } from 'uuid';

import {
  X,
  PanelLeftClose,
  PanelRightClose,
  PanelLeft,
  PanelRight,
} from 'lucide-react';
import {
  
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from 'react';

import {
  ToggleGroup,
  ToggleGroupItem,
} from '@workspace/ui/components/toggle-group';

import { JsonInspector } from '@/components/json-inspector';
import { useAppDispatch } from '@/lib/hooks/useAppDispatch';
import { useAppSelector } from '@/lib/hooks/useAppSelector';
import {
  selectSelectedQueries,
  QueryState,
  setQueryState,
} from '@/lib/store/queriesSlice';
import {
  ResizablePanelGroup,
  ResizablePanel,
  ResizableHandle,
} from '@/components/ui/resizable';
// import { MultiQueryDescription } from '@/components/multi-query-description';
// import { MultiQuerySql } from '@/components/multi-query-sql';
// import { MultiDatasetChart } from '@/components/multi-dataset-chart';
import { MultiDatasetTable } from '@/components/multi-dataset-table';
import { cn } from '@/lib/utils';
import { experimental_useObject } from '@ai-sdk/react';
import { queryDescriptionSchema, singleQuerySchema } from '@/client/lib/types';
import {
  usePostRunSqlMutation,
  // usePostToolRouterMutation,
} from '@/client/store/sliceChartStoryApi';
// import { MultiQueryPrompt } from '@/components/multi-query-prompt';
import { SummarySection } from '@/components/multi-query-summary';
import { ChatHistory } from '@/components/chat-history';
// import { isArray } from 'lodash';
import ChartRenderer from '@/components/chart';

export default function Home() {
  const [visibleSections, setVisibleSections] = useState<string[]>([
    'Summary',
    'Chart',
    'Table',
  ]);
  const [prompt, setPrompt] = useState(
    'use taptools to show me the ohlcv price data for the wmtx token'
  );
  const [leftPanelOpen, setLeftPanelOpen] = useState(true);
  const [rightPanelOpen, setRightPanelOpen] = useState(true);
  const [prevLeftSize, setPrevLeftSize] = useState(25);
  const [prevRightSize, setPrevRightSize] = useState(25);
  const [panelSizes, setPanelSizes] = useState([25, 50, 25]); // [left, center, right]
  const panelGroupRef = useRef(null);
  const [currentQueryId, setCurrentQueryId] = useState<string>(uuidv4());

  const dispatch = useAppDispatch();
  const selectedQueries = useAppSelector(selectSelectedQueries);
  const currentQuery = selectedQueries[0];
  // Set up useCompletion for SQL generation

  const {
    object: queryDescription,
    submit: submitQueryDescription,
    isLoading: isLoadingQueryDescription,
  } = experimental_useObject({
    api: '/api/summarize',
    schema: queryDescriptionSchema,
    onFinish: ({ object }) => {
      if (currentQueryId) {
        const { description } = object ?? {};
        dispatch(
          setQueryState({
            id: currentQueryId,
            query: {
              description,
            },
          })
        );
      }
    },
  });
  useEffect(() => {
    if (currentQueryId && queryDescription) {
      dispatch(
        setQueryState({
          id: currentQueryId,
          query: {
            description: queryDescription.description,
          },
        })
      );
    }
  }, [queryDescription, currentQueryId]);

  const [postSql] = usePostRunSqlMutation();
  // const [postToolRouter] = usePostToolRouterMutation();

  const {
    object: sqlGeneration,
    submit,
    isLoading,
  } = experimental_useObject({
    id: currentQueryId,
    api: '/api/generate',
    schema: singleQuerySchema,
    onFinish: async ({ object }) => {
      const { query: sqlQuery, tableName } = object ?? {};
      if (currentQueryId && sqlQuery) {
        submitQueryDescription({ sqlQuery });
        const { requestId, ...rest } = postSql({ query: sqlQuery });
        dispatch(
          setQueryState({
            id: currentQueryId,
            query: {
              sqlQuery,
              isGenerating: false,
              tableName,
              finishedAt: new Date().toISOString(),
              requestId,
            },
          })
        );
        // const sqlResult = await rest.unwrap();
        // if (sqlResult && sqlResult.length > 0) {
        //   console.log('sqlResult', sqlResult);
        //   const toolCallResult = await postToolRouter(sqlResult[0]);
        //   console.log('toolCallResult', toolCallResult);
        // }
      }
    },
  });

  useEffect(() => {
    if (currentQueryId && sqlGeneration) {
      dispatch(
        setQueryState({
          id: currentQueryId,
          query: {
            sqlQuery: sqlGeneration.query,
            isGenerating: isLoading,
            tableName: sqlGeneration.tableName,
          },
        })
      );
    }
  }, [sqlGeneration, currentQueryId]);
  const handleSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    // Generate a UUID
    // const queryId = uuidv4();
    // setCurrentQueryId(queryId);

    // Define an empty query structure matching QueryState
    const emptyQuery: QueryState = {
      id: currentQueryId,
      timestamp: new Date().toISOString(),
      prompt,
      sqlQuery: '', // Empty initially
      description: null,
      data: null,
      chartConfig: null,
      isGenerating: true,
      isExecuting: false,
      isGeneratingDescription: false,
      error: null,
      isComplete: false,
      finishedAt: null,
      tableName: null,
      requestId: null,
    };
    dispatch(setQueryState({ id: currentQueryId, query: emptyQuery }));

    submit({ input: prompt }); // Send the input as a JSON sqlGeneration
    setPrompt('');
  };

  const toggleLeftPanel = () => {
    if (leftPanelOpen) {
      setPrevLeftSize(panelSizes[0]);
      setPanelSizes([0, 100 - panelSizes[2], panelSizes[2]]);
    } else {
      const newLeft = prevLeftSize;
      setPanelSizes([newLeft, 100 - newLeft - panelSizes[2], panelSizes[2]]);
    }
    setLeftPanelOpen(!leftPanelOpen);
  };

  const toggleRightPanel = () => {
    if (rightPanelOpen) {
      setPrevRightSize(panelSizes[2]);
      setPanelSizes([panelSizes[0], 100 - panelSizes[0], 0]);
    } else {
      const newRight = prevRightSize;
      setPanelSizes([panelSizes[0], 100 - panelSizes[0] - newRight, newRight]);
    }
    setRightPanelOpen(!rightPanelOpen);
  };

  useEffect(() => {
    if (panelGroupRef.current) {
      panelGroupRef.current.setLayout(panelSizes);
    }
  }, [panelSizes]);

  return (
    <div className="flex flex-col h-full justify-start  ">
      <ResizablePanelGroup
        direction="horizontal"
        className="flex-1"
        ref={panelGroupRef}
      >
        <ResizablePanel
          defaultSize={25}
          minSize={0}
          maxSize={40}
          onResize={(newLeft) =>
            setPanelSizes((prev) => [newLeft, 100 - newLeft - prev[2], prev[2]])
          }
          className={cn(
            'transition-all duration-300 ease-in-out',
            !leftPanelOpen && 'min-w-[0px] !w-[0px]'
          )}
        >
          <div className="h-full flex flex-col">
            <div className="flex-1 overflow-y-auto p-4">
              <ChatHistory />
            </div>
          </div>
        </ResizablePanel>

        {leftPanelOpen && <ResizableHandle />}

        <ResizablePanel defaultSize={50} minSize={30}>
          <div className="h-full flex flex-col">
            <div className="sticky top-0 z-50 bg-background/80 backdrop-blur-sm ">
              <form onSubmit={handleSubmit} className="p-1">
                <div className="relative flex items-center gap-2">
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={toggleLeftPanel}
                    className="shrink-0"
                  >
                    {leftPanelOpen ? (
                      <PanelLeftClose className="h-4 w-4" />
                    ) : (
                      <PanelRight className="h-4 w-4" />
                    )}
                  </Button>

                  <div className="relative flex-1">
                    <Textarea
                      value={prompt}
                      onChange={(e) => {
                        setPrompt(e.target.value);
                        e.target.style.height = 'auto';
                        e.target.style.height = `${e.target.scrollHeight}px`;
                      }}
                      placeholder="Describe your query..."
                      disabled={currentQuery?.isGenerating}
                      className="w-full min-h-[40px] pr-10 pb-10 resize-none overflow-hidden border-2 border-secondary hover:border-primary focus-visible:ring-0 focus-visible:ring-offset-0 focus-visible:border-primary transition-colors"
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' && !e.shiftKey) {
                          e.preventDefault();
                          handleSubmit(e);
                        }
                      }}
                      style={{
                        height: '40px',
                        minHeight: '40px',
                        maxHeight: '200px',
                      }}
                    />
                    <Button
                      type="submit"
                      disabled={currentQuery?.isGenerating || !prompt.trim()}
                      className="absolute right-2 bottom-2 shrink-0 transition-colors hover:bg-primary/90 disabled:cursor-not-allowed cursor-pointer z-10"
                      onClick={handleSubmit}
                    >
                      <Send className="h-4 w-4" />
                      <span className="sr-only">Submit</span>
                    </Button>
                  </div>

                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={toggleRightPanel}
                    className="shrink-0"
                  >
                    {rightPanelOpen ? (
                      <PanelRightClose className="h-4 w-4" />
                    ) : (
                      <PanelLeft className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </form>

              <div>
                <div className="flex items-center justify-center gap-1">
                  <ToggleGroup
                    type="multiple"
                    value={visibleSections}
                    onValueChange={(value) => {
                      if (value.length > 0) {
                        setVisibleSections(value);
                      }
                    }}
                  >
                    <ToggleGroupItem
                      value="Summary"
                      size="sm"
                      className="h-8 w-8 p-0 data-[state=on]:bg-muted"
                      aria-label="Toggle Summary"
                    >
                      <LayoutDashboard className="h-4 w-4" />
                    </ToggleGroupItem>
                    <ToggleGroupItem
                      value="Chart"
                      size="sm"
                      className="h-8 w-8 p-0 data-[state=on]:bg-muted"
                      aria-label="Toggle Chart"
                    >
                      <LineChart className="h-4 w-4" />
                    </ToggleGroupItem>
                    <ToggleGroupItem
                      value="Table"
                      size="sm"
                      className="h-8 w-8 p-0 data-[state=on]:bg-muted"
                      aria-label="Toggle Table"
                    >
                      <Table className="h-4 w-4" />
                    </ToggleGroupItem>
                  </ToggleGroup>
                </div>
              </div>
            </div>

            <main className="flex-1 overflow-y-auto p-4 space-y-4">
              {visibleSections.includes('Summary') && (
                <div className="rounded-lg border bg-card p-4">
                  <h2 className="text-lg font-semibold mb-2">Summary</h2>
                  <SummarySection />
                </div>
              )}

              {visibleSections.includes('Chart') && (
                <div className="rounded-lg border bg-card">
                  <h2 className="text-lg font-semibold p-4 border-b">Chart</h2>
                  <div className="p-4">
                    {/* <MultiDatasetChart /> */}
                    <ChartRenderer />
                  </div>
                </div>
              )}

              {visibleSections.includes('Table') && (
                <div className="rounded-lg border bg-card">
                  <h2 className="text-lg font-semibold p-4 border-b">Table</h2>
                  <div className="p-4">
                    <MultiDatasetTable />
                  </div>
                </div>
              )}
            </main>
          </div>
        </ResizablePanel>

        {rightPanelOpen && <ResizableHandle />}

        <ResizablePanel
          defaultSize={25}
          minSize={0}
          maxSize={40}
          onResize={(newRight) =>
            setPanelSizes((prev) => [
              prev[0],
              100 - prev[0] - newRight,
              newRight,
            ])
          }
          className={cn(
            'transition-all duration-300 ease-in-out',
            !rightPanelOpen && 'min-w-[0px] !w-[0px]'
          )}
        >
          <div className="h-full flex flex-col">
            <div className="flex-1 overflow-y-auto p-4">
              <JsonInspector data={currentQuery?.data ?? {}} />
            </div>
          </div>
        </ResizablePanel>
      </ResizablePanelGroup>
    </div>
  );
}
