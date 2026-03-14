#!/usr/bin/env python3
import os
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("LanceDBCodeSearch")

DB_PATH = os.path.expanduser("~/lancedb_data")


@mcp.tool()
def search_code(project_id: str = "sd_cpp", query: str = "", top_k: int = 3) -> str:
    import lancedb
    from langchain_huggingface import HuggingFaceEmbeddings

    if not project_id:
        return "错误: project_id 不能为空"

    db = lancedb.connect(DB_PATH)

    try:
        table = db.open_table(project_id)
    except Exception as e:
        return f"错误: 项目 '{project_id}' 不存在或数据库路径错误\n{str(e)}"

    embeddings = HuggingFaceEmbeddings(
        model_name="BAAI/bge-small-zh-v1.5", model_kwargs={"device": "cpu"}
    )

    query_vector = embeddings.embed_query(query)
    results = table.search(query_vector).limit(top_k).to_list()

    if not results:
        return f"未在项目 '{project_id}' 中找到与 '{query}' 相关的代码"

    output = []
    for i, row in enumerate(results, 1):
        source = row.get("source", "unknown")
        text = row.get("text", "")
        output.append(f"--- 结果 {i} ({source}) ---\n{text}")

    return "\n\n".join(output)


if __name__ == "__main__":
    print("启动 MCP 服务: LanceDBCodeSearch")
    print(f"数据库路径: {DB_PATH}")
    mcp.run(transport="stdio")
