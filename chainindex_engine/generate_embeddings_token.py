import sys
import json
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


def seed_token_embeddings(token_data_file, dbname, user, password):
    """
    Read token data from JSON file, generate embeddings, and seed them into pgvector.

    Args:
        token_data_file (str): Path to the JSON file containing token data.
        dbname (str): Database name.
        user (str): Database user.
        password (str): Database password.
    """
    # Read the token data from JSON file
    with open(token_data_file, "r") as f:
        tokens = json.load(f)

    if not tokens:
        print("No tokens found in the data file.")
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
            # Create token_embeddings table if it doesn't exist
            cur.execute("""
                CREATE TABLE IF NOT EXISTS token_embeddings (
                    id SERIAL PRIMARY KEY,
                    unit TEXT UNIQUE,
                    token_text TEXT,
                    embedding vector(768)
                );
            """)

            # Process each token
            for token in tokens:
                unit = token["unit"]
                # Create token_text from other attributes
                token_text = " ".join(
                    [
                        str(value)
                        for key, value in token.items()
                        if key != "unit" and value is not None
                    ]
                )
                try:
                    # Generate embedding
                    embedding = generate_embedding(token_text)
                    # Insert into database
                    cur.execute(
                        "INSERT INTO token_embeddings (unit, token_text, embedding) VALUES (%s, %s, %s) ON CONFLICT (unit) DO NOTHING",
                        (unit, token_text, embedding),
                    )
                    if cur.rowcount > 0:
                        print(f"Successfully seeded embedding for unit: {unit}")
                    else:
                        print(f"Unit {unit} already exists, skipped.")
                except Exception as e:
                    print(f"Failed to process unit {unit}: {e}")

        conn.commit()
    conn.close()
    print(f"Processed {len(tokens)} tokens for embedding seeding into {dbname}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(
            "Usage: python seed_token_embeddings.py <token_data_file> <dbname> <user> <password>"
        )
        sys.exit(1)
    token_data_file, dbname, user, password = sys.argv[1:5]
    seed_token_embeddings(token_data_file, dbname, user, password)
