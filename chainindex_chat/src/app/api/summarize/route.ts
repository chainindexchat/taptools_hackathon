import { createOllama } from 'ollama-ai-provider';
import { streamObject, streamText } from "ai";
import { queryDescriptionSchema } from '@/client/lib/types';

const ollama = createOllama({
  baseURL: 'http://127.0.0.1:11434/api'
});
const MODEL_ID = 'llama3.3:70b-instruct-q2_K';

export async function POST(req: Request) {
  try {
    const { sqlQuery } = await req.json();

    if (!sqlQuery || typeof sqlQuery !== 'string' || sqlQuery.trim() === '') {
      return new Response(JSON.stringify({ error: "Invalid or missing SQL query" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const systemPrompt = `You are a SQL (Postgres) expert tasked with summarizing the purpose of an SQL query in a concise, human-readable explanation.

Analyze the provided SQL query and describe its purpose in plain English, focusing on what data it retrieves, filters, or manipulates. Provide only a single, clear sentence or phrase explaining the query's intent, without including the query itself or any additional text.

**Critical Instruction:** Your entire response must be a single, valid JSON object starting with '{' and ending with '}'. Do NOT include any text, code blocks, or explanations outside this JSON. The JSON must match this structure:
- "description": a string representing the purpose of the SQL query.

**Example 1:**
SQL query: "SELECT product_id, SUM(quantity) FROM orders GROUP BY product_id"
Response:
{
  "description": "Calculates the total quantity of each product ordered by summing the quantities from the orders table, grouped by product ID."
}

**Example 2:**
SQL query: "SELECT time, value FROM metrics WHERE unit = 'ABC'"
Response:
{
  "description": "Retrieves the time and value columns from the metrics table for the unit 'ABC'."
}

Before responding, ensure that the description accurately reflects the purpose of the provided SQL query and that the JSON is correctly formatted.`;

    const result = await streamObject({
      model: ollama(MODEL_ID),
      schema: queryDescriptionSchema,
      system: systemPrompt,
      prompt: `Summarize the purpose of this SQL query: "${sqlQuery}"`,
    });

    return result.toTextStreamResponse();

  } catch (error) {
    console.error("Error processing request:", error);
    return new Response(JSON.stringify({ error: "Failed to generate summarization" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}