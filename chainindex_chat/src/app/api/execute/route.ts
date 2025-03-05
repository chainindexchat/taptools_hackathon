import { getPool } from "@/server/providers/postgresProvider";
import { Parser } from "node-sql-parser";

const parser = new Parser();

// List of tables users are allowed to query
// const ALLOWED_TABLES = ["public_data1", "public_data2"]; // Adjust based on your needs

export async function POST(req: Request) {
  try {
    const { query } = await req.json();

    if (!query || typeof query !== "string") {
      return new Response(JSON.stringify({ error: "Invalid query" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Get a pool for the target database
    const pool = getPool("steampipe");

    // Set a statement timeout for all connections (e.g., 5 seconds)
    pool.on("connect", (client) => {
      client.query("SET statement_timeout = 5000;"); // Prevents DoS via long-running queries
    });

    // Log the query for auditing
    console.log(`Executing query: ${query}`);

    const result = await runGenerateSQLQuery(pool, query);
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Error running SQL:", e);
    return new Response(JSON.stringify({ error: e.message || "Failed to run SQL" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

export const runGenerateSQLQuery = async (client, query) => {
  // Step 1: Remove SQL comments to prevent comment-based injections
  const cleanQuery = query.replace(/--.*$|\/\*[\s\S]*?\*\//gm, "").trim();

  // Step 2: Validate query structure using SQL parser
  let ast;
  try {
    ast = parser.astify(cleanQuery);
  } catch (e) {
    throw new Error("Invalid SQL query syntax");
  }

  // Ensure it's a single SELECT statement
  if (Array.isArray(ast) || ast.type !== "select") {
    throw new Error("Only single SELECT queries are allowed");
  }

  // Step 3: Restrict to allowed tables
  const tables = ast.from.map((from) => from.table);
  for (const table of tables) {
    if (!ALLOWED_TABLES.includes(table)) {
      throw new Error(`Access to table '${table}' is not allowed`);
    }
  }


  // Step 4: Execute the validated query
  let data;
  try {
    data = await client.query(cleanQuery);
  } catch (e) {
    if (e.message.includes('relation "unicorns" does not exist')) {
      console.log("Table does not exist, creating and seeding it with dummy data now...");
      throw new Error("Table does not exist");
    }
    throw e;
  }

  return data.rows;
};