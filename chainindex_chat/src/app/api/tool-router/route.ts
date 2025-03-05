'use server';
import { generateText, streamText } from 'ai';
import { NextResponse } from 'next/server';
import { createOllama } from 'ollama-ai-provider';
import { z } from 'zod';

const ollama = createOllama({ baseURL: 'http://127.0.0.1:11434/api' });
const MODEL_ID = 'MFDoom/deepseek-r1-tool-calling:32b'; // Or 'llama3.1:70b'


// Define chart tools returning props based on sample datum schema
const tools = {
    renderCandlestickChart: {
        description: 'Generate props for a Recharts candlestick chart based on financial data schema',
        parameters: z.object({
            sample: z.object({
                open: z.number().optional(),
                close: z.number().optional(),
                high: z.number().optional(),
                low: z.number().optional(),
            }).passthrough(),
        }),
        execute: async ({ sample }) => {
            console.log('Generating candlestick chart props for schema:', sample);
            if (!sample.open || !sample.close || !sample.high || !sample.low) {
                throw new Error('Missing required fields (open, close, high, low) for candlestick chart');
            }
            return {
                width: 600,
                height: 400,
                dataKeys: { low: 'low', high: 'high', open: 'open', close: 'close' },
                children: [
                    { type: 'Bar', dataKey: 'low', stackId: 'a', fill: '#ff6347' },
                    { type: 'Bar', dataKey: 'high', stackId: 'a', fill: '#32cd32' },
                    { type: 'XAxis', dataKey: 'name' },
                    { type: 'YAxis' },
                ],
            };
        },
    },
    renderLineChart: {
        description: 'Generate props for a Recharts line chart based on numeric data schema',
        parameters: z.object({
            sample: z.object({
                value: z.number().optional(),
            }).passthrough(),
        }),
        execute: async ({ sample }) => {
            console.log('Generating line chart props for schema:', sample);
            const valueKey = sample.value !== undefined ? 'value' : Object.keys(sample).find(k => typeof sample[k] === 'number') || 'value';
            return {
                width: 600,
                height: 400,
                dataKeys: { value: valueKey },
                children: [
                    { type: 'Line', dataKey: valueKey, stroke: '#4682b4', strokeWidth: 2 },
                    { type: 'XAxis', dataKey: 'name' },
                    { type: 'YAxis' },
                ],
            };
        },
    },
    renderBarChart: {
        description: 'Generate props for a Recharts bar chart based on numeric data schema',
        parameters: z.object({
            sample: z.object({
                value: z.number().optional(),
            }).passthrough(),
        }),
        execute: async ({ sample }) => {
            console.log('Generating bar chart props for schema:', sample);
            const valueKey = sample.value !== undefined ? 'value' : Object.keys(sample).find(k => typeof sample[k] === 'number') || 'value';
            return {
                width: 600,
                height: 400,
                dataKeys: { value: valueKey },
                children: [
                    { type: 'Bar', dataKey: valueKey, fill: '#6a5acd' },
                    { type: 'XAxis', dataKey: 'label' },
                    { type: 'YAxis' },
                ],
            };
        },
    },
    renderStackedBarChart: {
        description: 'Generate props for a Recharts stacked bar chart based on multiple value schema',
        parameters: z.object({
            sample: z.object({
                value1: z.number().optional(),
                value2: z.number().optional(),
            }).passthrough(),
        }),
        execute: async ({ sample }) => {
            console.log('Generating stacked bar chart props for schema:', sample);
            const numericKeys = Object.keys(sample).filter(k => typeof sample[k] === 'number');
            if (numericKeys.length < 2) {
                throw new Error('At least two numeric fields required for stacked bar chart');
            }
            const [value1Key, value2Key] = numericKeys.slice(0, 2);
            return {
                width: 600,
                height: 400,
                dataKeys: { value1: value1Key, value2: value2Key },
                children: [
                    { type: 'Bar', dataKey: value1Key, stackId: 'a', fill: '#ffa500' },
                    { type: 'Bar', dataKey: value2Key, stackId: 'a', fill: '#ff4500' },
                    { type: 'XAxis', dataKey: 'label' },
                    { type: 'YAxis' },
                ],
            };
        },
    },
    renderTreemap: {
        description: 'Generate props for a D3 treemap based on name-value schema',
        parameters: z.object({
            sample: z.object({
                name: z.string().optional(),
                value: z.number().optional(),
            }).passthrough(),
        }),
        execute: async ({ sample }) => {
            console.log('Generating treemap props for schema:', sample);
            const nameKey = sample.name !== undefined ? 'name' : Object.keys(sample).find(k => typeof sample[k] === 'string') || 'name';
            const valueKey = sample.value !== undefined ? 'value' : Object.keys(sample).find(k => typeof sample[k] === 'number') || 'value';
            return {
                width: 600,
                height: 400,
                dataKeys: { name: nameKey, value: valueKey },
                tile: 'treemapSquarify',
            };
        },
    },
};

export async function POST(req: Request) {
    try {
        const datum = await req.json(); // Expect { datum: {...} }
        if (!datum || typeof datum !== 'object') {
            return new Response(JSON.stringify({ error: 'Invalid sample datum' }), {
                status: 400,
                headers: { 'Content-Type': 'application/json' },
            });
        }

        const result = await generateText({
            model: ollama(MODEL_ID),
            maxSteps: 10,
            prompt: `Pick a chart based on this sample row: ${datum}`,
            tools,
            system: `You are an assistant for generating chart props with these tools:
                - renderCandlestickChart: Recharts candlestick chart. Parameters: {"sample": {"open": number, "close": number, "high": number, "low": number}}
                - renderLineChart: Recharts line chart. Parameters: {"sample": {"value": number, "name": string (optional)}}
                - renderBarChart: Recharts bar chart. Parameters: {"sample": {"value": number, "label": string (optional)}}
                - renderStackedBarChart: Recharts stacked bar chart. Parameters: {"sample": {"value1": number, "value2": number, "label": string (optional)}}
                - renderTreemap: D3 treemap. Parameters: {"sample": {"name": string, "value": number}}

                Given a sample datum, respond ONLY with one or more JSON tool calls to generate chart props:
                {"name": "TOOL_NAME", "parameters": {"sample": {...}}}
                Separate multiple calls with a newline.

                Rules:
                - Match the datum’s schema to the tool parameters, using available numeric/string fields if exact matches (e.g., "value", "name") are missing.
                - Always generate at least one tool call.
                - Include all applicable tools based on the schema (one per line).
                - No plain text or extra tags.

                Examples:
                Input: {"id": 1, "open": 100, "close": 105, "high": 110, "low": 95}
                Response: {"name": "renderCandlestickChart", "parameters": {"sample": {"open": 100, "close": 105, "high": 110, "low": 95}}}

                Input: {"id": 2, "sales": 500, "returns": 50, "region": "North"}
                Response: {"name": "renderStackedBarChart", "parameters": {"sample": {"value1": 500, "value2": 50, "label": "North"}}}
                {"name": "renderBarChart", "parameters": {"sample": {"value": 500, "label": "North"}}}
                {"name": "renderLineChart", "parameters": {"sample": {"value": 500, "name": "North"}}}
                {"name": "renderTreemap", "parameters": {"sample": {"name": "North", "value": 500}}}`,

        });

        return NextResponse.json(result, { status: 200 })
    } catch (e) {
        console.error('Error in streamText:', e);
        return new Response(JSON.stringify({ error: 'Failed to process request' }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' },
        });
    }
}
