"use client"

import { Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ComposedChart } from "recharts"
import { Card } from "@workspace/ui/components/card"

interface PriceData {
  date: string
  open: number
  high: number
  low: number
  close: number
  volume: number
}

interface PriceChartProps {
  data: PriceData[]
}

export function PriceChart({ data }: PriceChartProps) {
  // Custom candle renderer
  const renderCandleStick = (props: any) => {
    const { x, y, width, height, payload } = props
    const fill = payload.close > payload.open ? "#22c55e" : "#ef4444"
    const stroke = fill

    // Calculate wick positions
    const wickX = x + width / 2
    const wickTop = Math.min(y, y + height)
    const wickBottom = Math.max(y, y + height)
    const highY =
      y + height * (1 - (payload.high - Math.min(payload.open, payload.close)) / (payload.high - payload.low))
    const lowY = y + height * (1 - (payload.low - Math.min(payload.open, payload.close)) / (payload.high - payload.low))

    return (
      <g key={`candle-${x}`}>
        {/* Wick */}
        <line x1={wickX} y1={highY} x2={wickX} y2={lowY} stroke={stroke} strokeWidth={1} />
        {/* Candle body */}
        <rect
          x={x}
          y={Math.min(
            y + height * (1 - (payload.open - payload.low) / (payload.high - payload.low)),
            y + height * (1 - (payload.close - payload.low) / (payload.high - payload.low)),
          )}
          width={width}
          height={Math.abs((height * (payload.open - payload.close)) / (payload.high - payload.low))}
          fill={fill}
          stroke={stroke}
        />
      </g>
    )
  }

  // Custom tooltip
  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload
      return (
        <Card className="p-3 !bg-background/95 backdrop-blur-sm">
          <div className="space-y-1">
            <p className="text-sm font-medium">{data.date}</p>
            <p className="text-sm text-muted-foreground">
              Open: <span className="font-medium text-foreground">${data.open.toFixed(2)}</span>
            </p>
            <p className="text-sm text-muted-foreground">
              High: <span className="font-medium text-foreground">${data.high.toFixed(2)}</span>
            </p>
            <p className="text-sm text-muted-foreground">
              Low: <span className="font-medium text-foreground">${data.low.toFixed(2)}</span>
            </p>
            <p className="text-sm text-muted-foreground">
              Close: <span className="font-medium text-foreground">${data.close.toFixed(2)}</span>
            </p>
            <p className="text-sm text-muted-foreground">
              Volume: <span className="font-medium text-foreground">{data.volume.toLocaleString()}</span>
            </p>
          </div>
        </Card>
      )
    }
    return null
  }

  return (
    <div className="w-full p-4 space-y-4">
      <div className="h-[400px]">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart
            data={data}
            margin={{
              top: 20,
              right: 20,
              bottom: 20,
              left: 40,
            }}
          >
            <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
            <XAxis dataKey="date" scale="band" className="text-xs text-muted-foreground" />
            <YAxis yAxisId="price" domain={["auto", "auto"]} className="text-xs text-muted-foreground" />
            <YAxis
              yAxisId="volume"
              orientation="right"
              domain={["auto", "auto"]}
              className="text-xs text-muted-foreground"
            />
            <Tooltip content={<CustomTooltip />} />
            <Bar
              dataKey="volume"
              yAxisId="volume"
              fill="currentColor"
              opacity={0.3}
              className="fill-muted-foreground"
            />
            {data.map((entry, index) =>
              renderCandleStick({
                key: `candle-${index}`,
                x: index * (100 / data.length) + "%",
                y: 0,
                width: 10,
                height: 300,
                payload: entry,
              }),
            )}
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

