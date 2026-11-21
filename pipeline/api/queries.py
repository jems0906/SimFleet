from pathlib import Path

QUERY_DIR = Path(__file__).resolve().parents[2] / "db" / "queries"


def load_query(name: str) -> str:
    return (QUERY_DIR / f"{name}.sql").read_text(encoding="utf-8")