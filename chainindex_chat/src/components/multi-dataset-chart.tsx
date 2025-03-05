"use client"

import { useAppSelector } from "@/lib/hooks/useAppSelector"
import { selectSelectedQueries } from "@/lib/store/queriesSlice"
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts"
import { Card } from "@workspace/ui/components/card"

const COLORS = ["hsl(var(--primary))", "hsl(var(--secondary))", "hsl(var(--accent))", "hsl(var(--destructive))"]

export function MultiDatasetChart() {
  const selectedQueries = useAppSelector(selectSelectedQueries)

  // Assuming all datasets have a common x-axis field (date)
  const mergedData = mergeDatasets(selectedQueries)

  return (
    <div className="h-[400px] w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={mergedData} margin={{ top: 20, right: 30, left: 20, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
          <XAxis dataKey="date" className="text-xs text-muted-foreground" />
          {selectedQueries.map((query, index) => (
            <YAxis
              key={query.id}
              yAxisId={query.id}
              orientation={index % 2 === 0 ? "left" : "right"}
              className="text-xs text-muted-foreground"
            />
          ))}
          <Tooltip content={<CustomTooltip />} />
          <Legend />
          {selectedQueries.map((query, index) => (
            <Line
              key={query.id}
              yAxisId={query.id}
              type="monotone"
              dataKey={`${query.id}_close`}
              name={truncate(query.prompt, 30)}
              stroke={COLORS[index % COLORS.length]}
              dot={false}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

function mergeDatasets(queries: any[]) {
  // Create a map of all dates
  const dateMap = new Map<string, any>()

  queries.forEach((query) => {
    query.data?.forEach((point: any) => {
      if (!dateMap.has(point.date)) {
        dateMap.set(point.date, { date: point.date })
      }
      const entry = dateMap.get(point.date)
      entry[`${query.id}_close`] = point.close
    })
  })

  return Array.from(dateMap.values()).sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
}

function CustomTooltip({ active, payload, label }: any) {
  if (active && payload && payload.length) {
    return (
      <Card className="p-3 !bg-background/95 backdrop-blur-sm">
        <div className="space-y-1">
          <p className="text-sm font-medium">{label}</p>
          {payload.map((entry: any) => (
            <p key={entry.dataKey} className="text-sm">
              <span style={{ color: entry.color }}>{entry.name}: </span>
              {entry.value?.toFixed(2)}
            </p>
          ))}
        </div>
      </Card>
    )
  }
  return null
}

function truncate(str: string, n: number) {
  return str.length > n ? str.slice(0, n - 1) + "..." : str
}

