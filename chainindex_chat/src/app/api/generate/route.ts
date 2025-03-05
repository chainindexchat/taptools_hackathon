'use server';
import { createOllama } from 'ollama-ai-provider';
import { streamObject } from "ai";

import { getPool } from '@/server/providers/postgresProvider';
import { singleQuerySchema } from '@/client/lib/types';

const ollama = createOllama({
  baseURL: 'http://127.0.0.1:11434/api'
});
const MODEL_ID = 'llama3.3:70b-instruct-q2_K';


export async function POST(req: Request) {
  try {
    const { input } = await req.json();

    const embedding = await getEmbedding(input);

    // Convert embedding array to PostgreSQL vector format (e.g., '[0.1,0.2,...]')
    const embeddingString = `[${embedding.join(",")}]`;

    // Get a pool for the target database
    const pool = getPool('pgvector');

    // Get the most similar table schema from pgvector
    const tableSchemas = await getTableSchemaFromVector(pool, embeddingString);

    const schemaText = tableSchemas.map(s =>
      `Table: ${s.table}\nSchema: ${s.schema}`
    ).join('\n\n');
    const tableNames = tableSchemas.map(s => s.table).join(', ');

    // Get the most similar token info from pgvector
    const tokenInfos = await getTokenInfoFromVector(pool, embeddingString);

    const tokenInfo = tokenInfos.map(s =>
      `Token Info: ${s.tokenInfo}\nUnit: ${s.unit}`
    ).join('\n\n');


    // Stream a single SQL query object
    const result = streamObject({
      model: ollama(MODEL_ID),
      schema: singleQuerySchema,
      system: `You are a SQL (Postgres) expert tasked with generating a single SQL query based on user input.

            Required table names list: ${tableNames}

            The schemas for the required tables appear below:

            ${schemaText}

            If the prompt mentions a token, filter the query using this token information:

            ${tokenInfo}

            The unit is the primary key for the token and can be used in WHERE clauses or JOIN conditions on tables with a unit column.

            When generating the query:
            - Only use table names from the available table names list, you are absolutely required to only use the table names in this list after the FROM keyword in the SQL query.
            - If the user's prompt mentions a token, use the provided unit to filter the query on tables that have a unit column.

            **Critical Instruction:** Your entire response must be a single, valid JSON object starting with '{' and ending with '}'. Do NOT include any text, code blocks, or explanations outside this JSON. The JSON must match this structure:
            - "tableName": a string representing the table name.
            - "query": a string representing the SQL query.

            **Example 1:**
            User prompt: "Show total sales by product"
            Response:
            {
            "tableName": "sales_db.orders",
            "query": "SELECT product_id, SUM(quantity) FROM orders GROUP BY product_id"
            }

            **Example 2:**
            User prompt: "Get data for token ABC"
            Response:
            {
            "tableName": "token_db.metrics",
            "query": "SELECT time, value FROM metrics WHERE unit = 'ABC'"
            }

            Before responding, verify that the "tableName" is from the required table names list and that the JSON is correctly formatted.`,
      prompt: `Based on the user’s request: "${input}", generate a single SQL retrieval query using the provided table schemas and token information. Format the response as a valid JSON object with "tableName" and "query".`,
    });

    return result.toTextStreamResponse();

  } catch (e) {
    console.error("Error initiating stream:", e);
    return new Response(JSON.stringify({ error: "Failed to generate query stream" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
};

// Helper functions (unchanged)
async function getTableSchemaFromVector(client, inputEmbedding) {
  try {
    const queryText = `
            SELECT table_name, schema_text
            FROM schema_embeddings
            ORDER BY embedding <-> $1::vector ASC
            LIMIT 3;
        `;
    const res = await client.query(queryText, [inputEmbedding]);

    if (res.rows.length === 0) {
      throw new Error("No matching schema found");
    }

    return res.rows.map(row => ({
      table: row.table_name,
      schema: row.schema_text
    }));
  } catch (e) {
    console.error("Error querying pgvector:", e);
    throw e;
  }
}

async function getTokenInfoFromVector(client, inputEmbedding) {
  try {
    const queryText = `
            SELECT unit, token_text
            FROM token_embeddings
            ORDER BY embedding <-> $1::vector ASC
            LIMIT 1;
        `;
    const res = await client.query(queryText, [inputEmbedding]);

    if (res.rows.length === 0) {
      throw new Error("No matching token info found");
    }

    return res.rows.map(row => ({
      unit: row.unit,
      tokenInfo: row.token_text
    }));
  } catch (e) {
    console.error("Error querying pgvector:", e);
    throw e;
  }
}

async function getEmbedding(input) {

  const response = await fetch('http://localhost:11434/api/embeddings', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'nomic-embed-text',
      prompt: input,
    }),
  });

  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }

  const data = await response.json();
  return data.embedding;
}