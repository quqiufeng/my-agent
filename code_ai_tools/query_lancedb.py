#!/usr/bin/env python3
import os
import argparse
import lancedb
from langchain_huggingface import HuggingFaceEmbeddings

DB_PATH = os.path.expanduser("~/lancedb_data")


def query_code(project_id, query_str, top_k=3):
    db = lancedb.connect(DB_PATH)

    try:
        table = db.open_table(project_id)
    except Exception as e:
        print(f"错误: 表 '{project_id}' 不存在 - {e}")
        return

    print(f"查询: {query_str}")
    print(f"项目: {project_id}")

    embeddings = HuggingFaceEmbeddings(
        model_name="BAAI/bge-small-zh-v1.5", model_kwargs={"device": "cpu"}
    )

    query_vector = embeddings.embed_query(query_str)

    results = table.search(query_vector).limit(top_k).to_list()

    print(f"\n找到 {len(results)} 条结果:\n")
    for i, row in enumerate(results, 1):
        print(f"--- 结果 {i} ({row['source']}) ---")
        print(row["text"][:500])
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LanceDB 代码检索")
    parser.add_argument("project_id", help="项目ID")
    parser.add_argument("query", help="查询内容")
    parser.add_argument("--top-k", type=int, default=3, help="返回结果数")
    args = parser.parse_args()

    query_code(args.project_id, args.query, args.top_k)
