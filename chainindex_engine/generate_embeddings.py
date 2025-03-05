import sys
import re
import psycopg2
import requests
from pgvector.psycopg2 import register_vector


def generate_embedding(text):
    """
    Generate a 768-dimensional embedding from text using nomic-embed-text via Ollama.

    Args:
        text (str): The input text to embed.

    Returns:
        list: A 768-dimensional embedding vector.
    """
    url = "http://chainindex_engine:11434/api/embeddings"
    payload = {"model": "nomic-embed-text", "prompt": text}
    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        return response.json()["embedding"]
    except Exception as e:
        raise Exception(f"Embedding generation failed: {e}")


def extract_table_name_from_create(stmt):
    """
    Extract table name from CREATE FOREIGN TABLE statement.

    Args:
        stmt (str): The CREATE FOREIGN TABLE statement.

    Returns:
        str or None: The extracted table name, or None if not found.
    """
    match = re.search(
        r"CREATE FOREIGN TABLE\s+(\"[^\"]+\"(?:\.\"[^\"]+\")?|[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*))\s*\(",
        stmt,
        re.IGNORECASE,
    )
    return match.group(1) if match else None


def extract_table_name_from_comment_on_table(stmt):
    """
    Extract table name from COMMENT ON FOREIGN TABLE statement.

    Args:
        stmt (str): The COMMENT ON FOREIGN TABLE statement.

    Returns:
        str or None: The extracted table name, or None if not found.
    """
    match = re.search(
        r"COMMENT ON FOREIGN TABLE\s+(\"[^\"]+\"(?:\.\"[^\"]+\")?|[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*))\s+IS",
        stmt,
        re.IGNORECASE,
    )
    return match.group(1) if match else None


def extract_table_name_from_comment_on_column(stmt):
    """
    Extract table name from COMMENT ON COLUMN statement.

    Args:
        stmt (str): The COMMENT ON COLUMN statement.

    Returns:
        str or None: The extracted table name, or None if not found.
    """
    match = re.search(
        r"COMMENT ON COLUMN\s+(\"[^\"]+\"(?:\.\"[^\"]+\")?|[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*))\.(?:\"[^\"]+\"|[a-zA-Z_][a-zA-Z0-9_]*)\s+IS",
        stmt,
        re.IGNORECASE,
    )
    return match.group(1) if match else None


def parse_schema(schema_sql):
    """
    Parse the schema SQL to extract statements and group them by table name.

    Args:
        schema_sql (str): The SQL schema content.

    Returns:
        dict: A dictionary with table names as keys and lists of associated statements as values.
    """
    statements = re.findall(
        r"(?:CREATE FOREIGN TABLE|COMMENT ON FOREIGN TABLE|COMMENT ON COLUMN)[\s\S]*?;",
        schema_sql,
        re.DOTALL | re.IGNORECASE,
    )

    if not statements:
        print("No relevant statements found in the schema.")
        return {}

    table_groups = {}
    for stmt in statements:
        stmt = " ".join(stmt.split())  # Normalize whitespace
        if stmt.upper().startswith("CREATE FOREIGN TABLE"):
            table_name = extract_table_name_from_create(stmt)
        elif stmt.upper().startswith("COMMENT ON FOREIGN TABLE"):
            table_name = extract_table_name_from_comment_on_table(stmt)
        elif stmt.upper().startswith("COMMENT ON COLUMN"):
            table_name = extract_table_name_from_comment_on_column(stmt)
        else:
            table_name = None

        if table_name:
            if table_name not in table_groups:
                table_groups[table_name] = []
            table_groups[table_name].append(stmt)
        else:
            print(f"Failed to extract table name from statement:\n{stmt}")

    return table_groups


def normalize_schema_text(statements):
    """
    Normalize a list of statements by removing excessive whitespace.

    Args:
        statements (list): List of SQL statements.

    Returns:
        str: A single string with normalized whitespace, joined by newlines.
    """
    # Normalize each statement: collapse all whitespace into a single space, strip edges
    normalized_statements = [
        re.sub(r"\s+", " ", stmt).strip() for stmt in statements if stmt.strip()
    ]
    # Join with a single newline, filtering out any empty statements
    return "\n".join(normalized_statements)


def seed_embeddings(dump_file, dbname, user, password):
    """
    Read pg_dump output, generate embeddings, and seed them into pgvector.

    Args:
        dump_file (str): Path to the pg_dump file.
        dbname (str): Database name.
        user (str): Database user.
        password (str): Database password.
    """
    # Read the schema file
    with open(dump_file, "r") as f:
        schema_sql = f.read()

    # Parse schema into table groups
    table_groups = parse_schema(schema_sql)
    if not table_groups:
        print("No tables found to process.")
        sys.exit(1)

    # Connect to the database
    try:
        conn = psycopg2.connect(dbname=dbname, user=user, password=password)
        register_vector(conn)
    except Exception as e:
        print(f"Failed to connect to the database: {e}")
        sys.exit(1)

    with conn:
        with conn.cursor() as cur:
            # Create schema_embeddings table if it doesn’t exist
            cur.execute("""
                CREATE TABLE IF NOT EXISTS schema_embeddings (
                    id SERIAL PRIMARY KEY,
                    table_name TEXT,
                    schema_text TEXT,
                    embedding vector(768)
                );
            """)

            # Process each table
            for table_name, stmts in table_groups.items():
                print(f"Processing table: {table_name}")
                schema_text = normalize_schema_text(stmts)
                try:
                    # Generate embedding
                    embedding = generate_embedding(schema_text)
                    # Insert into database
                    cur.execute(
                        "INSERT INTO schema_embeddings (table_name, schema_text, embedding) VALUES (%s, %s, %s)",
                        (table_name, schema_text, embedding),
                    )
                    print(f"Successfully seeded embedding for table: {table_name}")
                except Exception as e:
                    print(f"Failed to process table {table_name}: {e}")

        conn.commit()
    conn.close()
    print(f"Seeded {len(table_groups)} embeddings into {dbname}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(
            "Usage: python generate_embeddings.py <dump_file> <dbname> <user> <password>"
        )
        sys.exit(1)
    dump_file, dbname, user, password = sys.argv[1:5]
    seed_embeddings(dump_file, dbname, user, password)
